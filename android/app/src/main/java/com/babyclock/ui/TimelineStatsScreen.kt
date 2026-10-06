package com.babyclock.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.babyclock.data.*
import com.babyclock.ui.theme.Warm
import java.util.Calendar

@Composable
fun TimelineScreen(vm: RecorderViewModel) {
    var dayOffset by remember { mutableIntStateOf(0) }
    val (dayStart, dayEnd) = remember(dayOffset) { dayRange(dayOffset) }
    val list = vm.eventsOnDay(dayStart, dayEnd)
    /// 被点开编辑的那条记录（§3.3 交互流程 3：点击记录 → 编辑面板）
    var editing by remember { mutableStateOf<BabyEvent?>(null) }

    Column(Modifier.fillMaxSize().background(Warm.Bg)) {
        Surface(color = Warm.Elevated) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                NavPill("‹") { dayOffset-- }
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(if (dayOffset == 0) "今天" else Format.day(dayStart),
                        style = MaterialTheme.typography.titleMedium, color = Warm.Text1)
                    Text(Format.day(dayStart), style = MaterialTheme.typography.labelSmall, color = Warm.Text2)
                }
                NavPill("›") { dayOffset++ }
            }
        }
        DayRibbon(
            events = vm.eventsOverlapping(dayStart, dayEnd, vm.now),
            dayStart = dayStart,
            dayEnd = dayEnd,
            now = vm.now,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
        )
        if (list.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                // §3.3 异常表：今天指向首页按钮，历史日期只做陈述
                Text(if (dayOffset == 0) "今天还没有记录，点首页按钮开始" else "这一天还没有记录",
                    color = Warm.Text3)
            }
        } else {
            LazyColumn(contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(list, key = { it.id }) { e ->
                    Box(Modifier.fillMaxWidth().clickable { editing = e }) { TimelineRow(e, vm.now) }
                }
            }
        }
    }

    editing?.let { e ->
        EventEditDialog(original = e, vm = vm, onDismiss = { editing = null })
    }
}

@Composable
private fun NavPill(label: String, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(50), color = Warm.Sunken) {
        Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) {
            Text(label, fontWeight = FontWeight.Bold, color = Warm.Text2)
        }
    }
}

private fun dayRange(offset: Int): Pair<Long, Long> {
    val c = Calendar.getInstance().apply {
        add(Calendar.DAY_OF_YEAR, offset)
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }
    val start = c.timeInMillis
    return start to start + 86_400_000L
}

private data class Lane(val type: EventType, val label: String)

private val ribbonLanes = listOf(
    Lane(EventType.FEED, "喂养"),
    Lane(EventType.SLEEP, "睡觉"),
    Lane(EventType.MEDICINE, "吃药"),
    Lane(EventType.POOP, "排便")
)

/** 24 小时活动带（PRD §3.4.1）：横轴 0–24 点，四泳道展示宝宝几点做了什么。 */
@Composable
fun DayRibbon(
    events: List<BabyEvent>,
    dayStart: Long,
    dayEnd: Long,
    now: Long,
    modifier: Modifier = Modifier
) {
    val isToday = now in dayStart until dayEnd
    val density = LocalDensity.current
    val labelW = 40.dp
    val laneH = 30.dp
    val span = (dayEnd - dayStart).toFloat()

    Column(
        modifier = modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(Warm.Elevated).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text("24 小时活动带", style = MaterialTheme.typography.labelMedium, color = Warm.Text2)
        Spacer(Modifier.height(2.dp))

        ribbonLanes.forEach { lane ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(labelW)) {
                    Text(lane.label, fontSize = 11.sp, color = Warm.Text2)
                }
                Canvas(Modifier.weight(1f).height(laneH)) {
                    val W = size.width
                    val H = size.height
                    val trackY = H / 2f
                    val barH = with(density) { 12.dp.toPx() }
                    val minBar = with(density) { 3.dp.toPx() }
                    val rDot = with(density) { 4.5.dp.toPx() }
                    val rFormula = with(density) { 5.5.dp.toPx() }
                    val corner = CornerRadius(barH / 2f, barH / 2f)

                    fun xOf(t: Long): Float =
                        ((t - dayStart).coerceIn(0L, dayEnd - dayStart) / span) * W

                    // 轨道底色
                    drawRoundRect(
                        color = Warm.Sunken,
                        topLeft = Offset(0f, trackY - barH / 2f),
                        size = Size(W, barH),
                        cornerRadius = corner
                    )

                    events.filter { it.type == lane.type }.forEach { e ->
                        val color = Warm.fill(lane.type)
                        when {
                            Format.isFormula(e) -> if (e.startAt in dayStart until dayEnd) {
                                val c = Offset(xOf(e.startAt), trackY)
                                drawCircle(color = color, radius = rFormula, center = c)
                                drawCircle(color = Color.White, radius = rFormula * 0.4f, center = c)
                            }
                            e.type.isInterval -> {
                                val s = maxOf(e.startAt, dayStart)
                                val en = minOf(e.endAt ?: now, dayEnd)
                                if (en > s) {
                                    val x1 = xOf(s)
                                    var x2 = xOf(en)
                                    if (x2 - x1 < minBar) x2 = x1 + minBar
                                    drawRoundRect(
                                        color = color,
                                        topLeft = Offset(x1, trackY - barH / 2f),
                                        size = Size(x2 - x1, barH),
                                        cornerRadius = corner
                                    )
                                }
                            }
                            else -> if (e.startAt in dayStart until dayEnd) {
                                drawCircle(color = color, radius = rDot, center = Offset(xOf(e.startAt), trackY))
                            }
                        }
                    }

                    if (isToday) {
                        val xn = xOf(now)
                        drawLine(
                            color = Warm.PrimaryStrong,
                            start = Offset(xn, 0f),
                            end = Offset(xn, H),
                            strokeWidth = with(density) { 1.5.dp.toPx() }
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(2.dp))
        Row(
            Modifier.fillMaxWidth().padding(start = labelW),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            listOf("0", "6", "12", "18", "24").forEach { h ->
                Text(h, fontSize = 10.sp, color = Warm.Text3)
            }
        }
    }
}

enum class StatsRange(val label: String) { TODAY("今日"), WEEK("近 7 天") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(vm: RecorderViewModel) {
    var range by remember { mutableStateOf(StatsRange.TODAY) }
    val now = vm.now
    val (from, to) = when (range) {
        StatsRange.TODAY -> dayRange(0).let { it.first to now }
        StatsRange.WEEK -> dayRange(-6).first to now
    }
    val inWin = vm.events.filter { it.startAt in from..to }

    fun count(t: EventType) = inWin.count { it.type == t }
    val feedSec = inWin.filter { it.type == EventType.FEED }.sumOf { it.durationMs(now) }
    /** 奶量口径（§3.4.2 / AC-8）：毫升只累计 FORMULA 零时长段，母乳有时长无毫升、不计入。 */
    val formulaMl = inWin.filter { it.isFormula }.sumOf { it.volumeMl ?: 0 }
    val sleepEvents = inWin.filter { it.type == EventType.SLEEP }
    val sleepTotal = sleepEvents.sumOf { it.durationMs(now) }

    Column(Modifier.fillMaxSize().background(Warm.Bg).verticalScroll(rememberScrollState())
        .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {

        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            StatsRange.values().forEachIndexed { i, r ->
                SegmentedButton(selected = range == r,
                    onClick = { range = r },
                    shape = SegmentedButtonDefaults.itemShape(index = i, count = StatsRange.values().size)) {
                    Text(r.label)
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.weight(1f)) {
                StatCard("🍼 吃奶", "${count(EventType.FEED)} 次",
                    "母乳 ${Format.duration(feedSec)} · 奶粉 ${formulaMl}ml")
            }
            Box(Modifier.weight(1f)) { StatCard("😴 睡觉", Format.duration(sleepTotal), "${sleepEvents.size} 段") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.weight(1f)) { StatCard("💊 吃药", "${count(EventType.MEDICINE)} 次", "瞬时记录") }
            Box(Modifier.weight(1f)) { StatCard("🧷 排便", "${count(EventType.POOP)} 次", "瞬时记录") }
        }

        // §3.4.2 近 7 天趋势（P1）：始终展示最近 7 天，与上方今日/近7天数字汇总切换无关
        TrendCard(vm)
    }
}

// MARK: - §3.4.2 近 7 天趋势（P1）

/** 趋势图可切换指标（§3.4.2 表）。奶量仅统计 FORMULA，母乳不计入（口径约束见 §3.4.2）。 */
private enum class TrendMetric(val label: String, val unit: String) {
    FORMULA_ML("奶量", "ml"),
    FEED_COUNT("喂奶", "次"),
    SLEEP_MINUTES("睡眠时长", "分钟"),
    SLEEP_SEGMENTS("睡眠段数", "段"),
    POOP_COUNT("排便", "次"),
    MEDICINE_COUNT("吃药", "次")
}

/** 单日聚合桶。 */
private data class DayBucket(
    val dayStart: Long,
    val label: String,
    var formulaMl: Int = 0,
    var breastCount: Int = 0,
    var feedCount: Int = 0,
    var sleepMinutes: Double = 0.0,
    var sleepSegments: Int = 0,
    var poopCount: Int = 0,
    var medicineCount: Int = 0
) {
    fun value(m: TrendMetric): Double = when (m) {
        TrendMetric.FORMULA_ML -> formulaMl.toDouble()
        TrendMetric.FEED_COUNT -> feedCount.toDouble()
        TrendMetric.SLEEP_MINUTES -> sleepMinutes
        TrendMetric.SLEEP_SEGMENTS -> sleepSegments.toDouble()
        TrendMetric.POOP_COUNT -> poopCount.toDouble()
        TrendMetric.MEDICINE_COUNT -> medicineCount.toDouble()
    }
}

/** 近 7 天趋势卡：按天聚合柱状图 + 指标切换 + 奶量口径标注（AC-8 / AC-18）。 */
@Composable
fun TrendCard(vm: RecorderViewModel) {
    var metric by remember { mutableStateOf(TrendMetric.FEED_COUNT) }
    val buckets = buildBuckets(vm.events, vm.now)
    val maxValue = buckets.maxOfOrNull { it.value(metric) } ?: 0.0

    Surface(shape = RoundedCornerShape(18.dp), color = Warm.Elevated,
        shadowElevation = 4.dp, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("近 7 天趋势", style = MaterialTheme.typography.labelLarge,
                color = Warm.Text2, fontWeight = FontWeight.Bold)

            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TrendMetric.values().forEach { m ->
                    val on = m == metric
                    Box(
                        Modifier.clip(RoundedCornerShape(50))
                            .background(if (on) Warm.PrimaryStrong else Warm.PrimarySoft)
                            .clickable { metric = m }
                            .padding(horizontal = 12.dp, vertical = 6.dp)
                    ) {
                        Text(m.label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                            color = if (on) Color.White else Warm.PrimaryStrong)
                    }
                }
            }

            // 柱状图：无数据时各柱保留 2dp 基线（§3.4 异常表"零值占位"）
            Row(
                Modifier.fillMaxWidth().height(160.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom
            ) {
                buckets.forEach { b ->
                    val v = b.value(metric)
                    val h = if (maxValue <= 0.0 || v <= 0.0) 2.dp
                        else (96.dp * (v / maxValue).toFloat()).coerceAtLeast(2.dp)
                    Column(
                        Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Box(Modifier.fillMaxWidth().height(h).clip(RoundedCornerShape(4.dp))
                            .background(Warm.Primary))
                        Text(b.label, fontSize = 10.sp, color = Warm.Text3)
                    }
                }
            }

            Text(trendCaption(buckets, metric), style = MaterialTheme.typography.labelSmall,
                color = Warm.Text3)
        }
    }
}

/**
 * 口径标注（§3.4.2 约束）：奶量只含奶粉，并显式说明母乳次数未计入 ——
 * 禁用"总摄入量/达标"等表述。
 */
private fun trendCaption(buckets: List<DayBucket>, metric: TrendMetric): String {
    val total = buckets.sumOf { it.value(metric) }
    return when {
        total <= 0.0 -> "暂无数据"
        metric == TrendMetric.FORMULA_ML ->
            "奶粉量合计 ${buckets.sumOf { it.formulaMl }}ml · 母乳 ${buckets.sumOf { it.breastCount }} 次未计入"
        else -> "单位：${metric.unit}"
    }
}

/** 构建最近 7 天（含今天）的聚合桶。睡眠时长按 splitByDay 跨天归属（AC-12）；其余按 startAt 所属自然日。 */
private fun buildBuckets(events: List<BabyEvent>, now: Long): List<DayBucket> {
    val fmt = java.text.SimpleDateFormat("M/d", java.util.Locale.getDefault())
    val buckets = (6 downTo 0).map { off ->
        val start = dayRange(-off).first
        DayBucket(dayStart = start, label = fmt.format(java.util.Date(start)))
    }.toMutableList()
    val idx = buckets.withIndex().associate { (i, b) -> b.dayStart to i }

    events.forEach { e ->
        val startDay = dayRangeOf(e.startAt)
        val i = idx[startDay] ?: return@forEach
        when {
            e.isFormula -> { buckets[i].formulaMl += e.volumeMl ?: 0; buckets[i].feedCount++ }
            e.type == EventType.FEED -> { buckets[i].breastCount++; buckets[i].feedCount++ }
            e.type == EventType.SLEEP -> {
                DaySplitter.splitByDay(e.startAt, e.endAt ?: now).forEach { (day, ms) ->
                    idx[day]?.let { buckets[it].sleepMinutes += ms / 60_000.0 }
                }
                buckets[i].sleepSegments++
            }
            e.type == EventType.POOP -> buckets[i].poopCount++
            else -> buckets[i].medicineCount++
        }
    }
    return buckets
}

/** startAt 所属本地自然日的 00:00。 */
private fun dayRangeOf(ms: Long): Long {
    val c = Calendar.getInstance().apply { timeInMillis = ms }
    c.set(Calendar.HOUR_OF_DAY, 0); c.set(Calendar.MINUTE, 0)
    c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
    return c.timeInMillis
}

@Composable
private fun StatCard(title: String, value: String, sub: String) {
    Surface(shape = RoundedCornerShape(18.dp), color = Warm.Elevated,
        shadowElevation = 4.dp, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(value, style = MaterialTheme.typography.headlineMedium, color = Warm.Text1)
            Text(title, style = MaterialTheme.typography.labelMedium, color = Warm.Text2)
            Text(sub, style = MaterialTheme.typography.labelSmall, color = Warm.Text3)
        }
    }
}

// MARK: - §3.3 规则 3/4：记录编辑与删除（AC-6 / AC-7）

/**
 * 时间轴编辑面板：类型、时刻、备注，奶粉另给毫升、母乳另给左右侧、排便另给小便/大便；删除需二次确认。
 * 三条口径与状态机保持一致（与 iOS EventEditPanel 逐条对齐）：
 * - 奶粉是零时长段（I4）：只给一个时刻选择器，endAt 由 update 跟随 startAt；
 * - 进行中的段只改开始时刻，结束时刻仍由首页的「结束」决定（I2）；
 * - 结束早于开始就地拦下，不落库（AC-7）。
 */
@Composable
fun EventEditDialog(original: BabyEvent, vm: RecorderViewModel, onDismiss: () -> Unit) {
    var type by remember(original) { mutableStateOf(original.type) }
    var method by remember(original) { mutableStateOf(original.feedMethod ?: FeedMethod.BREAST) }
    var startAt by remember(original) { mutableLongStateOf(original.startAt) }
    var endAt by remember(original) { mutableLongStateOf(original.endAt ?: original.startAt) }
    var side by remember(original) { mutableStateOf(original.breastSide) }
    var diaper by remember(original) { mutableStateOf(original.diaperKind) }
    var volume by remember(original) { mutableStateOf(original.volumeMl?.toString() ?: "") }
    var note by remember(original) { mutableStateOf(original.note ?: "") }
    var error by remember(original) { mutableStateOf<String?>(null) }
    var confirmDelete by remember(original) { mutableStateOf(false) }
    var pendingLarge by remember(original) { mutableStateOf<Int?>(null) }
    /** 已完成 >500ml 二次确认，避免再次进同一分支反复弹窗 */
    var largeConfirmed by remember(original) { mutableStateOf(false) }

    val isFormula = type == EventType.FEED && method == FeedMethod.FORMULA
    /** 只有"时间段 + 非奶粉 + 已结束"才有独立的结束时刻选择器 */
    val showsEnd = type.isInterval && !isFormula && !original.ongoing

    fun save() {
        error = null
        val ml = volume.toIntOrNull()
        var e = original.copy(
            type = type,
            startAt = startAt,
            // 非吃奶事件不保留吃奶形态；形态决定毫升与左右侧谁有效
            feedMethod = if (type == EventType.FEED) method else null,
            volumeMl = null,
            breastSide = if (type == EventType.FEED && method == FeedMethod.BREAST) side else null,
            // 类别只属于排便：改成别的类型就清掉，否则一条"吃药"会带着"小便"的标题
            diaperKind = if (type == EventType.POOP) diaper else null,
            note = note.trim().ifEmpty { null }
        )
        when {
            !type.isInterval -> e = e.copy(endAt = null, ongoing = false)
            isFormula -> {
                if (ml == null || ml <= 0) {
                    error = StoreErrorText.text(MachineError.INVALID_VOLUME); return
                }
                if (ml > 500 && !largeConfirmed) { pendingLarge = ml; return }
                e = e.copy(volumeMl = ml, endAt = startAt, ongoing = false)
            }
            original.ongoing -> e = e.copy(endAt = null, ongoing = true)
            else -> {
                if (endAt < startAt) {
                    error = StoreErrorText.text(MachineError.INVALID_INTERVAL); return
                }
                e = e.copy(endAt = endAt, ongoing = false)
            }
        }
        vm.update(e)
        onDismiss()
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("编辑记录") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {

                FieldLabel("类型")
                ChipRow(EventType.values().toList(), type, { it.title }) { type = it }
                if (type == EventType.FEED) {
                    ChipRow(FeedMethod.values().toList(), method,
                        { if (it == FeedMethod.FORMULA) "奶粉" else "母乳" }) { method = it }
                }

                FieldLabel("时刻")
                TimeField(if (original.ongoing || isFormula) "发生时刻" else "开始时刻", startAt) { startAt = it }
                when {
                    showsEnd -> TimeField("结束时刻", endAt) { endAt = it }
                    isFormula -> Hint("奶粉是一条时刻记录，没有时长")
                    original.ongoing -> Hint("这段仍在进行中，结束时刻由首页的「结束」决定")
                }

                if (isFormula) {
                    FieldLabel("毫升数")
                    OutlinedTextField(
                        value = volume,
                        onValueChange = { volume = it.filter(Char::isDigit).take(4) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                } else if (type == EventType.FEED) {
                    FieldLabel("左右侧")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        BreastSide.values().forEach { s ->
                            EditChip(Format.side(s), selected = side == s) {
                                side = if (side == s) null else s
                            }
                        }
                    }
                } else if (type == EventType.POOP) {
                    FieldLabel("小便 / 大便")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DiaperKind.values().forEach { k ->
                            EditChip(Format.diaper(k), selected = diaper == k) {
                                diaper = if (diaper == k) null else k
                            }
                        }
                    }
                }

                FieldLabel("备注")
                OutlinedTextField(value = note, onValueChange = { note = it }, modifier = Modifier.fillMaxWidth())

                error?.let { Text(it, color = Color(0xFFD33A2C), style = MaterialTheme.typography.labelMedium) }
            }
        },
        confirmButton = { TextButton(onClick = { save() }) { Text("保存") } },
        dismissButton = { TextButton(onClick = { confirmDelete = true }) { Text("删除这条记录") } }
    )

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("删除这条记录？") },
            text = {
                Text(if (original.ongoing) "这段还在进行中，删除后回到「无进行中」。" else "删除后无法恢复。")
            },
            confirmButton = {
                TextButton(onClick = { vm.delete(original); confirmDelete = false; onDismiss() }) {
                    Text("删除", color = Color(0xFFD33A2C))
                }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("取消") } }
        )
    }

    pendingLarge?.let { ml ->
        AlertDialog(
            onDismissRequest = { pendingLarge = null },
            title = { Text("确认毫升数") },
            text = { Text("一次喝了 ${ml}ml 以上？") },
            confirmButton = {
                TextButton(onClick = { pendingLarge = null; largeConfirmed = true; save() }) { Text("确认") }
            },
            dismissButton = { TextButton(onClick = { pendingLarge = null }) { Text("返回修改") } }
        )
    }
}

@Composable
private fun FieldLabel(text: String) {
    Text(text, style = MaterialTheme.typography.labelMedium,
        color = Warm.Text2, fontWeight = FontWeight.Bold)
}

@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.labelSmall, color = Warm.Text3)
}

@Composable
private fun <T> ChipRow(values: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        values.forEach { v ->
            EditChip(label(v), selected = v == selected) { onSelect(v) }
        }
    }
}

@Composable
private fun EditChip(text: String, selected: Boolean = false, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        color = if (selected) Warm.PrimaryStrong else Warm.PrimarySoft
    ) {
        Box(Modifier.padding(horizontal = 14.dp, vertical = 9.dp)) {
            Text(text,
                fontSize = 13.sp, fontWeight = FontWeight.Bold,
                color = if (selected) Color.White else Warm.Text1)
        }
    }
}

/** 一行时刻：当前值 + 日期 / 时间两个选择入口。 */
@Composable
private fun TimeField(label: String, ms: Long, onChange: (Long) -> Unit) {
    val ctx = LocalContext.current
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = Warm.Text2,
            modifier = Modifier.weight(1f))
        Text("${Format.day(ms).substringBefore(" ")} ${Format.clock(ms)}",
            style = MaterialTheme.typography.labelMedium, color = Warm.Text1)
        EditChip("日期") { pickDate(ctx, ms, onChange) }
        EditChip("时间") { pickTime(ctx, ms, onChange) }
    }
}

// 系统 DatePickerDialog / TimePickerDialog：Material3 1.6 没有现成的弹窗式日期选择器，
// 用系统对话框可避免为此再加依赖。
private fun pickDate(ctx: android.content.Context, ms: Long, onPicked: (Long) -> Unit) {
    val c = Calendar.getInstance().apply { timeInMillis = ms }
    android.app.DatePickerDialog(ctx, { _, y, m, d ->
        val n = Calendar.getInstance().apply {
            timeInMillis = ms   // 用字段逐个 set：set(y, m, d) 会把时分秒清零
            set(Calendar.YEAR, y); set(Calendar.MONTH, m); set(Calendar.DAY_OF_MONTH, d)
        }
        onPicked(n.timeInMillis)
    }, c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)).show()
}

private fun pickTime(ctx: android.content.Context, ms: Long, onPicked: (Long) -> Unit) {
    val c = Calendar.getInstance().apply { timeInMillis = ms }
    android.app.TimePickerDialog(ctx, { _, h, min ->
        val n = Calendar.getInstance().apply {
            timeInMillis = ms
            set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, min); set(Calendar.SECOND, 0)
        }
        onPicked(n.timeInMillis)
    }, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), true).show()
}

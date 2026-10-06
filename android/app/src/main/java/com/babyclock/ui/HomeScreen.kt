package com.babyclock.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.babyclock.data.*
import com.babyclock.ui.theme.Warm

/** iOS squircle 圆角图标容器（22% 圆角） */
@Composable
fun SquircleIcon(type: EventType, size: Int = 58, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(RoundedCornerShape(percent = 22))
            .background(Warm.soft(type)),
        contentAlignment = Alignment.Center
    ) { content() }
}

@Composable
fun EventGlyph(type: EventType, size: Int = 30) {
    Text(Format.emoji(type), fontSize = (size * 0.6).sp)
}

/** 首页五个记录动作：吃奶在 UI 层拆为母乳 / 奶粉（PRD §3.1）。 */
private enum class HomeAction(val label: String, val emoji: String, val type: EventType) {
    BREAST("母乳", "🤱", EventType.FEED),
    FORMULA("奶粉", "🍼", EventType.FEED),
    SLEEP("睡觉", "😴", EventType.SLEEP),
    MEDICINE("吃药", "💊", EventType.MEDICINE),
    POOP("排便", "🧷", EventType.POOP)
}

@Composable
fun HomeScreen(vm: RecorderViewModel, onOpenTimeline: () -> Unit, initialFormula: Boolean = false) {
    var showFormula by remember { mutableStateOf(initialFormula) }
    /** 刚结束的那段母乳 id：非空即等待补填左右侧（§3.1 规则 5，可跳过）。 */
    var pendingSideId by remember { mutableStateOf<String?>(null) }
    /** 刚落库的那条排便 id：非空即等待补填小便/大便（同一手法，同样可跳过）。 */
    var pendingDiaperId by remember { mutableStateOf<String?>(null) }
    val ongoing = vm.ongoing
    val ongoingType = ongoing?.type

    fun click(a: HomeAction) {
        if (a == HomeAction.FORMULA) { showFormula = true; return }
        // 这次点击结束了一段母乳 → 段已落库，随后追问一次左右侧（可跳过，不阻断已完成的记录）
        if (a == HomeAction.BREAST && ongoingType == EventType.FEED) {
            vm.submit(a.type, RecordSource.APP)
            pendingSideId = ongoing?.id
            return
        }
        // 排便先落库再追问"这一次是"：一键仍然记录成功，下滑关面板 = 跳过，字段保持 null 显示"排便"。
        if (a == HomeAction.POOP) {
            vm.submit(a.type, RecordSource.APP) { pendingDiaperId = it.id }
            return
        }
        vm.submit(a.type, RecordSource.APP)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Warm.Bg)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        StatusCard(vm)
        Text("轻点记录", style = MaterialTheme.typography.labelMedium, color = Warm.Text2)

        val actions = HomeAction.values().toList()
        // 3 行：[母乳 奶粉] [睡觉 吃药] [排便 —]
        actions.chunked(2).forEach { rowActions ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                rowActions.forEach { a ->
                    Box(Modifier.weight(1f)) {
                        HomeButton(
                            action = a,
                            ongoing = (a == HomeAction.BREAST && ongoingType == EventType.FEED) ||
                                      (a == HomeAction.SLEEP && ongoingType == EventType.SLEEP),
                            onClick = { click(a) }
                        )
                    }
                }
                if (rowActions.size == 1) Spacer(Modifier.weight(1f))
            }
        }

        Text("今天时间轴", style = MaterialTheme.typography.labelMedium, color = Warm.Text2)
        val cal = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
        }
        val dayStart = cal.timeInMillis
        val dayEnd = dayStart + 86_400_000L
        val list = vm.eventsOnDay(dayStart, dayEnd).take(3)
        if (list.isEmpty()) {
            Text("今天还没有记录，点上方按钮开始", style = MaterialTheme.typography.labelSmall, color = Warm.Text3)
        } else {
            list.forEach { TimelineRow(it, vm.now) }
        }
    }

    if (showFormula) {
        FormulaSheet(
            onDismiss = { showFormula = false },
            onConfirm = { ml -> vm.submitFormula(ml, RecordSource.APP); showFormula = false }
        )
    }

    pendingSideId?.let { id ->
        OptionalChoiceSheet(
            prompt = "这一段是哪一侧？",
            options = BreastSide.values().toList(),
            titleOf = Format::side,
            onPick = { side -> vm.setBreastSide(side, id); pendingSideId = null },
            onDismiss = { pendingSideId = null }
        )
    }

    pendingDiaperId?.let { id ->
        OptionalChoiceSheet(
            prompt = "这一次是？",
            options = DiaperKind.values().toList(),
            titleOf = Format::diaper,
            onPick = { kind -> vm.setDiaperKind(kind, id); pendingDiaperId = null },
            onDismiss = { pendingDiaperId = null }
        )
    }
}

/**
 * "先落库、再追问"的一次点选（PRD §3.1 规则 5）：母乳左右侧与排便小便/大便共用这一形态。
 * 每一项都可选，也可整块跳过（点跳过或下滑关闭）—— 跳过后字段为空，记录本身已经落库不受影响，
 * 事后可在时间轴编辑里补填（§3.3 规则 3）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> OptionalChoiceSheet(
    prompt: String,
    options: List<T>,
    titleOf: (T) -> String,
    onPick: (T?) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Warm.Elevated) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(prompt, style = MaterialTheme.typography.titleLarge, color = Warm.Text1)
            Text("可跳过，之后在时间轴里补填", style = MaterialTheme.typography.labelSmall, color = Warm.Text2)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                options.forEach { option ->
                    Surface(
                        onClick = { onPick(option) },
                        shape = RoundedCornerShape(14.dp),
                        color = Warm.PrimarySoft,
                        modifier = Modifier.weight(1f)
                    ) {
                        Box(Modifier.fillMaxWidth().padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
                            Text(titleOf(option), color = Warm.PrimaryStrong,
                                fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        }
                    }
                }
            }
            TextButton(onClick = { onPick(null) }, modifier = Modifier.fillMaxWidth()) {
                Text("跳过", color = Warm.Text2)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StatusCard(vm: RecorderViewModel) {
    val o = vm.ongoing
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(Brush.linearGradient(listOf(Warm.Primary, Warm.PrimaryStrong)))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (o != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).clip(RoundedCornerShape(50)).background(Color.White))
                Spacer(Modifier.width(8.dp))
                Text("正在进行 · ${Format.label(o)}", color = Color.White.copy(alpha = .92f),
                    style = MaterialTheme.typography.labelMedium)
            }
            Text(Format.hms(vm.now - o.startAt), color = Color.White,
                fontSize = 40.sp, fontWeight = FontWeight.ExtraBold)
            Text("开始于 ${Format.clock(o.startAt)} · 再次点击「${Format.label(o)}」可结束",
                color = Color.White.copy(alpha = .9f), style = MaterialTheme.typography.labelSmall)
        } else {
            Text("当前无进行中的活动", color = Color.White, style = MaterialTheme.typography.titleMedium)
            Text("点下方按钮开始记录", color = Color.White.copy(alpha = .9f),
                style = MaterialTheme.typography.labelSmall)
        }
        // §3.2 规则5：突出"距上次喂奶"（母乳/奶粉更近的一次），字号高于下方五项；仅客观事实、无判断性文案
        val lastFeed = listOfNotNull(vm.lastBreast(), vm.lastFormula()).maxByOrNull { it.startAt }
        if (lastFeed != null) {
            Spacer(Modifier.height(2.dp))
            Text(Format.feedHighlight(lastFeed, vm.now), color = Color.White,
                fontSize = 17.sp, fontWeight = FontWeight.Bold)
        }

        Spacer(Modifier.height(4.dp))
        // §3.2 规则3/6：五项"距上次"（母乳带侧别与时长、奶粉带毫升、排便带小便/大便），超宽自动换行
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            vm.lastBreast()?.let { StatusChip(Format.breastChip(it, vm.now)) }
            vm.lastFormula()?.let { StatusChip(Format.formulaChip(it, vm.now)) }
            listOf(EventType.SLEEP, EventType.MEDICINE).forEach { t ->
                vm.lastOccurrence(t)?.let { StatusChip("${Format.emoji(t)} ${Format.relative(it, vm.now)}") }
            }
            vm.lastPoop()?.let { StatusChip(Format.poopChip(it, vm.now)) }
        }
    }
}

/** 状态卡"距上次"胶囊（§3.2 规则3）。 */
@Composable
private fun StatusChip(text: String) {
    Box(Modifier.clip(RoundedCornerShape(50))
        .background(Color.White.copy(alpha = .18f))
        .padding(horizontal = 10.dp, vertical = 5.dp)) {
        Text(text, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun HomeButton(action: HomeAction, ongoing: Boolean, onClick: () -> Unit) {
    val hint = when {
        ongoing -> "进行中"
        action == HomeAction.FORMULA -> "记毫升"
        action.type.isInterval -> "时间段"
        else -> "瞬时"
    }
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(20.dp),
        color = if (ongoing) Warm.PrimarySoft else Warm.Elevated,
        shadowElevation = 6.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(vertical = 18.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SquircleIcon(action.type) { Text(action.emoji, fontSize = 26.sp) }
            Text(action.label, style = MaterialTheme.typography.labelLarge, color = Warm.Text1)
            Text(hint, style = MaterialTheme.typography.labelSmall,
                color = if (ongoing) Warm.PrimaryStrong else Warm.Text3,
                fontWeight = if (ongoing) FontWeight.Bold else FontWeight.Normal)
        }
    }
}

/** 奶粉毫升快选面板（PRD §3.1）：档位直点即记录，自定义需校验，>500ml 二次确认。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FormulaSheet(onDismiss: () -> Unit, onConfirm: (Int) -> Unit) {
    var custom by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var pendingLarge by remember { mutableStateOf<Int?>(null) }

    fun commit(v: Int?) {
        if (v == null || v <= 0) { error = "请输入有效的毫升数"; return }
        error = null
        if (v > 500) { pendingLarge = v; return }
        onConfirm(v)
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Warm.Elevated) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text("奶粉 · 毫升数", style = MaterialTheme.typography.titleLarge, color = Warm.Text1)
            Text("点档位立即记录，或输入自定义毫升", style = MaterialTheme.typography.labelSmall, color = Warm.Text2)

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(30, 60, 90, 120, 150).forEach { ml ->
                    Surface(
                        onClick = { commit(ml) },
                        shape = RoundedCornerShape(14.dp),
                        color = Warm.PrimarySoft,
                        modifier = Modifier.weight(1f)
                    ) {
                        Box(Modifier.fillMaxWidth().padding(vertical = 14.dp), contentAlignment = Alignment.Center) {
                            Text("$ml", color = Warm.PrimaryStrong, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        }
                    }
                }
            }

            OutlinedTextField(
                value = custom,
                onValueChange = { custom = it.filter(Char::isDigit).take(4) },
                label = { Text("自定义毫升") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth()
            )
            error?.let {
                Text(it, color = Color(0xFFD33A2C), style = MaterialTheme.typography.labelSmall)
            }
            Button(
                onClick = { commit(custom.toIntOrNull()) },
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth()
            ) { Text("记录奶粉") }
        }
    }

    pendingLarge?.let { ml ->
        AlertDialog(
            onDismissRequest = { pendingLarge = null },
            title = { Text("确认毫升数") },
            text = { Text("一次喝了 ${ml}ml 以上？") },
            confirmButton = { TextButton(onClick = { pendingLarge = null; onConfirm(ml) }) { Text("确认") } },
            dismissButton = { TextButton(onClick = { pendingLarge = null }) { Text("返回修改") } }
        )
    }
}

@Composable
fun TimelineRow(e: BabyEvent, now: Long) {
    val formula = Format.isFormula(e)
    Surface(
        shape = RoundedCornerShape(16.dp), color = Warm.Elevated,
        shadowElevation = 4.dp, modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SquircleIcon(e.type, 40) {
                Text(Format.icon(e), fontSize = 16.sp)
            }
            Column(Modifier.weight(1f)) {
                Text(
                    if (e.ongoing) "${Format.label(e)} · 进行中" else Format.label(e),
                    style = MaterialTheme.typography.labelLarge, color = Warm.Text1
                )
                Text(Format.subtitle(e), style = MaterialTheme.typography.labelSmall, color = Warm.Text2)
            }
            when {
                formula -> Box(
                    Modifier.clip(RoundedCornerShape(50)).background(Warm.PrimarySoft)
                        .padding(horizontal = 9.dp, vertical = 3.dp)
                ) {
                    Text("${e.volumeMl ?: 0}ml", color = Warm.PrimaryStrong,
                        fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
                }
                e.type.isInterval -> {
                    val txt = if (e.ongoing) Format.hms(now - e.startAt) else Format.duration(e.durationMs(now))
                    Box(
                        Modifier.clip(RoundedCornerShape(50)).background(Warm.PrimarySoft)
                            .padding(horizontal = 9.dp, vertical = 3.dp)
                    ) {
                        Text(txt, color = Warm.PrimaryStrong, fontSize = 11.sp, fontWeight = FontWeight.ExtraBold)
                    }
                }
                else -> Text("瞬时", style = MaterialTheme.typography.labelSmall, color = Warm.Text3)
            }
        }
    }
}

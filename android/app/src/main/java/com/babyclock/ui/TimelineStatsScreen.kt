package com.babyclock.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
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
                Text("这一天还没有记录", color = Warm.Text3)
            }
        } else {
            LazyColumn(contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(list, key = { it.id }) { TimelineRow(it, vm.now) }
            }
        }
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
    val sleepEvents = inWin.filter { it.type == EventType.SLEEP }
    val sleepTotal = sleepEvents.sumOf { it.durationMs(now) }

    Column(Modifier.fillMaxSize().background(Warm.Bg).padding(16.dp),
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
            Box(Modifier.weight(1f)) { StatCard("🍼 吃奶", "${count(EventType.FEED)} 次", "共 ${Format.duration(feedSec)}") }
            Box(Modifier.weight(1f)) { StatCard("😴 睡觉", Format.duration(sleepTotal), "${sleepEvents.size} 段") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.weight(1f)) { StatCard("💊 吃药", "${count(EventType.MEDICINE)} 次", "瞬时记录") }
            Box(Modifier.weight(1f)) { StatCard("🧷 排便", "${count(EventType.POOP)} 次", "瞬时记录") }
        }
    }
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

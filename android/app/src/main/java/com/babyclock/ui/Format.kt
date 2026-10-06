package com.babyclock.ui

import com.babyclock.data.BabyEvent
import com.babyclock.data.BreastSide
import com.babyclock.data.DiaperKind
import com.babyclock.data.EventType
import com.babyclock.data.FeedMethod
import java.text.SimpleDateFormat
import java.util.*

object Format {
    private val clockFmt = SimpleDateFormat("HH:mm", Locale.getDefault())
    private val dayFmt = SimpleDateFormat("yyyy年M月d日 EEE", Locale.CHINA)

    fun clock(ms: Long): String = clockFmt.format(Date(ms))
    fun day(ms: Long): String = dayFmt.format(Date(ms))

    /** HH:MM:SS */
    fun hms(ms: Long): String {
        val s = ms / 1000
        return String.format(Locale.US, "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /** 人性化时长 */
    fun duration(ms: Long): String {
        val s = ms / 1000; val h = s / 3600; val m = (s % 3600) / 60
        return when {
            h > 0 -> "$h 小时 $m 分"
            m > 0 -> "$m 分钟"
            else -> "$s 秒"
        }
    }

    fun relative(ms: Long, now: Long = System.currentTimeMillis()): String {
        val diff = (now - ms) / 1000
        return when {
            diff < 60 -> "刚刚"
            diff < 3600 -> "${diff / 60} 分钟前"
            diff < 86400 -> "${diff / 3600} 小时前"
            else -> "${diff / 86400} 天前"
        }
    }

    fun emoji(t: EventType) = when (t) {
        EventType.FEED -> "🍼"; EventType.SLEEP -> "😴"
        EventType.MEDICINE -> "💊"; EventType.POOP -> "🧷"
    }

    /** 母乳左右侧文案（§3.1 规则 5 点选面板与时间轴编辑共用）。 */
    fun side(s: BreastSide): String = s.title

    /** 排便类别文案（与左右侧同一批快捷入口）。 */
    fun diaper(k: DiaperKind): String = k.title

    fun isFormula(e: BabyEvent): Boolean = e.isFormula

    /**
     * 记录标题：母乳带左右侧、排便带小便/大便，其余用类型名。与 iOS BabyEvent.label 一致。
     * 侧别/类别未补填时都不显示 —— 快捷入口（小组件 / 通知 / Siri）与跳过追问的记录保持原样。
     */
    fun label(e: BabyEvent): String = when {
        e.feedMethod == FeedMethod.FORMULA -> "奶粉"
        e.feedMethod == FeedMethod.BREAST -> e.breastSide?.let { "母乳 ${it.title}" } ?: "母乳"
        e.type == EventType.POOP -> e.diaperKind?.title ?: e.type.title
        else -> e.type.title
    }

    fun subtitle(e: BabyEvent): String = when {
        isFormula(e) -> "${clock(e.startAt)} · 奶粉 ${e.volumeMl ?: 0}ml"
        e.type.isInterval -> {
            val end = e.endAt?.let { clock(it) } ?: "现在"
            "${clock(e.startAt)} – $end"
        }
        else -> clock(e.startAt)
    }

    /** §3.2 规则5：突出"距上次喂奶"（母乳/奶粉更近的一次）。仅陈述客观事实，禁止"该喂奶了/间隔过长"等判断性文案（§3.4 合规红线）。 */
    fun feedHighlight(e: BabyEvent, now: Long): String {
        val rel = relative(e.startAt, now)
        return if (isFormula(e)) "喂奶 · $rel · 奶粉 ${e.volumeMl ?: 0}ml" else "喂奶 · $rel · ${label(e)}"
    }

    /** §3.2 规则3/6：母乳 chip，带左右侧（未补填则不带）与时长。 */
    fun breastChip(e: BabyEvent, now: Long): String =
        "${label(e)} ${duration(e.durationMs(now))} · ${relative(e.startAt, now)}"

    /** §3.2 规则3/6：奶粉 chip，带毫升。 */
    fun formulaChip(e: BabyEvent, now: Long): String =
        "奶粉 ${e.volumeMl ?: 0}ml · ${relative(e.startAt, now)}"

    /** 记录图标：排便区分了类别就换成小/大便的符号，其余用类型图标。时间轴行与状态卡共用，同一行两处不能各画各的。 */
    fun icon(e: BabyEvent): String = e.diaperKind?.emoji ?: emoji(e.type)

    /** §3.2 规则3/6：排便 chip，带小便/大类别；未区分时回到类型图标与"排便"。 */
    fun poopChip(e: BabyEvent, now: Long): String =
        "${icon(e)} ${label(e)} · ${relative(e.startAt, now)}"
}

package com.babyclock.ui

import com.babyclock.data.BabyEvent
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

    fun isFormula(e: BabyEvent): Boolean = e.type == EventType.FEED && e.feedMethod == FeedMethod.FORMULA

    /** 记录标题：母乳/奶粉区分显示，其余用类型名。 */
    fun label(e: BabyEvent): String = when (e.feedMethod) {
        FeedMethod.FORMULA -> "奶粉"
        FeedMethod.BREAST -> "母乳"
        null -> e.type.title
    }

    fun subtitle(e: BabyEvent): String = when {
        isFormula(e) -> "${clock(e.startAt)} · 奶粉 ${e.volumeMl ?: 0}ml"
        e.type.isInterval -> {
            val end = e.endAt?.let { clock(it) } ?: "现在"
            "${clock(e.startAt)} – $end"
        }
        else -> clock(e.startAt)
    }
}

package com.babyclock.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/** 事件类型：吃奶/睡觉为时间段(INTERVAL，可被打断)，吃药/排便为瞬时(INSTANT)。 */
enum class EventType(val kind: EventKind, val title: String) {
    FEED(EventKind.INTERVAL, "吃奶"),
    SLEEP(EventKind.INTERVAL, "睡觉"),
    MEDICINE(EventKind.INSTANT, "吃药"),
    POOP(EventKind.INSTANT, "排便");

    val isInterval: Boolean get() = kind == EventKind.INTERVAL
}

enum class EventKind { INTERVAL, INSTANT }

/** 吃奶的两种记录形态（PRD §3.0）：母乳记时长，奶粉记毫升(零时长段)。 */
enum class FeedMethod { BREAST, FORMULA }

/** 母乳左右侧（可选，PRD §3.0）。 */
enum class BreastSide(val title: String) { LEFT("左侧"), RIGHT("右侧"), BOTH("双侧") }

/**
 * 排便的小便/大便之分（可选，与 BreastSide 同一口径：先落库、再追问、可跳过）。
 * null = 未区分：迁移前的历史行，以及小组件 / 锁屏通知 / Siri 这些不追问的快捷入口。
 * 显示时退回类型名"排便"，不猜。
 */
enum class DiaperKind(val title: String, val emoji: String) {
    PEE("小便", "💧"), POO("大便", "💩"), MIXED("大小便", "🧷")
}

enum class RecordSource { APP, WIDGET, VOICE, NOTIFICATION }

/** 一条事件记录。INTERVAL: endAt==null 表示进行中(ongoing)。INSTANT: endAt 恒 null, ongoing 恒 false。 */
@Entity(tableName = "event")
data class BabyEvent(
    @PrimaryKey val id: String,
    val babyId: String,
    val type: EventType,
    val startAt: Long,          // epoch ms
    val endAt: Long?,           // epoch ms; null=进行中(仅INTERVAL)
    val ongoing: Boolean,
    val note: String?,
    val source: RecordSource,
    val createdAt: Long,
    val updatedAt: Long,
    // v1.1 新增：吃奶形态与属性（其余事件恒为 null）
    @ColumnInfo(name = "feed_method") val feedMethod: FeedMethod? = null,
    @ColumnInfo(name = "volume_ml") val volumeMl: Int? = null,
    @ColumnInfo(name = "breast_side") val breastSide: BreastSide? = null,
    // v1.2 新增：排便区分小便/大便（仅 POOP 有意义，其余恒为 null）
    @ColumnInfo(name = "diaper_kind") val diaperKind: DiaperKind? = null
) {
    /** 是否为奶粉记录（FEED + FORMULA 零时长段）。与 iOS BabyEvent.isFormula 一致。 */
    val isFormula: Boolean get() = type == EventType.FEED && feedMethod == FeedMethod.FORMULA

    /** 已持续/总时长（进行中则到 now），单位 ms */
    fun durationMs(now: Long = System.currentTimeMillis()): Long {
        if (!type.isInterval) return 0
        val end = endAt ?: now
        return (end - startAt).coerceAtLeast(0)
    }
}

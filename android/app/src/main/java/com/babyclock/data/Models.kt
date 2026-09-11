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
enum class BreastSide { LEFT, RIGHT, BOTH }

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
    @ColumnInfo(name = "breast_side") val breastSide: BreastSide? = null
) {
    /** 已持续/总时长（进行中则到 now），单位 ms */
    fun durationMs(now: Long = System.currentTimeMillis()): Long {
        if (!type.isInterval) return 0
        val end = endAt ?: now
        return (end - startAt).coerceAtLeast(0)
    }
}

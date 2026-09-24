package com.babyclock.ui

import androidx.compose.runtime.*
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.babyclock.data.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 应用状态容器：包装仓库，向 Compose 暴露可观察数据 + 每秒走时。 */
class RecorderViewModel : ViewModel() {
    var events by mutableStateOf<List<BabyEvent>>(emptyList())
        private set
    var now by mutableStateOf(System.currentTimeMillis())
        private set

    init {
        viewModelScope.launch { reload() }
        viewModelScope.launch {
            while (true) {
                now = System.currentTimeMillis()
                delay(1000)
            }
        }
    }

    suspend fun reload() { events = EventRepository.allEvents() }

    fun submit(type: EventType, source: RecordSource = RecordSource.APP) {
        viewModelScope.launch {
            EventRepository.submit(type, source)
            reload()
        }
    }

    fun submitFormula(volumeMl: Int, source: RecordSource = RecordSource.APP) {
        viewModelScope.launch {
            EventRepository.submitFormula(volumeMl, source)
            reload()
        }
    }

    fun delete(e: BabyEvent) {
        viewModelScope.launch {
            EventRepository.delete(e)
            reload()
        }
    }

    val ongoing: BabyEvent? get() = events.firstOrNull { it.ongoing }

    fun lastOccurrence(type: EventType): Long? =
        events.filter { it.type == type }.map { it.startAt }.maxOrNull()

    /** §3.2：最近一次母乳（FEED 且非奶粉；含无 feedMethod 的历史段）。 */
    fun lastBreast(): BabyEvent? =
        events.filter { it.type == EventType.FEED && !Format.isFormula(it) }.maxByOrNull { it.startAt }

    /** §3.2：最近一次奶粉（FEED/FORMULA 零时长段）。 */
    fun lastFormula(): BabyEvent? =
        events.filter { Format.isFormula(it) }.maxByOrNull { it.startAt }

    fun eventsOnDay(dayStart: Long, dayEnd: Long): List<BabyEvent> =
        events.filter { it.startAt in dayStart until dayEnd }.sortedByDescending { it.startAt }

    /** 与当天窗口有重叠的事件（含跨天段），供 24h 活动带按窗口裁剪绘制。 */
    fun eventsOverlapping(dayStart: Long, dayEnd: Long, now: Long): List<BabyEvent> =
        events.filter { e ->
            if (e.type.isInterval) {
                val effEnd = e.endAt ?: if (e.ongoing) now else e.startAt
                e.startAt < dayEnd && effEnd > dayStart
            } else {
                e.startAt in dayStart until dayEnd
            }
        }.sortedByDescending { it.startAt }
}

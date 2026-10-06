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

    /** 一次性提示文案（null 表示无提示）。UI 以轻量横幅呈现，不用弹窗打断记录。 */
    var errorMessage by mutableStateOf<String?>(null)
        private set

    fun dismissError() { errorMessage = null }

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

    /**
     * 统一写入路径：成功清空提示，校验失败换成对应文案，其余失败如实报"未保存"。
     * 与 iOS Recorder.run 一致 —— 失败绝不静默（PRD §3.1 异常表）。
     */
    private fun write(body: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                body()
                errorMessage = null
            } catch (e: MachineException) {
                errorMessage = StoreErrorText.text(e.error)
            } catch (e: Exception) {
                errorMessage = "记录未保存，请重试"
            }
            reload()
        }
    }

    /**
     * 记录/结束一个时间段或瞬时事件。[onCreated] 在写库成功后回传本次那条 ——
     * 首页要拿刚落库的排便 id 去追问大小便（与母乳左右侧同一手法：先落库、再问、可跳过）。
     */
    fun submit(
        type: EventType,
        source: RecordSource = RecordSource.APP,
        onCreated: (BabyEvent) -> Unit = {}
    ) = write { onCreated(EventRepository.submit(type, source)) }

    /** 奶粉专用（PRD §3.1 规则 2）：零时长段并打断进行中段。 */
    fun submitFormula(volumeMl: Int, source: RecordSource = RecordSource.APP) =
        write { EventRepository.submitFormula(volumeMl, source) }

    /** 时间轴编辑（§3.3 规则 3）。非法区间由状态机挡下并提示（AC-7）。 */
    fun update(event: BabyEvent) = write { EventRepository.update(event) }

    /** 母乳结束后可选补填左/右/双侧（§3.1 规则 5）。 */
    fun setBreastSide(side: BreastSide?, id: String) = write { EventRepository.setBreastSide(side, id) }

    /** 排便后可选补填小便/大便（§3.1 规则 5 同款）；跳过即保持 null，显示为"排便"。 */
    fun setDiaperKind(kind: DiaperKind?, id: String) = write { EventRepository.setDiaperKind(kind, id) }

    fun delete(e: BabyEvent) = write { EventRepository.delete(e) }

    val ongoing: BabyEvent? get() = events.firstOrNull { it.ongoing }

    fun lastOccurrence(type: EventType): Long? =
        events.filter { it.type == type }.map { it.startAt }.maxOrNull()

    /** §3.2：最近一次母乳（FEED 且非奶粉；含无 feedMethod 的历史段）。 */
    fun lastBreast(): BabyEvent? =
        events.filter { it.type == EventType.FEED && !Format.isFormula(it) }.maxByOrNull { it.startAt }

    /** §3.2：最近一次奶粉（FEED/FORMULA 零时长段）。 */
    fun lastFormula(): BabyEvent? =
        events.filter { Format.isFormula(it) }.maxByOrNull { it.startAt }

    /** §3.2：最近一次排便。返回整条而非时刻，状态卡要看它的小便/大类别。 */
    fun lastPoop(): BabyEvent? =
        events.filter { it.type == EventType.POOP }.maxByOrNull { it.startAt }

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

/** 校验失败文案（PRD §3.1 / §3.3 异常表）。全部为客观陈述，不含健康判断用词（§4 合规禁词）。 */
object StoreErrorText {
    fun text(error: MachineError): String = when (error) {
        MachineError.INVALID_VOLUME -> "请输入有效的毫升数"
        MachineError.INVALID_INTERVAL -> "结束时间不能早于开始时间"
        MachineError.INCONSISTENT_FORMULA -> "奶粉记录只需选择发生时刻"
    }
}

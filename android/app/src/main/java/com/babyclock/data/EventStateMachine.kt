package com.babyclock.data

/**
 * 存储抽象：让状态机可被纯内存实现测试，生产用 Room。
 * `delete` 刻意不给默认实现 —— 漏实现的空删除会让"删了又复活"看起来像数据 bug。
 */
interface EventStore {
    fun findOngoing(babyId: String): BabyEvent?
    fun insert(event: BabyEvent)
    fun update(event: BabyEvent)
    fun delete(event: BabyEvent)
    fun allEvents(babyId: String): List<BabyEvent>

    /** 把「结束旧段 + 写入新记录」包成原子操作（ARCH §2.3）。 */
    fun <T> transaction(body: () -> T): T = body()
}

/** 校验失败原因（与 iOS MachineError 一一对应），文案在 UI 层映射。 */
enum class MachineError { INVALID_VOLUME, INVALID_INTERVAL, INCONSISTENT_FORMULA }

class MachineException(val error: MachineError) : Exception(error.name)

/**
 * 核心事件状态机 —— 与 shared/state-machine.md 及 iOS EventStateMachine 逐条一致。
 * 规则：吃奶/睡觉为时间段(可被打断)，吃药/排便为瞬时(不打断时间段)。
 */
class EventStateMachine(
    private val store: EventStore,
    private val babyId: String = DEFAULT_BABY_ID
) {
    companion object { const val DEFAULT_BABY_ID = "default" }

    /** 提交一次记录，返回受影响的事件。两条写语句必须在同一事务里，否则中间被打断会留下两条 ongoing。 */
    fun submit(
        type: EventType,
        now: Long = System.currentTimeMillis(),
        source: RecordSource = RecordSource.APP,
        note: String? = null
    ): BabyEvent = store.transaction {
        if (type.isInterval) submitInterval(type, now, source, note)
        else submitInstant(type, now, source, note)
    }

    // INSTANT：仅新增一条，不影响进行中的时间段事件
    private fun submitInstant(type: EventType, now: Long, source: RecordSource, note: String?): BabyEvent {
        val e = BabyEvent(
            id = java.util.UUID.randomUUID().toString(), babyId = babyId, type = type,
            startAt = now, endAt = null, ongoing = false,
            note = note, source = source, createdAt = now, updatedAt = now
        )
        store.insert(e)
        return e
    }

    // INTERVAL：处理打断与"再次点击=结束"
    private fun submitInterval(type: EventType, now: Long, source: RecordSource, note: String?): BabyEvent {
        val current = store.findOngoing(babyId)

        // 再次点击同类型 = 结束当前段
        if (current != null && current.type == type) {
            val ended = current.copy(endAt = now, ongoing = false, updatedAt = now)
            store.update(ended)
            return ended
        }

        // 被打断：旧段结束于 now
        if (current != null) {
            store.update(current.copy(endAt = now, ongoing = false, updatedAt = now))
        }

        val new = BabyEvent(
            id = java.util.UUID.randomUUID().toString(), babyId = babyId, type = type,
            startAt = now, endAt = null, ongoing = true,
            note = note, source = source, createdAt = now, updatedAt = now,
            feedMethod = if (type == EventType.FEED) FeedMethod.BREAST else null
        )
        store.insert(new)
        return new
    }

    /**
     * 奶粉专用入口（state-machine.md submitFormula）：打断当前进行中段，
     * 写入一条 start==end==now 的零时长 FEED/FORMULA 段，永不 ongoing。
     */
    fun submitFormula(
        now: Long = System.currentTimeMillis(),
        volumeMl: Int,
        source: RecordSource = RecordSource.APP,
        note: String? = null
    ): BabyEvent {
        if (volumeMl <= 0) throw MachineException(MachineError.INVALID_VOLUME)
        return store.transaction {
            val current = store.findOngoing(babyId)
            if (current != null) {
                store.update(current.copy(endAt = now, ongoing = false, updatedAt = now))
            }
            val e = BabyEvent(
                id = java.util.UUID.randomUUID().toString(), babyId = babyId, type = EventType.FEED,
                startAt = now, endAt = now, ongoing = false,
                note = note, source = source, createdAt = now, updatedAt = now,
                feedMethod = FeedMethod.FORMULA, volumeMl = volumeMl
            )
            store.insert(e)
            e
        }
    }

    /**
     * 结束母乳段后补填左右侧（§3.1 规则 5），可跳过（保持 null）。
     * 按 id 从库里取当前行再改字段：UI 手上那份快照可能是段结束前的旧状态（endAt 仍为 null），
     * 直接写回去会把已结束的段复活成"进行中"，破坏 I1。
     */
    fun setBreastSide(side: BreastSide?, id: String) {
        val e = store.allEvents(babyId).firstOrNull { it.id == id } ?: return
        update(e.copy(breastSide = side))
    }

    /**
     * 排便记录补填小便/大便/大小便（与 [setBreastSide] 同一口径：记录已落库，这一笔可跳过，保持 null）。
     * 同样按 id 重读库内当前行，避免拿写入时的旧快照回写。
     */
    fun setDiaperKind(kind: DiaperKind?, id: String) {
        val e = store.allEvents(babyId).firstOrNull { it.id == id } ?: return
        update(e.copy(diaperKind = kind))
    }

    /**
     * 编辑一条记录（§3.3 规则 3）。落库前守住不变量，与 iOS EventStateMachine.update 逐条一致：
     * - 结束不得早于开始（AC-7）
     * - 奶粉是零时长段：UI 只暴露一个时刻，这里让 endAt 跟随 startAt（I4）
     * - FORMULA 必须带正毫升（I5）
     * - INTERVAL 的 endAt == null ⟺ ongoing（I2）
     */
    fun update(edited: BabyEvent): BabyEvent {
        var e = edited.copy(updatedAt = System.currentTimeMillis())
        if (e.isFormula) {
            val ml = e.volumeMl ?: 0
            if (ml <= 0) throw MachineException(MachineError.INVALID_VOLUME)
            e = e.copy(endAt = e.startAt, ongoing = false)
        }
        if (e.type.isInterval) {
            val end = e.endAt
            if (end != null && end < e.startAt) throw MachineException(MachineError.INVALID_INTERVAL)
            e = e.copy(ongoing = end == null)
        }
        store.transaction { store.update(e) }
        return e
    }

    /** 删除一条记录（§3.3 规则 4：二次确认由 UI 负责）。删除进行中段后状态回到"无进行中"。 */
    fun delete(event: BabyEvent) {
        store.transaction { store.delete(event) }
    }

    fun ongoing(): BabyEvent? = store.findOngoing(babyId)
    fun allEvents(): List<BabyEvent> = store.allEvents(babyId)
    fun lastOccurrence(type: EventType): Long? =
        allEvents().filter { it.type == type }.map { it.startAt }.maxOrNull()
}

/** 纯内存实现，用于单元测试与预览。 */
class InMemoryEventStore : EventStore {
    private val events = mutableListOf<BabyEvent>()
    override fun findOngoing(babyId: String) = events.firstOrNull { it.babyId == babyId && it.ongoing }
    override fun insert(event: BabyEvent) { events.add(event) }
    override fun update(event: BabyEvent) {
        val i = events.indexOfFirst { it.id == event.id }
        if (i >= 0) events[i] = event
    }
    override fun delete(event: BabyEvent) { events.removeAll { it.id == event.id } }
    override fun allEvents(babyId: String) =
        events.filter { it.babyId == babyId }.sortedBy { it.startAt }
}

object DaySplitter {
    /** 按本地自然日切分 [start,end) 时长，用于跨天统计(AC-12)。返回 [(dayStartMs, ms)]。 */
    fun splitByDay(start: Long, end: Long, cal: java.util.Calendar = java.util.Calendar.getInstance()): List<Pair<Long, Long>> {
        if (end <= start) return emptyList()
        val result = mutableListOf<Pair<Long, Long>>()
        var cursor = start
        while (cursor < end) {
            val c = (cal.clone() as java.util.Calendar).apply { timeInMillis = cursor }
            c.add(java.util.Calendar.DAY_OF_YEAR, 1)
            c.set(java.util.Calendar.HOUR_OF_DAY, 0)
            c.set(java.util.Calendar.MINUTE, 0)
            c.set(java.util.Calendar.SECOND, 0)
            c.set(java.util.Calendar.MILLISECOND, 0)
            val nextMidnight = c.timeInMillis
            val segmentEnd = minOf(nextMidnight, end)
            val dayCal = (cal.clone() as java.util.Calendar).apply {
                timeInMillis = cursor
                set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
            }
            result.add(dayCal.timeInMillis to (segmentEnd - cursor))
            cursor = segmentEnd
        }
        return result
    }
}

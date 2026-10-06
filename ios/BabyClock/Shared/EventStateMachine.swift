import Foundation

/// 存储抽象：让状态机可被纯内存实现测试，生产用 SQLiteStore。
public protocol EventStoring: AnyObject {
    func findOngoing(babyId: String) -> BabyEvent?
    func insert(_ event: BabyEvent) throws
    func update(_ event: BabyEvent) throws
    func delete(_ event: BabyEvent) throws
    func allEvents(babyId: String) throws -> [BabyEvent]

    /// 把「结束旧段 + 写入新记录」包成原子操作（ARCH §2.3）。
    /// 不加这层，两条语句之间被中断就会留下两条 ongoing 或谁都不 ongoing，破坏 I1。
    func transaction<T>(_ body: () throws -> T) throws -> T
}

/// 默认实现：内存实现无原子性需求，直接执行。
/// `delete` 刻意不给默认实现 —— 漏实现的空删除会让「删了就复活」看起来像数据 bug。
public extension EventStoring {
    func transaction<T>(_ body: () throws -> T) throws -> T { try body() }
}

/// 状态机错误。
/// - invalidVolume：奶粉毫升数非正（不得以 0/null 落库，见 state-machine.md 要点 3）
/// - invalidInterval：结束时刻早于开始时刻（PRD §3.3 异常表 / AC-7）
/// - inconsistentFormula：编辑奶粉时破坏了 start == end 这条零时长不变量（I4）
public enum MachineError: Error, Equatable {
    case invalidVolume
    case invalidInterval
    case inconsistentFormula
}

/// 核心事件状态机 —— 与 shared/state-machine.md 及 Android EventStateMachine 逐条一致。
/// 规则：吃奶/睡觉为时间段(可被打断)，吃药/排便为瞬时(不打断时间段)。
public final class EventStateMachine {

    public static let defaultBabyId = "default"

    private let store: EventStoring
    private let babyId: String

    public init(store: EventStoring, babyId: String = EventStateMachine.defaultBabyId) {
        self.store = store
        self.babyId = babyId
    }

    /// 提交一次记录。返回本次受影响的事件（便于 UI 反馈）。
    @discardableResult
    public func submit(type: EventType,
                       now: Date = Date(),
                       source: RecordSource = .app,
                       note: String? = nil) throws -> BabyEvent {
        if type.isInterval {
            return try store.transaction {
                try self.submitInterval(type: type, now: now, source: source, note: note)
            }
        } else {
            return try store.transaction {
                try self.submitInstant(type: type, now: now, source: source, note: note)
            }
        }
    }

    // MARK: - INSTANT (吃药 / 排便)：仅新增一条，不影响进行中的时间段事件
    private func submitInstant(type: EventType, now: Date, source: RecordSource, note: String?) throws -> BabyEvent {
        let e = BabyEvent(id: UUID().uuidString, babyId: babyId, type: type,
                          startAt: now, endAt: nil, ongoing: false,
                          note: note, source: source, createdAt: now, updatedAt: now)
        try store.insert(e)
        return e
    }

    // MARK: - INTERVAL (吃奶 / 睡觉)
    private func submitInterval(type: EventType, now: Date, source: RecordSource, note: String?) throws -> BabyEvent {
        let current = store.findOngoing(babyId: babyId)

        // 再次点击同类型 = 结束当前段
        // FEED 命中此分支时 current 必为 BREAST（I5 保证 FORMULA 永不 ongoing）
        if let current, current.type == type {
            var ended = current
            ended.endAt = now
            ended.ongoing = false
            ended.updatedAt = now
            try store.update(ended)
            return ended
        }

        // 被打断：旧段结束于 now
        if var current {
            current.endAt = now
            current.ongoing = false
            current.updatedAt = now
            try store.update(current)
        }

        // 开启新的进行中段
        let new = BabyEvent(id: UUID().uuidString, babyId: babyId, type: type,
                            startAt: now, endAt: nil, ongoing: true,
                            note: note, source: source, createdAt: now, updatedAt: now,
                            feedMethod: type == .feed ? .breast : nil)
        try store.insert(new)
        return new
    }

    /// 奶粉专用入口（state-machine.md submitFormula）：打断当前进行中段，
    /// 写入一条 start==end==now 的零时长 FEED/FORMULA 段，永不 ongoing。
    /// volumeMl 必填且为正；非法时抛错，不得以 0/null 落库（规格要点 3）。
    @discardableResult
    public func submitFormula(now: Date = Date(),
                              volumeMl: Int,
                              source: RecordSource = .app,
                              note: String? = nil) throws -> BabyEvent {
        guard volumeMl > 0 else { throw MachineError.invalidVolume }
        return try store.transaction {
            if var current = store.findOngoing(babyId: babyId) {
                current.endAt = now
                current.ongoing = false
                current.updatedAt = now
                try store.update(current)
            }
            let e = BabyEvent(id: UUID().uuidString, babyId: babyId, type: .feed,
                              startAt: now, endAt: now, ongoing: false,
                              note: note, source: source, createdAt: now, updatedAt: now,
                              feedMethod: .formula, volumeMl: volumeMl)
            try store.insert(e)
            return e
        }
    }

    // MARK: - 时间轴管理（PRD §3.3）

    /// 结束母乳段后补填左右侧（§3.1 规则 5）。可跳过 —— 跳过即保持 nil，不影响记录已落库。
    /// 按 id 从库里取当前行再改字段：UI 手上那份快照可能是段结束前的旧状态（endAt 仍为 nil），
    /// 直接把它写回去会把已结束的段复活成"进行中"，破坏 I1。
    public func setBreastSide(_ side: BreastSide?, id: String) throws {
        guard var e = try store.allEvents(babyId: babyId).first(where: { $0.id == id }) else { return }
        e.breastSide = side
        try update(e)
    }

    /// 排便记录补填小便/大便/大小便。与 setBreastSide 同一口径：记录已落库，这一笔可跳过（保持 nil）。
    /// 同样按 id 取库内当前行 —— 首页手上那份是写入时的快照，直接回写会带着旧 updatedAt 覆盖编辑结果。
    public func setDiaperKind(_ kind: DiaperKind?, id: String) throws {
        guard var e = try store.allEvents(babyId: babyId).first(where: { $0.id == id }) else { return }
        e.diaperKind = kind
        try update(e)
    }

    /// 编辑一条记录（时刻 / 类型 / 备注 / 毫升 / 左右侧）。落库前守住不变量：
    /// - 结束不得早于开始（AC-7）
    /// - 奶粉是零时长段：UI 只暴露一个时刻选择器，这里把 endAt 强制跟随 startAt（I4）
    /// - FORMULA 必须带正毫升（I5）
    public func update(_ edited: BabyEvent) throws {
        var e = edited
        e.updatedAt = Date()
        if e.isFormula {
            guard let ml = e.volumeMl, ml > 0 else { throw MachineError.invalidVolume }
            e.endAt = e.startAt
        }
        if e.type.isInterval, let end = e.endAt, end < e.startAt {
            throw MachineError.invalidInterval
        }
        // 编辑进行中段时不得顺手把 ongoing 写丢：INTERVAL 的 end==nil ⟺ ongoing（I2）
        if e.type.isInterval { e.ongoing = e.endAt == nil }
        try store.transaction { try self.store.update(e) }
    }

    /// 删除一条记录（§3.3 规则 4：二次确认由 UI 负责）。删除进行中段后状态回到"无进行中"。
    public func delete(_ event: BabyEvent) throws {
        try store.transaction { try self.store.delete(event) }
    }

    // MARK: - 查询

    public func ongoing() -> BabyEvent? { store.findOngoing(babyId: babyId) }

    public func allEvents() throws -> [BabyEvent] { try store.allEvents(babyId: babyId) }

    /// 某事件类型最近一次记录（瞬时取发生时刻；时间段取最近一段开始时刻）
    public func lastOccurrence(of type: EventType) throws -> Date? {
        try allEvents()
            .filter { $0.type == type }
            .map { $0.startAt }
            .max()
    }

    /// 按自然日切分时间段时长（用于跨天统计，AC-12）。返回 [(dayStart, seconds)]
    public static func splitByDay(start: Date, end: Date,
                                  calendar: Calendar = .current) -> [(day: Date, seconds: TimeInterval)] {
        guard end > start else { return [] }
        var result: [(Date, TimeInterval)] = []
        var cursor = start
        while cursor < end {
            let nextMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: cursor)!)
            let segmentEnd = min(nextMidnight, end)
            let day = calendar.startOfDay(for: cursor)
            result.append((day, segmentEnd.timeIntervalSince(cursor)))
            cursor = segmentEnd
        }
        return result
    }
}

/// 纯内存实现，用于单元测试与 SwiftUI 预览。
public final class InMemoryEventStore: EventStoring {
    private var events: [BabyEvent] = []

    public init() {}

    public func findOngoing(babyId: String) -> BabyEvent? {
        events.first { $0.babyId == babyId && $0.ongoing }
    }
    public func insert(_ event: BabyEvent) throws { events.append(event) }
    public func update(_ event: BabyEvent) throws {
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[i] = event
    }
    public func delete(_ event: BabyEvent) throws {
        events.removeAll { $0.id == event.id }
    }
    public func allEvents(babyId: String) throws -> [BabyEvent] {
        events.filter { $0.babyId == babyId }.sorted { $0.startAt < $1.startAt }
    }
}

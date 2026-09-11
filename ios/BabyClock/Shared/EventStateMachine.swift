import Foundation

/// 存储抽象：让状态机可被纯内存实现测试，生产用 SQLiteStore。
public protocol EventStoring: AnyObject {
    func findOngoing(babyId: String) -> BabyEvent?
    func insert(_ event: BabyEvent) throws
    func update(_ event: BabyEvent) throws
    func allEvents(babyId: String) throws -> [BabyEvent]
}

/// 状态机错误。invalidVolume：奶粉毫升数非正（不得以 0/null 落库，见 state-machine.md 要点 3）。
public enum MachineError: Error, Equatable {
    case invalidVolume
}

/// 核心事件状态机 —— 与 shared/state-machine.md 逐条一致。
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
            return try submitInterval(type: type, now: now, source: source, note: note)
        } else {
            return try submitInstant(type: type, now: now, source: source, note: note)
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
    public func allEvents(babyId: String) throws -> [BabyEvent] {
        events.filter { $0.babyId == babyId }.sorted { $0.startAt < $1.startAt }
    }
}

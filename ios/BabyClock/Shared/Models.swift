import Foundation

/// 事件类型（吃奶/睡觉为时间段，吃药/排便为瞬时）
public enum EventType: String, Codable, CaseIterable, Sendable {
    case feed = "FEED"
    case sleep = "SLEEP"
    case medicine = "MEDICINE"
    case poop = "POOP"

    public enum Kind: String, Codable, Sendable {
        case interval = "INTERVAL"
        case instant = "INSTANT"
    }

    public var kind: Kind {
        switch self {
        case .feed, .sleep: return .interval
        case .medicine, .poop: return .instant
        }
    }

    public var isInterval: Bool { kind == .interval }

    public var title: String {
        switch self {
        case .feed: return "吃奶"
        case .sleep: return "睡觉"
        case .medicine: return "吃药"
        case .poop: return "排便"
        }
    }
}

public enum RecordSource: String, Codable, Sendable {
    case app = "APP"
    case widget = "WIDGET"
    case voice = "VOICE"
}

/// 吃奶的两种记录形态（PRD §3.0）：母乳记时长，奶粉记毫升(零时长段)。
public enum FeedMethod: String, Codable, CaseIterable, Sendable {
    case breast = "BREAST"
    case formula = "FORMULA"
}

/// 母乳左右侧（可选，PRD §3.0）。
public enum BreastSide: String, Codable, CaseIterable, Sendable {
    case left = "LEFT"
    case right = "RIGHT"
    case both = "BOTH"
}

/// 一条事件记录。INTERVAL: endAt==nil 表示进行中(ongoing)。INSTANT: endAt 恒为 nil, ongoing 恒为 false。
public struct BabyEvent: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var babyId: String
    public var type: EventType
    public var startAt: Date
    public var endAt: Date?
    public var ongoing: Bool
    public var note: String?
    public var source: RecordSource
    public var createdAt: Date
    public var updatedAt: Date
    // v1.1 新增：吃奶形态与属性（其余事件恒为 nil）。默认 nil 以保持既有构造点不变。
    public var feedMethod: FeedMethod? = nil
    public var volumeMl: Int? = nil
    public var breastSide: BreastSide? = nil

    public var kind: EventType.Kind { type.kind }

    /// 是否为奶粉记录（FEED + FORMULA 零时长段）。
    public var isFormula: Bool { type == .feed && feedMethod == .formula }

    /// 已持续/总时长（进行中则到 now）
    public func duration(now: Date = Date()) -> TimeInterval {
        guard type.isInterval else { return 0 }
        let end = endAt ?? now
        return max(0, end.timeIntervalSince(startAt))
    }
}

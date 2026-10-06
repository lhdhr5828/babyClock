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
/// 文案放在这一层而非 HomeView：Widget target 只编译 Shared/ + Theme，取不到 View 文件里的扩展。
public enum BreastSide: String, Codable, CaseIterable, Sendable {
    case left = "LEFT"
    case right = "RIGHT"
    case both = "BOTH"

    public var title: String {
        switch self {
        case .left: return "左侧"
        case .right: return "右侧"
        case .both: return "双侧"
        }
    }
}

/// 排便的小便/大便之分（可选，点选后可跳过；PRD §3.1 规则 5 的同款口径）。
/// nil = 未区分：历史行（迁移只加列不填值）与小组件/通知/Siri 这类不追问的快捷入口，
/// 显示时退回类型名"排便"，不猜。
public enum DiaperKind: String, Codable, CaseIterable, Sendable {
    case pee = "PEE"
    case poo = "POO"
    case mixed = "MIXED"

    public var title: String {
        switch self {
        case .pee: return "小便"
        case .poo: return "大便"
        case .mixed: return "大小便"
        }
    }

    /// 混合沿用排便原本的回形针符号：两个 emoji 并排在状态卡胶囊里会挤掉时间。
    public var emoji: String {
        switch self {
        case .pee: return "💧"
        case .poo: return "💩"
        case .mixed: return "🧷"
        }
    }
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
    // v1.2 新增：排便区分小便/大便（仅 POOP 有意义，其余恒为 nil）。
    public var diaperKind: DiaperKind? = nil

    public var kind: EventType.Kind { type.kind }

    /// 是否为奶粉记录（FEED + FORMULA 零时长段）。
    public var isFormula: Bool { type == .feed && feedMethod == .formula }

    /// 记录标题：母乳带侧别、排便带小便/大便，其余用类型名（对齐 Android Format.label）。
    /// 侧别只在已补填时才出现 —— 进行中的母乳段还没问，跳过追问的历史段也没有。
    public var label: String {
        if let fm = feedMethod {
            if fm == .formula { return "奶粉" }
            return breastSide.map { "母乳 \($0.title)" } ?? "母乳"
        }
        if type == .poop, let d = diaperKind { return d.title }
        return type.title
    }

    /// 已持续/总时长（进行中则到 now）
    public func duration(now: Date = Date()) -> TimeInterval {
        guard type.isInterval else { return 0 }
        let end = endAt ?? now
        return max(0, end.timeIntervalSince(startAt))
    }
}

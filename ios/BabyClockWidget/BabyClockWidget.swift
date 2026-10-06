import AppIntents
import WidgetKit
import SwiftUI

/// 锁屏 / 桌面小组件（PRD §3.5）：不解锁一键记录，并显示当前状态。
/// 尺寸差异（规则 2 / 规则 6）：
///   systemSmall       —— 状态 + 母乳/睡觉/吃药/排便四键；**不含奶粉入口**
///   systemMedium      —— 状态 + 四键 + 内联三档毫升（60/90/120）直点即记
///   accessoryRectangular / accessoryCircular —— 锁屏形态，显示进行中事件与时长
///   accessoryInline   —— 「距上次喂奶 xx 分钟」（规则 6）
/// 与主 App 共享同一 App Group 内的 SQLite 文件，写入走同一状态机（规则 4）。
/// 库不可用时如实显示"暂不可用"且不写入 —— 绝不回退内存库假装记录成功（AC-21）。

// MARK: - Timeline

struct BabyClockWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = loadEntry()
        // 每分钟刷新一次以推进走秒显示；写入后由 Intent 触发 reloadAllTimelines 立即同步
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> WidgetEntry {
        guard let store = try? SQLiteStore() else {
            return WidgetEntry(date: Date(), available: false, ongoing: nil, lastFeedAt: nil)
        }
        let machine = EventStateMachine(store: store)
        let now = Date()
        // 规则 6：距上次喂奶 = 母乳/奶粉更近的一次开始时刻
        let feeds = (try? machine.allEvents())?.filter { $0.type == .feed } ?? []
        return WidgetEntry(date: now,
                           available: true,
                           ongoing: machine.ongoing(),
                           lastFeedAt: feeds.map(\.startAt).max())
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let ongoing: BabyEvent?
    let lastFeedAt: Date?

    static var sample: WidgetEntry {
        WidgetEntry(date: Date(), available: true,
                    ongoing: BabyEvent(id: "x", babyId: "default", type: .sleep,
                                       startAt: Date().addingTimeInterval(-2538),
                                       endAt: nil, ongoing: true, note: nil,
                                       source: .widget, createdAt: Date(), updatedAt: Date()),
                    lastFeedAt: Date().addingTimeInterval(-2400))
    }

    /// 走秒文案：HH:MM:SS。
    var elapsedText: String {
        guard let o = ongoing else { return "" }
        return formatDuration(date.timeIntervalSince(o.startAt))
    }
}

// MARK: - View

struct WidgetEntryView: View {
    var entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        content
            .modifier(WidgetChrome())
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                StatusLine(entry: entry, compact: true)
                Spacer(minLength: 0)
                RecordButtons(entry: entry)
            }
            .padding(12)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                StatusLine(entry: entry, compact: false)
                Spacer(minLength: 0)
                RecordButtons(entry: entry)
                FormulaTiers()
            }
            .padding(12)
        case .accessoryInline:
            Text(entry.lastFeedAt.map { "喂奶 " + relativeTimeString($0, now: entry.date) } ?? "尚无喂奶记录")
        case .accessoryCircular:
            VStack(spacing: 0) {
                if let o = entry.ongoing {
                    Text(o.type.title).font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(shortElapsed).font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: "baby.circle")
                    Text("无进行中").font(.system(size: 8))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let o = entry.ongoing {
                    Text("\(o.type.title)进行中").font(.system(size: 11, weight: .bold))
                    Text(entry.elapsedText).font(.system(size: 17, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("当前无进行中").font(.system(size: 11, weight: .bold))
                    Text(entry.lastFeedAt.map { "上次喂奶 " + formatClock($0) } ?? "尚无喂奶记录")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        default:
            StatusLine(entry: entry, compact: true)
        }
    }

    /// 圆形尺寸极小：走秒退化为 MM:SS，避免 HH:MM:SS 溢出。
    private var shortElapsed: String {
        guard let o = entry.ongoing else { return "" }
        let s = Int(entry.date.timeIntervalSince(o.startAt))
        if s >= 3600 { return String(format: "%d:%02d", s / 3600, (s % 3600) / 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 桌面小组件背景：iOS 17 用 containerBackground，iOS 16 退回普通背景（部署目标为 16）。
private struct WidgetChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                LinearGradient(colors: [Warm.bg, Warm.sunken], startPoint: .top, endPoint: .bottom)
            }
        } else {
            content.background(
                LinearGradient(colors: [Warm.bg, Warm.sunken], startPoint: .top, endPoint: .bottom)
            )
        }
    }
}

/// 状态行：进行中事件 + 已持续时长（规则 3），或"无进行中"/"暂不可用"。
/// 仅客观陈述，不含任何健康判断文案（§3.4 合规红线）。
private struct StatusLine: View {
    let entry: WidgetEntry
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !entry.available {
                Label("存储暂不可用", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
            } else if let o = entry.ongoing {
                HStack(spacing: 6) {
                    Circle().fill(Warm.primary).frame(width: 7, height: 7)
                    Text("\(o.type.title)进行中").font(.caption).fontWeight(.bold)
                }
                Text(entry.elapsedText)
                    .font(.system(size: compact ? 18 : 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("当前无进行中").font(.caption).fontWeight(.bold)
            }
        }
        .foregroundStyle(Warm.text1)
    }
}

/// 四键快捷记录（母乳 / 睡觉 / 吃药 / 排便）。奶粉不在这里 —— 小尺寸不含奶粉入口（规则 2）。
private struct RecordButtons: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    private let types: [EventType] = [.feed, .sleep, .medicine, .poop]

    var body: some View {
        // 可点按的小组件按钮是 iOS 17 的 Interactive Widgets 能力。iOS 16 上本组件退化为
        // 纯状态展示、轻点整块打开 App；"不解锁一键记录"在 16 上由 Siri（App Intents 支持 16）承担。
        if #available(iOS 17.0, *) {
            HStack(spacing: family == .systemSmall ? 6 : 10) {
                ForEach(types, id: \.self) { type in
                    Button(intent: QuickRecordIntent(type: type)) {
                        VStack(spacing: 3) {
                            SquircleIcon(type: type, size: family == .systemSmall ? 30 : 40) {
                                EventGlyph(type: type, size: family == .systemSmall ? 15 : 19)
                            }
                            Text(label(type))
                                .font(.system(size: family == .systemSmall ? 9 : 10, weight: .bold))
                                .foregroundStyle(Warm.text2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            Text("轻点打开 App 记录")
                .font(.caption2).foregroundStyle(Warm.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// FEED 键即母乳（奶粉走下方三档按钮），文案与首页五键一致（规则 1）。
    private func label(_ type: EventType) -> String {
        type == .feed ? "母乳" : type.title
    }
}

/// 中尺寸内联三档毫升（规则 2）：点一下即以该毫升数写入，不弹面板。
private struct FormulaTiers: View {
    private let tiers = [60, 90, 120]

    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 8) {
                Text("🍼").font(.system(size: 12))
                ForEach(tiers, id: \.self) { ml in
                    Button(intent: QuickFormulaIntent(volumeMl: ml)) {
                        Text("\(ml)ml")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Warm.primaryStrong)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(Warm.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Intents

/// 小组件按钮直接写入（无需打开 App），走同一状态机，来源标记 WIDGET。
/// 库不可用时不做任何写入 —— 内存库写入会"假装成功"并在下次刷新时凭空消失。
struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记录宝宝事件"
    static var isDiscoverable = false
    @Parameter(title: "类型") var typeParam: BabyEventTypeAppEnum
    init() {}
    init(type: EventType) {
        switch type {
        case .feed: self.typeParam = .feed
        case .sleep: self.typeParam = .sleep
        case .medicine: self.typeParam = .medicine
        case .poop: self.typeParam = .poop
        }
    }
    @MainActor
    func perform() async throws -> some IntentResult {
        let domain = typeParam.domain
        record { try $0.submit(type: domain, now: Date(), source: .widget) }
        return .result()
    }
}

/// 奶粉档位直点：等同 App 内选档，写入零时长 FEED/FORMULA 段并打断进行中段（§3.0 取舍 2）。
struct QuickFormulaIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记录奶粉毫升"
    static var isDiscoverable = false
    @Parameter(title: "毫升数") var volumeMl: Int
    init() { volumeMl = 0 }
    init(volumeMl: Int) { self.volumeMl = volumeMl }
    @MainActor
    func perform() async throws -> some IntentResult {
        let ml = volumeMl
        guard ml > 0 else { return .result() }
        record { try $0.submitFormula(now: Date(), volumeMl: ml, source: .widget) }
        return .result()
    }
}

/// 共用的"打开共享库 → 写一次 → 刷新时间线"路径。
/// 打不开共享库就放弃写入：写进内存库会"假装成功"，下次刷新凭空消失（AC-21）。
private func record(_ body: (EventStateMachine) throws -> Void) {
    guard let store = try? SQLiteStore() else { return }
    try? body(EventStateMachine(store: store))
    WidgetCenter.shared.reloadAllTimelines()
}

@main
struct BabyClockWidget: Widget {
    let kind = "BabyClockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BabyClockWidgetProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("宝宝记录")
        .description("不解锁一键记录母乳/睡觉/吃药/排便，中尺寸可直点奶粉毫升档位，并显示当前状态。")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

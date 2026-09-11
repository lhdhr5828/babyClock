import WidgetKit
import SwiftUI

/// 锁屏 / 桌面小组件：不解锁一键记录，并显示当前状态。
/// 与主 App 共享同一 App Group SQLite 文件，写入走同一状态机。
struct BabyClockWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(loadEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = loadEntry()
        // 每分钟刷新一次以更新走秒；写入由按钮 Intent 触发后 reloadAllTimelines
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func loadEntry() -> WidgetEntry {
        let store = (try? SQLiteStore()) ?? InMemoryEventStore()
        let machine = EventStateMachine(store: store)
        return WidgetEntry(date: Date(), ongoing: machine.ongoing())
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let ongoing: BabyEvent?
    static var sample: WidgetEntry {
        WidgetEntry(date: Date(),
                    ongoing: BabyEvent(id: "x", babyId: "default", type: .sleep,
                                       startAt: Date().addingTimeInterval(-2538),
                                       endAt: nil, ongoing: true, note: nil,
                                       source: .app, createdAt: Date(), updatedAt: Date()))
    }
}

struct WidgetEntryView: View {
    var entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Warm.primary).frame(width: 8, height: 8)
                if let o = entry.ongoing {
                    Text("\(o.type.title)进行中").font(.caption).fontWeight(.bold)
                    Spacer()
                    Text(formatDuration(entry.date.timeIntervalSince(o.startAt)))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("当前无进行中").font(.caption).fontWeight(.bold)
                }
            }
            .foregroundStyle(Warm.text1)

            HStack(spacing: 10) {
                ForEach(EventType.allCases, id: \.self) { type in
                    Button(intent: QuickRecordIntent(type: type)) {
                        VStack(spacing: 4) {
                            SquircleIcon(type: type, size: family == .systemSmall ? 34 : 40) {
                                EventGlyph(type: type, size: 20)
                            }
                            if family != .accessoryCircular {
                                Text(type.title).font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Warm.text2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Warm.bg, Warm.sunken], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// 小组件按钮直接写入（无需打开 App），走同一状态机，来源标记 WIDGET。
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
        let store = (try? SQLiteStore()) ?? InMemoryEventStore()
        let machine = EventStateMachine(store: store)
        try? machine.submit(type: typeParam.domain, now: Date(), source: .widget)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@main
struct BabyClockWidget: Widget {
    let kind = "BabyClockWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BabyClockWidgetProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("宝宝记录")
        .description("不解锁一键记录吃奶/睡觉/吃药/排便，并显示当前状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

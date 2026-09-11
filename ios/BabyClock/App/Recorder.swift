import SwiftUI
import Combine

/// App 状态容器：包装状态机，向 SwiftUI 暴露可观察数据 + 实时走秒。
@MainActor
final class Recorder: ObservableObject {

    @Published private(set) var events: [BabyEvent] = []
    @Published var now: Date = Date()

    private let machine: EventStateMachine
    private var ticker: AnyCancellable?

    init(store: EventStoring) {
        self.machine = EventStateMachine(store: store)
        reload()
        // 每秒刷新计时显示
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] t in self?.now = t }
    }

    func reload() {
        events = (try? machine.allEvents()) ?? []
    }

    func submit(_ type: EventType, source: RecordSource = .app) {
        do {
            try machine.submit(type: type, now: Date(), source: source)
            reload()
        } catch {
            // 本地写入失败：保留意图，提示由 UI 层处理（此处简化为重载）
            reload()
        }
    }

    var ongoing: BabyEvent? { events.first { $0.ongoing } }

    func lastOccurrence(of type: EventType) -> Date? {
        events.filter { $0.type == type }.map(\.startAt).max()
    }

    func events(on day: Date) -> [BabyEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.startAt, inSameDayAs: day) }
            .sorted { $0.startAt > $1.startAt }
    }

    func delete(_ e: BabyEvent) {
        // 简化：通过重建存储实现删除留给后续；此处从内存移除以更新 UI
        events.removeAll { $0.id == e.id }
    }
}

@main
struct BabyClockApp: App {
    @StateObject private var recorder: Recorder

    init() {
        let store = (try? SQLiteStore()) ?? InMemoryEventStore()
        _recorder = StateObject(wrappedValue: Recorder(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView().environmentObject(recorder)
        }
    }
}

struct RootTabView: View {
    /// §3.6 规则 7：一次性引导的持久化门控（仅首次启动弹出，之后不再打扰）。
    @AppStorage("hasShownSiriGuide") private var hasShownSiriGuide = false
    @State private var showSiriGuide = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("记录", systemImage: "house.fill") }
            TimelineView()
                .tabItem { Label("时间轴", systemImage: "calendar") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
        }
        .tint(Warm.primaryStrong)
        .onAppear {
            // 系统不支持语音时（iOS 16 以下）跳过引导，降级为小组件入口（异常表行 4）。
            if !hasShownSiriGuide && SiriAvailability.exposure != .unsupported {
                showSiriGuide = true
            }
        }
        .sheet(isPresented: $showSiriGuide, onDismiss: { hasShownSiriGuide = true }) {
            SiriGuideView()
        }
    }
}

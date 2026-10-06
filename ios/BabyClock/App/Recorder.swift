// xcode: set sdk=iOS

import SwiftUI
import Combine

/// App 状态容器：包装状态机，向 SwiftUI 暴露可观察数据 + 实时走秒。
/// 写库失败不静默吞掉：重试一次，仍失败则 errorMessage 供 UI 提示「记录未保存，请重试」（PRD §3.1 异常表）。
@MainActor
final class Recorder: ObservableObject {

    @Published private(set) var events: [BabyEvent] = []
    @Published var now: Date = Date()
    /// 一次性提示文案（nil 表示无提示）。UI 以轻量横幅呈现，不用弹窗打断记录。
    @Published var errorMessage: String?
    /// 数据库不可用时为 true：此时所有写操作都会失败，首页需明确告知而非假装已记录。
    @Published private(set) var storeUnavailable = false

    /// nil = 生产库打不开（App Group 未配置 / 文件保护拦截）。绝不回退到内存库假装成功。
    private let machine: EventStateMachine?
    private var ticker: AnyCancellable?

    init(machine: EventStateMachine?) {
        self.machine = machine
        self.storeUnavailable = machine == nil
        reload()
        // 每秒刷新计时显示
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] t in self?.now = t }
    }

    convenience init(store: EventStoring) {
        self.init(machine: EventStateMachine(store: store))
    }

    /// 生产入口：App Group 内的 SQLite；打不开就如实报，不静默换库。
    convenience init() {
        let machine: EventStateMachine?
        do {
            machine = EventStateMachine(store: try SQLiteStore())
        } catch {
            machine = nil
        }
        self.init(machine: machine)
    }

    func reload() {
        guard let machine else { storeUnavailable = true; return }
        do {
            events = try machine.allEvents()
        } catch {
            errorMessage = "记录读取失败，请重试"
        }
    }

    /// 记录/结束一个时间段或瞬时事件。返回本次写入或结束的那条记录（失败为 nil）。
    /// UI 若需要知道"这次点击是否在结束母乳"，在点击前读 `ongoing` 即可，不必回传事件；
    /// 排便则要拿返回的 id 去追问大小便（与母乳左右侧同一手法：先落库，再问，可跳过）。
    @discardableResult
    func submit(_ type: EventType, source: RecordSource = .app) -> BabyEvent? {
        var result: BabyEvent?
        run(retries: 1) { result = try $0.submit(type: type, now: Date(), source: source) }
        return result
    }

    /// 奶粉专用（PRD §3.1 规则 2）：写入零时长 FEED/FORMULA 段并打断进行中段。
    /// volumeMl 必须为正，非法时状态机抛 invalidVolume → 不落库（对齐"面板不选中不写库"）。
    func submitFormula(volumeMl: Int, source: RecordSource = .app) {
        run(retries: 1) { try $0.submitFormula(now: Date(), volumeMl: volumeMl, source: source) }
    }

    /// 母乳结束后可选补填左/右/双侧（§3.1 规则 5）。跳过即保持 nil，不影响已落库的记录。
    func setBreastSide(_ side: BreastSide?, id: String) {
        run { try $0.setBreastSide(side, id: id) }
    }

    /// 排便后可选补填小便/大便（§3.1 规则 5 同款）。跳过即保持 nil，显示为"排便"。
    func setDiaperKind(_ kind: DiaperKind?, id: String) {
        run { try $0.setDiaperKind(kind, id: id) }
    }

    /// 时间轴编辑（§3.3 规则 3）。非法区间由状态机挡下并提示（AC-7）。
    func update(_ event: BabyEvent) {
        run { try $0.update(event) }
    }

    /// 删除单条记录（§3.3 规则 4，二次确认由 UI 负责）。
    func delete(_ e: BabyEvent) {
        run { try $0.delete(e) }
    }

    var ongoing: BabyEvent? { events.first { $0.ongoing } }

    func lastOccurrence(of type: EventType) -> Date? {
        events.filter { $0.type == type }.map(\.startAt).max()
    }

    /// §3.2：最近一次母乳（FEED 且非奶粉）。历史无 feedMethod 的行已在迁移时回填为 BREAST，
    /// 因此这里用 feedMethod == .breast 判定，不再把"字段为空的未知段"混进母乳。
    func lastBreast() -> BabyEvent? {
        events.filter { $0.type == .feed && $0.feedMethod == .breast }.max { $0.startAt < $1.startAt }
    }

    /// §3.2：最近一次奶粉（FEED/FORMULA 零时长段）。
    func lastFormula() -> BabyEvent? {
        events.filter { $0.isFormula }.max { $0.startAt < $1.startAt }
    }

    /// §3.2：最近一次排便。返回整条而非时刻，状态卡要看它的小便/大类别。
    func lastPoop() -> BabyEvent? {
        events.filter { $0.type == .poop }.max { $0.startAt < $1.startAt }
    }

    func events(on day: Date) -> [BabyEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.startAt, inSameDayAs: day) }
            .sorted { $0.startAt > $1.startAt }
    }

    /// 与当天窗口有重叠的事件（含跨天时间段），供 24h 活动带按窗口裁剪绘制。
    /// 镜像 Android RecorderViewModel.eventsOverlapping。
    func eventsOverlapping(day: Date, now: Date) -> [BabyEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        return events.filter { e in
            if e.type.isInterval {
                let effEnd = e.endAt ?? (e.ongoing ? now : e.startAt)
                return e.startAt < dayEnd && effEnd > dayStart
            } else {
                return e.startAt >= dayStart && e.startAt < dayEnd
            }
        }
        .sorted { $0.startAt > $1.startAt }
    }

    // MARK: - helpers

    /// 统一写入路径：库不可用即如实报失败；成功则刷新并清除提示；
    /// 存储类失败按 `retries` 重试（状态机两个写入口都包在事务里，重试不会留下半条记录，ARCH §2.3）。
    /// 校验类失败（MachineError）不重试 —— 重试同样的输入只会再失败一次，只把文案换成对应的校验提示。
    private func run(retries: Int = 0, _ body: @escaping (EventStateMachine) throws -> Void) {
        guard let machine else { fail("记录未保存，请重试"); return }
        var attempt = 0
        while true {
            do {
                try body(machine)
                reload()
                errorMessage = nil
                return
            } catch let error as MachineError {
                errorMessage = StoreErrorText.text(for: error)
                reload()
                return
            } catch {
                if attempt >= retries {
                    fail("记录未保存，请重试")
                    return
                }
                attempt += 1
            }
        }
    }

    private func fail(_ message: String) {
        storeUnavailable = machine == nil
        errorMessage = message
        reload()
    }
}

/// 校验失败文案（PRD §3.1 / §3.3 异常表）。全部为客观陈述，不含健康判断用词（§4 合规禁词）。
enum StoreErrorText {
    static func text(for error: MachineError) -> String {
        switch error {
        case .invalidVolume: return "请输入有效的毫升数"
        case .invalidInterval: return "结束时间不能早于开始时间"
        case .inconsistentFormula: return "奶粉记录只需选择发生时刻"
        }
    }
}

@main
struct BabyClockApp: App {
    @StateObject private var recorder: Recorder

    init() {
        _recorder = StateObject(wrappedValue: Recorder())
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
    @EnvironmentObject private var recorder: Recorder

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("记录", systemImage: "house.fill") }
            TimelineScreen()
                .tabItem { Label("时间轴", systemImage: "calendar") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
        }
        .tint(Warm.primaryStrong)
        .safeAreaInset(edge: .bottom) { WriteFailureBanner() }
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

/// 写库失败 / 校验失败横幅：PRD §3.1 要求失败必须可见，不能静默丢弃。
/// 只做客观陈述，不含任何健康判断文案（§4 合规禁词）。
struct WriteFailureBanner: View {
    @EnvironmentObject private var recorder: Recorder

    var body: some View {
        if let message = recorder.errorMessage {
            HStack(spacing: 10) {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button {
                    recorder.errorMessage = nil
                } label: {
                    Image(systemName: "xmark").font(.caption.bold())
                }
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityLabel("关闭提示")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0xD33A2C))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

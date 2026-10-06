import AppIntents
import Foundation
import WidgetKit

/// 系统语音快捷指令（Siri / 快捷指令 App），PRD §3.6（仅 iOS）。
/// 使用系统自带语音能力：App 自身不录音、不做语音识别、不联网（§3.6 规则 4）。
/// 每条指令等同点击对应按钮，走同一状态机与 submitFormula（规则 3），写入后刷新小组件时间线。
///
/// 五类动作各一个专用 Intent（规则 1）：
///   RecordSleepIntent     —— 记录/结束睡觉（时间段 toggle）
///   RecordBreastIntent    —— 记录/结束吃母乳（时间段 toggle）
///   RecordFormulaIntent   —— 记录喝奶粉 N 毫升（零时长段，带参数）
///   RecordMedicineIntent  —— 记录吃药（瞬时）
///   RecordPoopIntent      —— 记录排便（瞬时）
/// 全部 openAppWhenRun = false（规则 5），保证锁屏后台执行不跳转 UI。

// MARK: - 语音写入助手

/// 统一的语音写入入口。
/// ⚠️ 不使用 v1.0 的 `(try? SQLiteStore()) ?? InMemoryEventStore()` 静默回退：
/// 生产库打开失败时写进临时内存库会「假装成功」并丢失记录（违背 AC-21：锁屏写入不得静默丢失）。
/// 这里改为打开失败即抛错，由各 Intent 转成 saveFailedDialog 的语音反馈，绝不谎报已记录。
enum VoiceRecorder {
    enum VoiceError: Error { case storeUnavailable }

    /// 写入失败 / 库不可用时的统一语音反馈（客观陈述，不含健康判断，符合 §3.4）。
    static let saveFailedDialog = "记录未保存，请重试"

    static func makeMachine() throws -> EventStateMachine {
        guard let store = try? SQLiteStore() else { throw VoiceError.storeUnavailable }
        return EventStateMachine(store: store)
    }

    /// 写入后刷新所有小组件时间线（锁屏 / 桌面），让状态卡与走秒立即同步。
    static func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - 睡觉（时间段 toggle）

/// 「记录宝宝睡觉」/「结束睡觉」：等同点击睡觉按钮，开始或结束一个睡眠段。
struct RecordSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "记录宝宝睡觉"
    static var description = IntentDescription("开始或结束宝宝的睡觉计时，仅保存在本机。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let machine = try VoiceRecorder.makeMachine()
            let e = try machine.submit(type: .sleep, now: Date(), source: .voice)
            VoiceRecorder.refreshWidgets()
            let msg = e.ongoing ? "已开始记录睡觉" : "已结束睡觉"
            return .result(dialog: IntentDialog(stringLiteral: msg))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: VoiceRecorder.saveFailedDialog))
        }
    }
}

// MARK: - 母乳（时间段 toggle）

/// 「记录宝宝吃母乳」/「结束吃母乳」：等同点击母乳按钮。
/// 走 submit(.feed)，状态机会把新开的吃奶段标记为 BREAST（见 EventStateMachine.submitInterval）。
struct RecordBreastIntent: AppIntent {
    static var title: LocalizedStringResource = "记录宝宝吃母乳"
    static var description = IntentDescription("开始或结束宝宝的母乳计时，仅保存在本机。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let machine = try VoiceRecorder.makeMachine()
            let e = try machine.submit(type: .feed, now: Date(), source: .voice)
            VoiceRecorder.refreshWidgets()
            let msg = e.ongoing ? "已开始记录母乳" : "已结束母乳"
            return .result(dialog: IntentDialog(stringLiteral: msg))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: VoiceRecorder.saveFailedDialog))
        }
    }
}

// MARK: - 奶粉（零时长段，带毫升参数）

/// 「记录宝宝喝奶粉 N 毫升」：走 submitFormula，写入一条 start==end==now 的零时长 FEED/FORMULA 段，
/// 并打断当前进行中的时间段（§3.0 取舍 2）。奶粉永不 ongoing。
///
/// 毫升参数（§3.6 规则 2）：
///   - 一句话已带数值（「…喝奶粉 90 毫升」）→ App Intents 直接从短语解析 \(\.$volume)，不再追问；
///   - 未带数值 → 通过 requestValueDialog 追问「喝了多少毫升？」；
///   - 追问超时 / 用户未答 → 系统在执行 perform 前即取消，天然不产生半条记录（§3.6 异常表）。
/// 非法值（0 / 负数）→ guard 拦下，取消且不写库，绝不落 0/null（state-machine.md submitFormula 要点 3）。
///
/// 已知取舍：§3.1「> 500ml 二次确认」依赖 UI 面板，无法在 openAppWhenRun=false 的后台语音里弹确认；
/// PRD 将 >500 定义为「允许写入」，故语音按用户口述的正值直接写入，二次确认仍只在 App 内面板生效。
// MARK: - 毫升数实体（§3.6 规则 2）

/// 快捷指令短语只能插值 AppEntity / AppEnum 类型的参数 —— 这是 App Intents 的硬性限制
/// （Int 会被元数据导出以 "'AppEntity' and 'AppEnum' are the only allowed types" 拒绝），
/// 而 §3.6 规则 2 要求「一句话已带数值」能直接解析，所以把毫升数包装成实体。
/// EntityStringQuery 让 Siri 能把口述的任意数字解析成实体值，不限于常用档位。
struct VolumeMlEntity: AppEntity, Identifiable, Hashable {
    let id: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "毫升数")
    static var defaultQuery = VolumeMlQuery()

    init(_ ml: Int) { id = String(ml) }

    var ml: Int { Int(id) ?? 0 }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(ml)") }
}

struct VolumeMlQuery: EntityStringQuery {
    static var defaultResult: VolumeMlEntity? { nil }

    func entities(for identifiers: [String]) async throws -> [VolumeMlEntity] {
        identifiers.compactMap { Int($0) }.map(VolumeMlEntity.init)
    }

    /// 只取口述里的数字；解析不出正数就返回空候选，交由 requestValueDialog 追问，不猜值。
    func entities(matching string: String) async throws -> [VolumeMlEntity] {
        let digits = string.filter(\.isNumber)
        guard let ml = Int(digits), ml > 0 else { return [] }
        return [VolumeMlEntity(ml)]
    }

    func suggestedEntities() async throws -> [VolumeMlEntity] {
        [60, 90, 120].map(VolumeMlEntity.init)
    }
}

struct RecordFormulaIntent: AppIntent {
    static var title: LocalizedStringResource = "记录宝宝喝奶粉"
    static var description = IntentDescription("记录宝宝喝了多少毫升奶粉，仅保存在本机。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "毫升数", requestValueDialog: "喝了多少毫升？")
    var volume: VolumeMlEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ml = volume.ml
        guard ml > 0 else {
            return .result(dialog: IntentDialog(stringLiteral: "毫升数无效，已取消"))
        }
        do {
            let machine = try VoiceRecorder.makeMachine()
            try machine.submitFormula(now: Date(), volumeMl: ml, source: .voice)
            VoiceRecorder.refreshWidgets()
            return .result(dialog: IntentDialog(stringLiteral: "已记录奶粉 \(ml) 毫升"))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: VoiceRecorder.saveFailedDialog))
        }
    }
}

// MARK: - 吃药（瞬时）

/// 「记录宝宝吃药」：瞬时事件，不打断进行中的时间段（§3.0）。
struct RecordMedicineIntent: AppIntent {
    static var title: LocalizedStringResource = "记录宝宝吃药"
    static var description = IntentDescription("记录宝宝吃药的时刻，仅保存在本机。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let machine = try VoiceRecorder.makeMachine()
            try machine.submit(type: .medicine, now: Date(), source: .voice)
            VoiceRecorder.refreshWidgets()
            return .result(dialog: IntentDialog(stringLiteral: "已记录吃药"))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: VoiceRecorder.saveFailedDialog))
        }
    }
}

// MARK: - 排便（瞬时）

/// 「记录宝宝排便」：瞬时事件，不打断进行中的时间段（§3.0）。
struct RecordPoopIntent: AppIntent {
    static var title: LocalizedStringResource = "记录宝宝排便"
    static var description = IntentDescription("记录宝宝排便的时刻，仅保存在本机。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let machine = try VoiceRecorder.makeMachine()
            try machine.submit(type: .poop, now: Date(), source: .voice)
            VoiceRecorder.refreshWidgets()
            return .result(dialog: IntentDialog(stringLiteral: "已记录排便"))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: VoiceRecorder.saveFailedDialog))
        }
    }
}

// MARK: - 快捷指令短语（iOS 17+ 自动暴露，§3.6 规则 7）
//
// 事件类型枚举 BabyEventTypeAppEnum 已移至 BabyClock/Shared/AppEnums.swift：
// Widget target 需要它，但不该连带编译本文件的 AppShortcutsProvider。

/// 在「快捷指令」App / Siri 中可发现的短语。每条短语均含 \(.applicationName)（发现性最稳），
/// 奶粉短语另含 \(\.$volume) 参数以支持「一句话带数值直接解析」。
/// 用户仍可在系统「快捷指令」App 中自定义触发短语（§3.6 规则 6）。
struct BabyClockShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordSleepIntent(),
            phrases: [
                "用\(.applicationName)记录宝宝睡觉",
                "用\(.applicationName)结束睡觉"
            ],
            shortTitle: "记录宝宝睡觉",
            systemImageName: "moon.fill"
        )
        AppShortcut(
            intent: RecordBreastIntent(),
            phrases: [
                "用\(.applicationName)记录宝宝吃母乳",
                "用\(.applicationName)结束吃母乳"
            ],
            shortTitle: "记录宝宝吃母乳",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: RecordFormulaIntent(),
            phrases: [
                "用\(.applicationName)记录宝宝喝奶粉\(\.$volume)毫升",
                "用\(.applicationName)记录宝宝喝了\(\.$volume)毫升奶粉"
            ],
            shortTitle: "记录宝宝喝奶粉",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: RecordMedicineIntent(),
            phrases: ["用\(.applicationName)记录宝宝吃药"],
            shortTitle: "记录宝宝吃药",
            systemImageName: "pills.fill"
        )
        AppShortcut(
            intent: RecordPoopIntent(),
            phrases: ["用\(.applicationName)记录宝宝排便"],
            shortTitle: "记录宝宝排便",
            systemImageName: "toilet.fill"
        )
    }
}

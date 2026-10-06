import AppIntents
import Foundation

/// 暴露给系统的四类事件短语。
/// 位于 Shared/ 而非 BabyClockIntents/：主 App（Siri 快捷指令）与 Widget target 都要编译它，
/// 而 Intents 文件里的 AppShortcutsProvider 只能属于主 App，不能整体塞进小组件扩展。
enum BabyEventTypeAppEnum: String, AppEnum {
    case feed, sleep, medicine, poop
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "事件类型"
    static var caseDisplayRepresentations: [BabyEventTypeAppEnum: DisplayRepresentation] = [
        .feed: "吃奶", .sleep: "睡觉", .medicine: "吃药", .poop: "排便"
    ]
    var domain: EventType {
        switch self {
        case .feed: return .feed
        case .sleep: return .sleep
        case .medicine: return .medicine
        case .poop: return .poop
        }
    }
}

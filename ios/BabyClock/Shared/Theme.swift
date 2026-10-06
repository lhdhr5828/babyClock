import SwiftUI

/// 暖色调主题，映射 design/design-tokens.json
enum Warm {
    static let bg          = Color(hex: 0xFFF8F1)
    static let elevated    = Color.white
    static let sunken      = Color(hex: 0xFBEDE0)
    static let primary     = Color(hex: 0xFF8A5C)
    static let primaryStrong = Color(hex: 0xF2703F)
    static let primarySoft = Color(hex: 0xFFD9C4)
    static let text1       = Color(hex: 0x4A3728)
    static let text2       = Color(hex: 0x8C7362)
    static let text3       = Color(hex: 0xB79E8C)
    static let hairline    = Color(hex: 0xF0E0D2)

    static func fill(_ t: EventType) -> Color {
        switch t {
        case .feed: return Color(hex: 0xFFB74D)
        case .sleep: return Color(hex: 0xF2A6A0)
        case .medicine: return Color(hex: 0xFF8A80)
        case .poop: return Color(hex: 0xC9A227)
        }
    }
    static func soft(_ t: EventType) -> Color {
        switch t {
        case .feed: return Color(hex: 0xFFE9C7)
        case .sleep: return Color(hex: 0xFBE0DD)
        case .medicine: return Color(hex: 0xFFDDD9)
        case .poop: return Color(hex: 0xF2EBCB)
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// iOS squircle 圆角图标容器
struct SquircleIcon<Content: View>: View {
    let type: EventType
    var size: CGFloat = 58
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(Warm.soft(type))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// 事件图标（iOS squircle 风格矢量图形）。
/// 放在 Theme 而非 HomeView：Widget target 只编译 Shared/ + Theme，需要在这里取到它。
struct EventGlyph: View {
    let type: EventType
    let size: CGFloat
    var body: some View {
        Image(systemName: symbol)
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Warm.fill(type))
    }
    private var symbol: String {
        switch type {
        case .feed: return "cup.and.saucer.fill"
        case .sleep: return "moon.zzz.fill"
        case .medicine: return "cross.case.fill"
        case .poop: return "leaf.fill"
        }
    }
}

/// 把 TimeInterval 格式化为 HH:MM:SS
func formatDuration(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}

func formatClock(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
}

func relativeTimeString(_ d: Date, now: Date = Date()) -> String {
    let diff = Int(now.timeIntervalSince(d))
    if diff < 60 { return "刚刚" }
    if diff < 3600 { return "\(diff / 60) 分钟前" }
    if diff < 86400 { return "\(diff / 3600) 小时前" }
    return "\(diff / 86400) 天前"
}

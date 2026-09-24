import SwiftUI
import Intents

// MARK: - 检测（§3.6 规则 7 / 异常表）

/// 首次启动检测语音记录可用性，驱动一次性引导的内容分支。
enum SiriAvailability {

    /// App Shortcuts 短语在当前系统上的暴露方式（§3.6 规则 7）。
    enum ShortcutExposure {
        case auto          // iOS 17+：自动暴露短语，无需手动配置
        case manual        // iOS 16：需用户在「快捷指令」App 手动添加一次
        case unsupported   // iOS 16 以下：隐藏语音项，降级为小组件入口（异常表行 4）
    }

    static var exposure: ShortcutExposure {
        if #available(iOS 17, *) { return .auto }
        if #available(iOS 16, *) { return .manual }
        return .unsupported
    }

    /// Siri 主开关是否开启（异常表行 1「Siri 未开启」）。
    /// ⚠️ 无公开 API 检测「锁屏时允许 Siri」这一子开关，只能检测总开关；
    /// 锁屏权限以文案引导用户自行到「设置 > Siri 与搜索」确认。
    static var siriEnabled: Bool {
        INPreferences.siriStatus() == .enabled
    }
}

// MARK: - 一次性引导（§3.6 规则 7）

/// 首次启动弹出一次的语音记录引导。内容随系统版本与 Siri 状态自适应，
/// 全部为客观说明，不含任何健康判断/阈值/提醒文案（§3.4 合规红线）。
struct SiriGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let exposure = SiriAvailability.exposure
    private let siriOn = SiriAvailability.siriEnabled

    private struct Phrase: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    private let phrases: [Phrase] = [
        Phrase(icon: "moon.fill", text: "记录宝宝睡觉 / 结束睡觉"),
        Phrase(icon: "heart.fill", text: "记录宝宝吃母乳 / 结束吃母乳"),
        Phrase(icon: "cup.and.saucer.fill", text: "记录宝宝喝奶粉 90 毫升"),
        Phrase(icon: "pills.fill", text: "记录宝宝吃药"),
        Phrase(icon: "leaf.fill", text: "记录宝宝排便"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !siriOn { siriOffBanner }
                    Text(intro)
                        .font(.subheadline)
                        .foregroundStyle(Warm.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    phraseCard
                    if exposure == .manual { manualHint }
                    privacyNote
                }
                .padding(20)
            }
            footer
        }
        .background(Warm.bg.ignoresSafeArea())
    }

    // MARK: header
    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Warm.primary, Warm.primaryStrong],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 68, height: 68)
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Warm.primaryStrong.opacity(0.3), radius: 12, y: 4)
            Text("用 Siri，免解锁记一笔")
                .font(.title3).fontWeight(.heavy)
                .foregroundStyle(Warm.text1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var intro: String {
        switch exposure {
        case .auto:
            return "语音指令已为你准备好。锁屏时对 Siri 说出下面任意一句即可记录，App 不会被打开，数据只存在这台设备。"
        case .manual:
            return "先点下方按钮打开「快捷指令」App，把本 App 的语音指令添加一次；之后锁屏对 Siri 说下面任意一句即可记录。"
        case .unsupported:
            return "当前系统不支持语音记录，你可以改用锁屏小组件一键记录。"
        }
    }

    // MARK: Siri 未开启（异常表行 1）
    private var siriOffBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Warm.primaryStrong)
            Text("检测到 Siri 未开启。请前往「设置 > Siri 与搜索」打开 Siri，并允许锁屏时使用，语音记录才能生效。")
                .font(.footnote)
                .foregroundStyle(Warm.text1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Warm.primarySoft.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: 短语清单
    private var phraseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可以这样说")
                .font(.footnote).fontWeight(.bold)
                .foregroundStyle(Warm.text2)
            ForEach(phrases) { p in
                HStack(spacing: 12) {
                    Image(systemName: p.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Warm.primaryStrong)
                        .frame(width: 22)
                    Text(p.text)
                        .font(.subheadline)
                        .foregroundStyle(Warm.text1)
                    Spacer(minLength: 0)
                }
            }
            Text("说指令时在前面带上本 App 名称即可触发，也可在「快捷指令」App 里自定义你习惯的说法。")
                .font(.caption2)
                .foregroundStyle(Warm.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Warm.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: iOS 16 手动添加入口（§3.6 规则 7）
    private var manualHint: some View {
        Button {
            if let url = URL(string: "shortcuts://") { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                Text("打开「快捷指令」App 添加")
            }
            .font(.subheadline).fontWeight(.semibold)
            .foregroundStyle(Warm.primaryStrong)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Warm.primarySoft.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 隐私说明（§3.6 规则 4）
    private var privacyNote: some View {
        Label("语音由系统 Siri 处理，App 不录音、不联网，记录只保存在这台设备。",
              systemImage: "lock.shield.fill")
            .font(.caption2)
            .foregroundStyle(Warm.text3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: footer
    private var footer: some View {
        Button {
            dismiss()
        } label: {
            Text("知道了")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(colors: [Warm.primary, Warm.primaryStrong],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(20)
        .background(Warm.bg)
    }
}

#Preview {
    SiriGuideView()
}

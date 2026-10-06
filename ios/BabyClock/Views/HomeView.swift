import SwiftUI

struct HomeView: View {
    @EnvironmentObject var recorder: Recorder
    @State private var showFormula = false
    /// 刚结束的那段母乳 id：非空即等待补填左右侧（§3.1 规则 5，可跳过）
    @State private var pendingSideId: String?
    /// 刚落库的那条排便 id：非空即等待补填小便/大便（同一手法，同样可跳过）
    @State private var pendingDiaperId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatusCard()
                    Text("轻点记录")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(Warm.text2)
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                        ForEach(HomeAction.allCases, id: \.self) { action in
                            HomeActionButton(action: action, ongoing: isOngoing(action)) {
                                click(action)
                            }
                        }
                    }
                    TodayPreview()
                }
                .padding(20)
            }
            .background(Warm.bg.ignoresSafeArea())
            .navigationTitle("小宝")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFormula) {
                FormulaPanel(onConfirm: { ml in
                    recorder.submitFormula(volumeMl: ml, source: .app)
                })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: pendingSideBinding) {
                BreastSidePanel { side in
                    if let id = pendingSideId { recorder.setBreastSide(side, id: id) }
                    pendingSideId = nil
                }
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: pendingDiaperBinding) {
                DiaperKindPanel { kind in
                    if let id = pendingDiaperId { recorder.setDiaperKind(kind, id: id) }
                    pendingDiaperId = nil
                }
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var pendingSideBinding: Binding<Bool> {
        Binding(get: { pendingSideId != nil },
               set: { if !$0 { pendingSideId = nil } })
    }

    private var pendingDiaperBinding: Binding<Bool> {
        Binding(get: { pendingDiaperId != nil },
               set: { if !$0 { pendingDiaperId = nil } })
    }

    /// 点击动作：奶粉弹毫升面板（不直接写库），排便弹大小便面板（先写库再问），
    /// 其余走状态机（母乳/睡觉 toggle，吃药瞬时）。
    private func click(_ action: HomeAction) {
        if action == .formula {
            showFormula = true
            return
        }
        // 这次点击结束了一段母乳 → 段已落库，随后追问一次左右侧（可跳过，不阻断已完成的记录）
        if action == .breast, let o = recorder.ongoing, o.type == .feed {
            recorder.submit(.feed, source: .app)
            pendingSideId = o.id
            return
        }
        // 排便先落库再追问：一键仍然记录成功，"这一次是"是可选的补充信息。
        // 下滑关闭面板 = 跳过，diaperKind 保持 nil，显示回"排便"。
        if action == .poop {
            pendingDiaperId = recorder.submit(.poop, source: .app)?.id
            return
        }
        recorder.submit(action.type, source: .app)
    }

    /// 该动作是否处于"进行中"高亮态。进行中的吃奶段必为母乳（奶粉永不 ongoing）。
    private func isOngoing(_ action: HomeAction) -> Bool {
        guard let o = recorder.ongoing else { return false }
        switch action {
        case .breast: return o.type == .feed
        case .sleep: return o.type == .sleep
        case .formula, .medicine, .poop: return false
        }
    }
}

/// 母乳左右侧一次点选（PRD §3.1 规则 5）。三项均可选，也可整块跳过 —— 跳过后字段为空，
/// 记录本身已经落库不受影响，事后可在时间轴编辑里补填（§3.3 规则 3）。
struct BreastSidePanel: View {
    let onPick: (BreastSide?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("这一段是哪一侧？")
                .font(.title3).fontWeight(.heavy).foregroundStyle(Warm.text1)
            Text("可跳过，之后在时间轴里补填")
                .font(.footnote).foregroundStyle(Warm.text2)
            HStack(spacing: 8) {
                ForEach(BreastSide.allCases, id: \.self) { side in
                    ChoiceTile(side.title) { onPick(side) }
                }
            }
            Button { onPick(nil) } label: {
                Text("跳过")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Warm.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Warm.elevated.ignoresSafeArea())
    }
}

/// 排便的小便/大便一次点选（与母乳左右侧同一口径：先落库、再追问、可跳过、时间轴可补填）。
/// 不追问的快捷入口（小组件 / 通知 / Siri）留下的记录字段为空，显示时退回"排便"。
struct DiaperKindPanel: View {
    let onPick: (DiaperKind?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("这一次是？")
                .font(.title3).fontWeight(.heavy).foregroundStyle(Warm.text1)
            Text("可跳过，之后在时间轴里补填")
                .font(.footnote).foregroundStyle(Warm.text2)
            HStack(spacing: 8) {
                ForEach(DiaperKind.allCases, id: \.self) { k in
                    ChoiceTile(k.title) { onPick(k) }
                }
            }
            Button { onPick(nil) } label: {
                Text("跳过")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Warm.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Warm.elevated.ignoresSafeArea())
    }
}

/// 追问面板里的档位按钮（左右侧 / 大小便两处共用同一形态）。
private struct ChoiceTile: View {
    let title: String
    let onTap: () -> Void

    init(_ title: String, onTap: @escaping () -> Void) {
        self.title = title
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Warm.primaryStrong)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Warm.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 当前状态卡：进行中事件 + 实时走秒 + 突出"距上次喂奶"(§3.2 规则5) + 五项"距上次"胶囊(母乳/奶粉拆分，规则3/6)
struct StatusCard: View {
    @EnvironmentObject var recorder: Recorder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let o = recorder.ongoing {
                HStack(spacing: 8) {
                    Circle().fill(.white).frame(width: 9, height: 9)
                        .opacity(0.9)
                    Text("正在进行 · \(o.label)")
                        .font(.footnote).fontWeight(.semibold)
                }
                .foregroundStyle(.white.opacity(0.92))
                Text(formatDuration(recorder.now.timeIntervalSince(o.startAt)))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("开始于 \(formatClock(o.startAt)) · 再次点击「\(o.label)」可结束")
                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
            } else {
                Text("当前无进行中的活动")
                    .font(.headline).foregroundStyle(.white)
                Text("点下方按钮开始记录")
                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
            }
            // §3.2 规则5：突出"距上次喂奶"（母乳/奶粉更近的一次），字号高于下方五项；仅客观事实、无判断性文案
            if let feed = [recorder.lastBreast(), recorder.lastFormula()].compactMap({ $0 })
                .max(by: { $0.startAt < $1.startAt }) {
                Text(feedHighlightText(feed, now: recorder.now))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }

            // §3.2 规则3/6：五项"距上次"（母乳带侧别与时长、奶粉带毫升、排便带小便/大便），超宽自动换行
            FlowLayout(spacing: 8) {
                if let b = recorder.lastBreast() { chip(breastChipText(b, now: recorder.now)) }
                if let f = recorder.lastFormula() { chip(formulaChipText(f, now: recorder.now)) }
                ForEach([EventType.sleep, .medicine], id: \.self) { t in
                    if let last = recorder.lastOccurrence(of: t) {
                        chip("\(eventEmoji(t)) \(relativeTimeString(last, now: recorder.now))")
                    }
                }
                if let p = recorder.lastPoop() { chip(poopChipText(p, now: recorder.now)) }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [Warm.primary, Warm.primaryStrong],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Warm.primaryStrong.opacity(0.28), radius: 14, y: 4)
    }
    private func chip(_ s: String) -> some View {
        Text(s).font(.caption2).fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.18), in: Capsule())
    }
}

/// 状态卡胶囊用的类型图标（对齐 Android Format.emoji）。
private func eventEmoji(_ t: EventType) -> String {
    switch t { case .feed: "🍼"; case .sleep: "😴"; case .medicine: "💊"; case .poop: "🧷" }
}

// MARK: - §3.2 状态卡文案（母乳/奶粉拆分 + 距上次喂奶突出项）

/// 规则5：突出"距上次喂奶"（取母乳/奶粉更近的一次）。仅陈述客观事实，禁止"该喂奶了/间隔过长"等判断性文案（§3.4 合规红线）。
func feedHighlightText(_ e: BabyEvent, now: Date) -> String {
    let rel = relativeTimeString(e.startAt, now: now)
    return e.isFormula ? "喂奶 · \(rel) · 奶粉 \(e.volumeMl ?? 0)ml" : "喂奶 · \(rel) · \(e.label)"
}

/// 规则3/6：母乳 chip，带左右侧（未补填则不带）与时长。
func breastChipText(_ e: BabyEvent, now: Date) -> String {
    "\(e.label) \(humanDuration(e.duration(now: now))) · \(relativeTimeString(e.startAt, now: now))"
}

/// 规则3/6：奶粉 chip，带毫升。
func formulaChipText(_ e: BabyEvent, now: Date) -> String {
    "奶粉 \(e.volumeMl ?? 0)ml · \(relativeTimeString(e.startAt, now: now))"
}

/// 排便 chip：label 已带"小便/大便/大小便"，未补填（快捷入口或跳过）时 label 回到"排便"。
func poopChipText(_ e: BabyEvent, now: Date) -> String {
    "\(e.diaperKind?.emoji ?? eventEmoji(.poop)) \(e.label) · \(relativeTimeString(e.startAt, now: now))"
}

/// 简单流式布局（iOS 16 Layout 协议）：子视图按内容宽度从左到右排列，超出容器宽度则换行。
/// 用于状态卡五项"距上次"胶囊自动换行（§3.2 规则3）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        for (i, row) in makeRows(width: width, subviews: subviews).enumerated() {
            if i > 0 { height += spacing }
            height += row.height
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in makeRows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { let indices: [Int]; let height: CGFloat }

    private func makeRows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var indices: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let added = indices.isEmpty ? size.width : rowWidth + spacing + size.width
            if !indices.isEmpty && added > width {
                rows.append(Row(indices: indices, height: rowHeight))
                indices = [i]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                indices.append(i)
                rowWidth = added
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !indices.isEmpty { rows.append(Row(indices: indices, height: rowHeight)) }
        return rows
    }
}

/// 首页五个记录动作（PRD §3.1）：吃奶在 UI 层拆为母乳 / 奶粉。
enum HomeAction: String, CaseIterable {
    case breast, formula, sleep, medicine, poop

    var label: String {
        switch self {
        case .breast: return "母乳"
        case .formula: return "奶粉"
        case .sleep: return "睡觉"
        case .medicine: return "吃药"
        case .poop: return "排便"
        }
    }
    var emoji: String {
        switch self {
        case .breast: return "🤱"
        case .formula: return "🍼"
        case .sleep: return "😴"
        case .medicine: return "💊"
        case .poop: return "🧷"
        }
    }
    /// 底层事件类型（母乳/奶粉同属 FEED，形态由入口与状态机区分）。
    var type: EventType {
        switch self {
        case .breast, .formula: return .feed
        case .sleep: return .sleep
        case .medicine: return .medicine
        case .poop: return .poop
        }
    }
}

struct HomeActionButton: View {
    let action: HomeAction
    let ongoing: Bool
    let onTap: () -> Void
    @State private var tapped = false

    var body: some View {
        Button {
            onTap()
            tapped = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { tapped = false }
        } label: {
            VStack(spacing: 10) {
                SquircleIcon(type: action.type) {
                    Text(action.emoji).font(.system(size: 28))
                }
                Text(action.label)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Warm.text1)
                Text(hint)
                    .font(.system(size: 11, weight: ongoing ? .bold : .semibold))
                    .foregroundStyle(ongoing ? Warm.primaryStrong : Warm.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(ongoing ? Warm.primarySoft : Warm.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(hex: 0xC78D63).opacity(0.14), radius: 10, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(tapped ? Warm.primaryStrong : .clear, lineWidth: 2)
            )
            .scaleEffect(tapped ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: tapped)
        }
        .buttonStyle(.plain)
    }

    private var hint: String {
        if ongoing { return "进行中" }
        if action == .formula { return "记毫升" }
        return action.type.isInterval ? "时间段" : "瞬时"
    }
}

/// 奶粉毫升快选面板（PRD §3.1 规则 2 / 交互流程"奶粉一次点击"）。
/// 档位直点即记录；自定义需校验（0/负/空 → 阻止写库并保持面板打开）；>500ml 二次确认。
/// 不选中而下滑关闭 = 取消，不写库（onConfirm 只在合法提交时触发）。
struct FormulaPanel: View {
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var custom = ""
    @State private var error: String?
    @State private var pendingLarge: Int?

    private let tiers = [30, 60, 90, 120, 150]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("奶粉 · 毫升数")
                .font(.title3).fontWeight(.heavy).foregroundStyle(Warm.text1)
            Text("点档位立即记录，或输入自定义毫升")
                .font(.footnote).foregroundStyle(Warm.text2)

            HStack(spacing: 8) {
                ForEach(tiers, id: \.self) { ml in
                    Button { commit(ml) } label: {
                        Text("\(ml)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Warm.primaryStrong)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Warm.primarySoft)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                TextField("自定义毫升", text: $custom)
                    .keyboardType(.numberPad)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Warm.text1)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Warm.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: custom) { newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue { custom = filtered }
                    }
                Button { commit(Int(custom)) } label: {
                    Text("记录")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Warm.primaryStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(Color(hex: 0xD33A2C))
            }

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Text("取消")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Warm.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Warm.elevated.ignoresSafeArea())
        .alert("确认毫升数", isPresented: pendingLargeBinding) {
            Button("返回修改", role: .cancel) { pendingLarge = nil }
            Button("确认") {
                if let ml = pendingLarge { onConfirm(ml) }
                pendingLarge = nil
                dismiss()
            }
        } message: {
            Text("一次喝了 \(pendingLarge ?? 0)ml 以上？")
        }
    }

    private var pendingLargeBinding: Binding<Bool> {
        Binding(get: { pendingLarge != nil },
                set: { if !$0 { pendingLarge = nil } })
    }

    private func commit(_ v: Int?) {
        guard let v, v > 0 else { error = "请输入有效的毫升数"; return }
        error = nil
        if v > 500 { pendingLarge = v; return }
        onConfirm(v)
        dismiss()
    }
}

struct TodayPreview: View {
    @EnvironmentObject var recorder: Recorder
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今天时间轴").font(.subheadline).fontWeight(.bold).foregroundStyle(Warm.text2)
            let list = Array(recorder.events(on: recorder.now).prefix(3))
            if list.isEmpty {
                Text("今天还没有记录，点上方按钮开始").font(.footnote).foregroundStyle(Warm.text3)
            } else {
                ForEach(list) { e in TimelineRow(event: e, now: recorder.now) }
            }
        }
        .padding(.top, 8)
    }
}

/// 事件图标定义在 Shared/Theme.swift：Widget target 也要用它。

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView().environmentObject(Recorder(store: InMemoryEventStore()))
    }
}

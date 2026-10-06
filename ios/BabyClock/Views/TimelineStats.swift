import SwiftUI
import Charts

// MARK: - 时间轴
/// 命名为 TimelineScreen：`TimelineView` 会与 SwiftUI 的 `TimelineView`（iOS 15+）同名冲突。
struct TimelineScreen: View {
    @EnvironmentObject var recorder: Recorder
    @State private var day: Date = Date()
    /// 被点开编辑的那条记录（§3.3 交互流程 3：点击记录 → 编辑面板）
    @State private var editing: BabyEvent?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayHeader(day: $day)
                DayRibbon(
                    events: recorder.eventsOverlapping(day: day, now: recorder.now),
                    day: day,
                    now: recorder.now
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                let list = recorder.events(on: day)
                if list.isEmpty {
                    Spacer()
                    Text(emptyText).foregroundStyle(Warm.text3)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(list) { e in
                                Button { editing = e } label: {
                                    TimelineRow(event: e, now: recorder.now)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Warm.bg.ignoresSafeArea())
            .navigationTitle("时间轴")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { e in
                EventEditPanel(original: e)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// §3.3 异常表：当天无记录的引导文案（今天指向首页按钮，历史日期只做陈述）。
    private var emptyText: String {
        Calendar.current.isDateInToday(day)
            ? "今天还没有记录，点首页按钮开始"
            : "这一天还没有记录"
    }
}

struct DayHeader: View {
    @Binding var day: Date
    var body: some View {
        HStack {
            Button { shift(-1) } label: { navIcon("chevron.left") }
            VStack(spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Warm.text1)
                Text(dateStr).font(.caption).foregroundStyle(Warm.text2)
            }
            .frame(maxWidth: .infinity)
            Button { shift(1) } label: { navIcon("chevron.right") }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Warm.elevated)
    }
    private func navIcon(_ s: String) -> some View {
        Image(systemName: s).font(.system(size: 15, weight: .bold))
            .foregroundStyle(Warm.text2)
            .frame(width: 34, height: 34)
            .background(Warm.sunken, in: Circle())
    }
    private func shift(_ d: Int) { day = Calendar.current.date(byAdding: .day, value: d, to: day)! }
    private var title: String { Calendar.current.isDateInToday(day) ? "今天" : "日期" }
    private var dateStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月d日 EEE"; f.locale = Locale(identifier: "zh_CN")
        return f.string(from: day)
    }
}

// MARK: - 24 小时活动带（PRD §3.4.1，对齐 Android DayRibbon）
/// 横轴 0–24 点，四泳道展示宝宝几点做了什么；奶粉画环不画色条，现在线仅今天显示。
private struct RibbonLane: Identifiable {
    let type: EventType
    let label: String
    var id: String { type.rawValue }
}

private let ribbonLanes: [RibbonLane] = [
    RibbonLane(type: .feed, label: "喂养"),
    RibbonLane(type: .sleep, label: "睡觉"),
    RibbonLane(type: .medicine, label: "吃药"),
    RibbonLane(type: .poop, label: "排便"),
]

struct DayRibbon: View {
    let events: [BabyEvent]
    let day: Date
    let now: Date

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }
    private var span: TimeInterval { dayEnd.timeIntervalSince(dayStart) }
    private var isToday: Bool { now >= dayStart && now < dayEnd }

    // 几何常量（pt，对齐 Android dp 值）
    private let laneH: CGFloat = 30
    private let labelW: CGFloat = 40
    private let barH: CGFloat = 12
    private let minBar: CGFloat = 3
    private let rDot: CGFloat = 4.5
    private let rFormula: CGFloat = 5.5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("24 小时活动带")
                .font(.caption).fontWeight(.semibold).foregroundStyle(Warm.text2)
            ForEach(ribbonLanes) { lane in
                HStack(spacing: 0) {
                    Text(lane.label)
                        .font(.system(size: 11)).foregroundStyle(Warm.text2)
                        .frame(width: labelW, alignment: .leading)
                    laneCanvas(lane.type)
                        .frame(maxWidth: .infinity)
                        .frame(height: laneH)
                }
            }
            axisRow
        }
        .padding(14)
        .background(Warm.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 底部时间轴 0/6/12/18/24，均匀分布（SpaceBetween），左侧让出泳道标签宽度。
    private var axisRow: some View {
        HStack(spacing: 0) {
            ForEach(["0", "6", "12", "18", "24"], id: \.self) { h in
                Text(h).font(.system(size: 10)).foregroundStyle(Warm.text3)
                if h != "24" { Spacer(minLength: 0) }
            }
        }
        .padding(.leading, labelW)
    }

    /// 单条泳道画布：轨道底色 + 该类型事件 + （今天）现在线。
    private func laneCanvas(_ type: EventType) -> some View {
        Canvas { ctx, size in
            let W = size.width
            let H = size.height
            let trackY = H / 2
            let color = Warm.fill(type)

            func xOf(_ t: Date) -> CGFloat {
                let d = min(max(t.timeIntervalSince(dayStart), 0), span)
                return CGFloat(d / span) * W
            }
            func circle(_ center: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }

            // 轨道底色
            ctx.fill(
                Path(roundedRect: CGRect(x: 0, y: trackY - barH / 2, width: W, height: barH),
                     cornerRadius: barH / 2),
                with: .color(Warm.sunken)
            )

            for e in events where e.type == type {
                if e.isFormula {
                    if e.startAt >= dayStart && e.startAt < dayEnd {
                        let c = CGPoint(x: xOf(e.startAt), y: trackY)
                        ctx.fill(circle(c, rFormula), with: .color(color))
                        ctx.fill(circle(c, rFormula * 0.4), with: .color(.white))
                    }
                } else if e.type.isInterval {
                    let s = max(e.startAt, dayStart)
                    let en = min(e.endAt ?? now, dayEnd)
                    if en > s {
                        let x1 = xOf(s)
                        var x2 = xOf(en)
                        if x2 - x1 < minBar { x2 = x1 + minBar }
                        ctx.fill(
                            Path(roundedRect: CGRect(x: x1, y: trackY - barH / 2, width: x2 - x1, height: barH),
                                 cornerRadius: barH / 2),
                            with: .color(color)
                        )
                    }
                } else if e.startAt >= dayStart && e.startAt < dayEnd {
                    let c = CGPoint(x: xOf(e.startAt), y: trackY)
                    ctx.fill(circle(c, rDot), with: .color(color))
                }
            }

            if isToday {
                var p = Path()
                p.move(to: CGPoint(x: xOf(now), y: 0))
                p.addLine(to: CGPoint(x: xOf(now), y: H))
                ctx.stroke(p, with: .color(Warm.primaryStrong), lineWidth: 1.5)
            }
        }
    }
}

struct TimelineRow: View {
    let event: BabyEvent
    var now: Date = Date()
    private var isFormula: Bool { event.isFormula }

    var body: some View {
        HStack(spacing: 12) {
            SquircleIcon(type: event.type, size: 40) {
                Group {
                    if isFormula {
                        Text("🍼").font(.system(size: 18))
                    } else {
                        EventGlyph(type: event.type, size: 20)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.ongoing ? "\(event.label) · 进行中" : event.label)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Warm.text1)
                Text(subtitle).font(.caption).foregroundStyle(Warm.text2)
            }
            Spacer()
            badge
        }
        .padding(12)
        .background(Warm.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0xC78D63).opacity(0.10), radius: 8, y: 4)
    }

    /// 右侧标记：奶粉显示毫升气泡，时间段显示时长，瞬时显示"瞬时"。
    @ViewBuilder private var badge: some View {
        if isFormula {
            capsule("\(event.volumeMl ?? 0)ml")
        } else if event.type.isInterval {
            capsule(event.ongoing
                    ? formatDuration(now.timeIntervalSince(event.startAt))
                    : humanDuration(event.duration()))
        } else {
            Text("瞬时").font(.caption).foregroundStyle(Warm.text3)
        }
    }

    private func capsule(_ s: String) -> some View {
        Text(s)
            .font(.caption).fontWeight(.heavy)
            .foregroundStyle(Warm.primaryStrong)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Warm.primarySoft, in: Capsule())
    }

    private var subtitle: String {
        if isFormula {
            return "\(formatClock(event.startAt)) · 奶粉 \(event.volumeMl ?? 0)ml"
        }
        if event.type.isInterval {
            let end = event.endAt.map(formatClock) ?? "现在"
            return "\(formatClock(event.startAt)) – \(end)"
        }
        return formatClock(event.startAt)
    }
}

func humanDuration(_ t: TimeInterval) -> String {
    let s = Int(t); let h = s / 3600; let m = (s % 3600) / 60
    if h > 0 { return "\(h) 小时 \(m) 分" }
    if m > 0 { return "\(m) 分钟" }
    return "\(s) 秒"
}

// MARK: - §3.3 规则 3/4：记录编辑与删除（AC-6 / AC-7）

/// 单条记录的编辑面板：类型、时刻、备注，奶粉另给毫升、母乳另给左右侧、排便另给小便/大便。
/// 三条口径与状态机保持一致：
/// - 奶粉是零时长段（I4），只暴露一个时刻选择器，endAt 由 `update` 跟随 startAt；
/// - 进行中的段只改开始时刻，结束时刻仍由首页的「结束」决定（I2）；
/// - 结束早于开始就地拦下，不落库（AC-7）。
struct EventEditPanel: View {
    @EnvironmentObject var recorder: Recorder
    @Environment(\.dismiss) private var dismiss

    let original: BabyEvent
    @State private var type: EventType
    @State private var method: FeedMethod
    @State private var start: Date
    @State private var end: Date
    @State private var side: BreastSide?
    @State private var diaper: DiaperKind?
    @State private var volumeText: String
    @State private var note: String
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var pendingLarge: Int?
    /// 已完成 >500ml 二次确认，避免再次进同一分支反复弹窗
    @State private var largeConfirmed = false

    init(original: BabyEvent) {
        self.original = original
        _type = State(initialValue: original.type)
        _method = State(initialValue: original.feedMethod ?? .breast)
        _start = State(initialValue: original.startAt)
        _end = State(initialValue: original.endAt ?? original.startAt)
        _side = State(initialValue: original.breastSide)
        _diaper = State(initialValue: original.diaperKind)
        _volumeText = State(initialValue: original.volumeMl.map(String.init) ?? "")
        _note = State(initialValue: original.note ?? "")
    }

    private var isFormula: Bool { type == .feed && method == .formula }
    /// 只有"时间段 + 非奶粉 + 已结束"才有独立的结束时刻选择器
    private var showsEndPicker: Bool { type.isInterval && !isFormula && !original.ongoing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("类型") {
                        segmented(EventType.allCases.map { ($0, $0.title) }, selection: $type)
                        if type == .feed {
                            segmented(FeedMethod.allCases.map { ($0, methodLabel($0)) }, selection: $method)
                                .padding(.top, 10)
                        }
                    }

                    section("时刻") {
                        VStack(alignment: .leading, spacing: 10) {
                            dateRow(original.ongoing || isFormula ? "发生时刻" : "开始时刻", $start)
                            if showsEndPicker {
                                dateRow("结束时刻", $end)
                            } else if isFormula {
                                Text("奶粉是一条时刻记录，没有时长")
                                    .font(.caption).foregroundStyle(Warm.text3)
                            } else if original.ongoing {
                                Text("这段仍在进行中，结束时刻由首页的「结束」决定")
                                    .font(.caption).foregroundStyle(Warm.text3)
                            }
                        }
                    }

                    if isFormula {
                        section("毫升数") { volumeRow }
                    } else if type == .feed {
                        section("左右侧") { sideRow }
                    } else if type == .poop {
                        section("小便 / 大便") { diaperRow }
                    }

                    section("备注") {
                        TextField("可留空", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(size: 15))
                            .foregroundStyle(Warm.text1)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Warm.sunken)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Color(hex: 0xD33A2C))
                    }
                }
                .padding(20)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    plainButton("取消") { dismiss() }
                    primaryButton("保存") { save() }
                }
                plainButton("删除这条记录") { confirmDelete = true }
            }
            .padding(20)
            .background(Warm.elevated)
        }
        .background(Warm.bg.ignoresSafeArea())
        .alert("删除这条记录？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                recorder.delete(original)
                dismiss()
            }
        } message: {
            Text(original.ongoing ? "这段还在进行中，删除后首页回到「无进行中」。" : "删除后无法恢复。")
        }
        .alert("确认毫升数", isPresented: largeBinding) {
            Button("返回修改", role: .cancel) { pendingLarge = nil }
            Button("确认") {
                largeConfirmed = true
                pendingLarge = nil
                save()
            }
        } message: {
            Text("一次喝了 \(pendingLarge ?? 0)ml 以上？")
        }
    }

    // MARK: 子控件

    private func methodLabel(_ m: FeedMethod) -> String { m == .formula ? "奶粉" : "母乳" }

    private var largeBinding: Binding<Bool> {
        Binding(get: { pendingLarge != nil }, set: { if !$0 { pendingLarge = nil } })
    }

    private var volumeRow: some View {
        TextField("毫升", text: $volumeText)
            .keyboardType(.numberPad)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Warm.text1)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Warm.sunken)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: volumeText) { newValue in
                let filtered = String(newValue.filter(\.isNumber).prefix(4))
                if filtered != newValue { volumeText = filtered }
            }
    }

    private var sideRow: some View {
        HStack(spacing: 8) {
            ForEach(BreastSide.allCases, id: \.self) { s in
                Button { side = (side == s ? nil : s) } label: {
                    Text(s.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(side == s ? .white : Warm.primaryStrong)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(side == s ? Warm.primaryStrong : Warm.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 排便类别：与左右侧同样可再点一次取消（回到"未区分"，显示为"排便"）。
    private var diaperRow: some View {
        HStack(spacing: 8) {
            ForEach(DiaperKind.allCases, id: \.self) { k in
                Button { diaper = (diaper == k ? nil : k) } label: {
                    Text(k.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(diaper == k ? .white : Warm.primaryStrong)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(diaper == k ? Warm.primaryStrong : Warm.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dateRow(_ title: String, _ value: Binding<Date>) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Warm.text2)
            Spacer()
            DatePicker(title, selection: value, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
        }
    }

    private func segmented<T: Hashable>(_ rows: [(T, String)], selection: Binding<T>) -> some View {
        Picker("", selection: selection) {
            ForEach(rows, id: \.1) { pair in
                Text(pair.1).tag(pair.0)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).fontWeight(.bold).foregroundStyle(Warm.text2)
            content()
        }
    }

    private func primaryButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Warm.primaryStrong)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func plainButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(Warm.text2)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: 保存

    private func save() {
        error = nil
        var e = original
        e.type = type
        e.startAt = start
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        e.note = trimmed.isEmpty ? nil : trimmed

        // 非吃奶事件不保留吃奶形态；形态决定毫升与左右侧谁有效
        e.feedMethod = type == .feed ? method : nil
        e.volumeMl = nil
        e.breastSide = (type == .feed && method == .breast) ? side : nil
        // 类别只属于排便：改成别的类型就清掉，否则一条"吃药"会带着"小便"的标题
        e.diaperKind = type == .poop ? diaper : nil

        if !type.isInterval {
            e.endAt = nil
            e.ongoing = false
        } else if isFormula {
            guard let ml = Int(volumeText), ml > 0 else {
                error = StoreErrorText.text(for: .invalidVolume); return
            }
            if ml > 500 && !largeConfirmed { pendingLarge = ml; return }
            e.volumeMl = ml
            e.endAt = start
            e.ongoing = false
        } else if original.ongoing {
            e.endAt = nil
            e.ongoing = true
        } else {
            guard end >= start else {
                error = StoreErrorText.text(for: .invalidInterval); return
            }
            e.endAt = end
            e.ongoing = false
        }

        recorder.update(e)
        dismiss()
    }
}

// MARK: - 统计
struct StatsView: View {
    @EnvironmentObject var recorder: Recorder
    @State private var range: StatsRange = .today

    enum StatsRange: String, CaseIterable { case today = "今日", week = "近 7 天" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $range) {
                        ForEach(StatsRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        StatCard(title: "🍼 吃奶", value: feedText,
                                 sub: "母乳 \(humanDuration(feedSeconds)) · 奶粉 \(formulaMl)ml")
                        StatCard(title: "😴 睡觉", value: sleepText, sub: "\(sleepSegments) 段")
                        StatCard(title: "💊 吃药", value: "\(count(.medicine)) 次", sub: "瞬时记录")
                        StatCard(title: "🧷 排便", value: "\(count(.poop)) 次", sub: "瞬时记录")
                    }

                    // §3.4.2 近 7 天趋势（P1）：始终展示最近 7 天，与上方今日/近7天数字汇总切换无关
                    TrendCard()
                }
                .padding(16)
            }
            .background(Warm.bg.ignoresSafeArea())
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // 统计区间内事件
    private var window: (Date, Date) {
        let cal = Calendar.current
        switch range {
        case .today: return (cal.startOfDay(for: recorder.now), recorder.now)
        case .week:  return (cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: recorder.now))!, recorder.now)
        }
    }
    private func inWindow(_ e: BabyEvent) -> Bool {
        let (s, en) = window
        return e.startAt >= s && e.startAt <= en
    }
    private func count(_ t: EventType) -> Int {
        recorder.events.filter { $0.type == t && inWindow($0) }.count
    }
    private var feedSeconds: TimeInterval {
        recorder.events.filter { $0.type == .feed && inWindow($0) }
            .reduce(0) { $0 + $1.duration(now: recorder.now) }
    }
    private var feedText: String { "\(count(.feed)) 次" }
    /// 奶量口径（§3.4.2 / AC-8）：毫升只累计 FORMULA 零时长段，母乳有时长无毫升、不计入。
    private var formulaMl: Int {
        recorder.events.filter { $0.isFormula && inWindow($0) }
            .reduce(0) { $0 + ($1.volumeMl ?? 0) }
    }
    private var sleepEvents: [BabyEvent] {
        recorder.events.filter { $0.type == .sleep && inWindow($0) }
    }
    private var sleepSegments: Int { sleepEvents.count }
    private var sleepText: String {
        let total = sleepEvents.reduce(0.0) { $0 + $1.duration(now: recorder.now) }
        return humanDuration(total)
    }
}

struct StatCard: View {
    let title: String; let value: String; let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Warm.text1).monospacedDigit()
            Text(title).font(.caption).fontWeight(.semibold).foregroundStyle(Warm.text2)
            Text(sub).font(.caption2).foregroundStyle(Warm.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Warm.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0xC78D63).opacity(0.10), radius: 8, y: 4)
    }
}

// MARK: - §3.4.2 近 7 天趋势（P1）

/// 趋势图可切换指标（§3.4.2 表）。奶量仅统计 FORMULA，母乳不计入（口径约束见 §3.4.2）。
private enum TrendMetric: String, CaseIterable, Identifiable {
    case formulaMl = "奶量"
    case feedCount = "喂奶"
    case sleepMinutes = "睡眠时长"
    case sleepSegments = "睡眠段数"
    case poopCount = "排便"
    case medicineCount = "吃药"
    var id: String { rawValue }

    func value(_ b: DayBucket) -> Double {
        switch self {
        case .formulaMl: return Double(b.formulaMl)
        case .feedCount: return Double(b.feedCount)
        case .sleepMinutes: return b.sleepMinutes
        case .sleepSegments: return Double(b.sleepSegments)
        case .poopCount: return Double(b.poopCount)
        case .medicineCount: return Double(b.medicineCount)
        }
    }
    var unit: String {
        switch self {
        case .formulaMl: return "ml"
        case .feedCount: return "次"
        case .sleepMinutes: return "分钟"
        case .sleepSegments: return "段"
        case .poopCount: return "次"
        case .medicineCount: return "次"
        }
    }
}

/// 单日聚合桶。id 用 dayStart 保证跨次渲染身份稳定（图表值变化可动画）。
private struct DayBucket: Identifiable {
    let dayStart: Date
    var id: Date { dayStart }
    let label: String
    var formulaMl: Int = 0
    var breastCount: Int = 0
    var feedCount: Int = 0
    var sleepMinutes: Double = 0
    var sleepSegments: Int = 0
    var poopCount: Int = 0
    var medicineCount: Int = 0
}

/// 近 7 天趋势卡：按天聚合柱状图 + 指标切换 + 奶量口径标注。
struct TrendCard: View {
    @EnvironmentObject var recorder: Recorder
    @State private var metric: TrendMetric = .feedCount

    var body: some View {
        let buckets = buildBuckets()
        VStack(alignment: .leading, spacing: 12) {
            Text("近 7 天趋势")
                .font(.subheadline).fontWeight(.bold).foregroundStyle(Warm.text2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TrendMetric.allCases) { m in metricChip(m) }
                }
            }

            // 柱状图：无数据时各柱为零值（§3.4 异常表"零值占位"）
            Chart {
                ForEach(buckets) { b in
                    BarMark(
                        x: .value("日期", b.label),
                        y: .value(metric.rawValue, metric.value(b))
                    )
                    .foregroundStyle(Warm.primary)
                    .cornerRadius(4)
                }
            }
            .frame(height: 160)

            caption(for: buckets)
        }
        .padding(16)
        .background(Warm.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0xC78D63).opacity(0.10), radius: 8, y: 4)
    }

    private func metricChip(_ m: TrendMetric) -> some View {
        Button { metric = m } label: {
            Text(m.rawValue)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(metric == m ? Color.white : Warm.primaryStrong)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(metric == m ? Warm.primaryStrong : Warm.primarySoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 口径标注：奶量仅奶粉、显式标注未计入母乳次数（§3.4.2 约束，禁止"总摄入量/达标"等表述）；其余显示单位；全零显示"暂无数据"。
    @ViewBuilder
    private func caption(for buckets: [DayBucket]) -> some View {
        let total = buckets.reduce(0.0) { $0 + metric.value($1) }
        if total == 0 {
            Text("暂无数据").font(.caption2).foregroundStyle(Warm.text3)
        } else if metric == .formulaMl {
            let ml = buckets.reduce(0) { $0 + $1.formulaMl }
            let breast = buckets.reduce(0) { $0 + $1.breastCount }
            Text("奶粉量合计 \(ml)ml · 母乳 \(breast) 次未计入")
                .font(.caption2).foregroundStyle(Warm.text3)
        } else {
            Text("单位：\(metric.unit)").font(.caption2).foregroundStyle(Warm.text3)
        }
    }

    /// 构建最近 7 天（含今天）的聚合桶。睡眠时长按 splitByDay 跨天归属（AC-12）；其余按 startAt 所属自然日。
    private func buildBuckets() -> [DayBucket] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: recorder.now)
        var buckets: [DayBucket] = (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            return DayBucket(dayStart: d, label: dayLabel(d))
        }
        var idx: [Date: Int] = [:]
        for (i, b) in buckets.enumerated() { idx[b.dayStart] = i }

        for e in recorder.events {
            let startDay = cal.startOfDay(for: e.startAt)
            if e.isFormula {
                if let i = idx[startDay] { buckets[i].formulaMl += e.volumeMl ?? 0; buckets[i].feedCount += 1 }
            } else if e.type == .feed {
                if let i = idx[startDay] { buckets[i].breastCount += 1; buckets[i].feedCount += 1 }
            } else if e.type == .sleep {
                let end = e.endAt ?? recorder.now
                for piece in EventStateMachine.splitByDay(start: e.startAt, end: end) {
                    if let i = idx[piece.day] { buckets[i].sleepMinutes += piece.seconds / 60 }
                }
                if let i = idx[startDay] { buckets[i].sleepSegments += 1 }
            } else if e.type == .poop {
                if let i = idx[startDay] { buckets[i].poopCount += 1 }
            } else if e.type == .medicine {
                if let i = idx[startDay] { buckets[i].medicineCount += 1 }
            }
        }
        return buckets
    }

    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: d)
    }
}

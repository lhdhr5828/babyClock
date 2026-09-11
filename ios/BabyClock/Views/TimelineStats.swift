import SwiftUI

// MARK: - 时间轴
struct TimelineView: View {
    @EnvironmentObject var recorder: Recorder
    @State private var day: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayHeader(day: $day)
                let list = recorder.events(on: day)
                if list.isEmpty {
                    Spacer()
                    Text("这一天还没有记录").foregroundStyle(Warm.text3)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(list) { e in TimelineRow(event: e, now: recorder.now) }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Warm.bg.ignoresSafeArea())
            .navigationTitle("时间轴")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DayHeader: View {
    @Binding var day: Date
    var body: some View {
        HStack {
            Button { shift(-1) } label: navIcon("chevron.left")
            VStack(spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Warm.text1)
                Text(dateStr).font(.caption).foregroundStyle(Warm.text2)
            }
            .frame(maxWidth: .infinity)
            Button { shift(1) } label: navIcon("chevron.right")
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

struct TimelineRow: View {
    let event: BabyEvent
    var now: Date = Date()
    var body: some View {
        HStack(spacing: 12) {
            SquircleIcon(type: event.type, size: 40) { EventGlyph(type: event.type, size: 20) }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.ongoing ? "\(event.type.title) · 进行中" : event.type.title)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Warm.text1)
                Text(subtitle).font(.caption).foregroundStyle(Warm.text2)
            }
            Spacer()
            if event.type.isInterval {
                Text(event.ongoing
                     ? formatDuration(now.timeIntervalSince(event.startAt))
                     : humanDuration(event.duration()))
                    .font(.caption).fontWeight(.heavy)
                    .foregroundStyle(Warm.primaryStrong)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Warm.primarySoft, in: Capsule())
            } else {
                Text("瞬时").font(.caption).foregroundStyle(Warm.text3)
            }
        }
        .padding(12)
        .background(Warm.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0xC78D63).opacity(0.10), radius: 8, y: 4)
    }
    private var subtitle: String {
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
                        StatCard(title: "🍼 吃奶", value: feedText, sub: "共 \(humanDuration(feedSeconds))")
                        StatCard(title: "😴 睡觉", value: sleepText, sub: "\(sleepSegments) 段")
                        StatCard(title: "💊 吃药", value: "\(count(.medicine)) 次", sub: "瞬时记录")
                        StatCard(title: "🧷 排便", value: "\(count(.poop)) 次", sub: "瞬时记录")
                    }
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

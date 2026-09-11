import SwiftUI

struct HomeView: View {
    @EnvironmentObject var recorder: Recorder

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatusCard(recorder: recorder)
                    Text("轻点记录")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(Warm.text2)
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                        ForEach(EventType.allCases, id: \.self) { type in
                            RecordButton(type: type, recorder: recorder)
                        }
                    }
                    TodayPreview(recorder: recorder)
                }
                .padding(20)
            }
            .background(Warm.bg.ignoresSafeArea())
            .navigationTitle("小宝")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 当前状态卡：进行中事件 + 实时走秒 + 四类距上次
struct StatusCard: View {
    @ObservedObject var recorder: Recorder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let o = recorder.ongoing {
                HStack(spacing: 8) {
                    Circle().fill(.white).frame(width: 9, height: 9)
                        .opacity(0.9)
                    Text("正在进行 · \(o.type.title)")
                        .font(.footnote).fontWeight(.semibold)
                }
                .foregroundStyle(.white.opacity(0.92))
                Text(formatDuration(recorder.now.timeIntervalSince(o.startAt)))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("开始于 \(formatClock(o.startAt)) · 再次点击「\(o.type.title)」可结束")
                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
            } else {
                Text("当前无进行中的活动")
                    .font(.headline).foregroundStyle(.white)
                Text("点下方按钮开始记录")
                    .font(.footnote).foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 8) {
                ForEach(EventType.allCases, id: \.self) { t in
                    if let last = recorder.lastOccurrence(of: t) {
                        chip("\(emoji(t)) \(relativeTimeString(last, now: recorder.now))")
                    }
                }
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
    private func emoji(_ t: EventType) -> String {
        switch t { case .feed: "🍼"; case .sleep: "😴"; case .medicine: "💊"; case .poop: "🧷" }
    }
}

struct RecordButton: View {
    let type: EventType
    @EnvironmentObject var recorder: Recorder
    @State private var tapped = false

    var body: some View {
        Button {
            recorder.submit(type, source: .app)
            tapped = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { tapped = false }
        } label: {
            VStack(spacing: 10) {
                SquircleIcon(type: type) { EventGlyph(type: type, size: 30) }
                Text(type.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Warm.text1)
                Text(type.isInterval ? (recorder.ongoing?.type == type ? "进行中" : "时间段") : "瞬时")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Warm.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Warm.elevated)
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

/// 事件图标（iOS squircle 风格矢量图形）
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

#Preview {
    HomeView().environmentObject(Recorder(store: InMemoryEventStore()))
}

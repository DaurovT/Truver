import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TruverWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MetronomeLiveActivity()
        MetronomeWidget()
        PresetsWidget()
        if #available(iOS 18.0, *) {
            MetronomeControl()
            TunerControl()
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
    static let ink = Color(hex: 0xf6f3ec)
    static let sub = Color(hex: 0xa29f97)
    static let beat = Color(hex: 0xf3efe6)
    static let inTune = Color(hex: 0x46e08f)
    static let sharp = Color(hex: 0xff9b52)
}

func inter(_ size: CGFloat, _ weight: String = "Regular") -> Font { .custom("Inter-\(weight)", fixedSize: size) }

/// The small mark of the island (canvas: ring 8, ten arc segments, needle) in one colour.
struct SmallMark: View {
    var color: Color = .ink

    var body: some View {
        Canvas { context, size in
            let k = min(size.width, size.height) / 100
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - 43 * k, y: c.y - 43 * k, width: 86 * k, height: 86 * k)), with: .color(color), lineWidth: 8 * k)
            for i in 0..<10 {
                var p = Path()
                let start = -54.3 + Double(i) * 36
                p.addArc(center: c, radius: 25 * k, startAngle: .degrees(start), endAngle: .degrees(start + 18.6), clockwise: false)
                context.stroke(p, with: .color(color), lineWidth: 9 * k)
            }
            var t = Path()
            t.move(to: CGPoint(x: c.x, y: c.y + (18 - 50) * k))
            t.addLine(to: CGPoint(x: c.x - 9 * k, y: c.y + (2 - 50) * k))
            t.addLine(to: CGPoint(x: c.x + 9 * k, y: c.y + (2 - 50) * k))
            t.closeSubpath()
            context.fill(t, with: .color(color))
            context.fill(Path(roundedRect: CGRect(x: c.x - 4.5 * k, y: c.y + (14 - 50) * k, width: 9 * k, height: 20 * k), cornerRadius: 4.5 * k), with: .color(color))
        }
        .frame(width: 20, height: 20)
    }
}

/// Beat bars: 22 × 14 strong, 22 × 9 normal; the first strong lit; no blinking.
struct ActivityBeats: View {
    let groups: [Int]
    let accents: [Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(groupRanges.enumerated()), id: \.offset) { _, range in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(range, id: \.self) { beat in
                        let level = accents.indices.contains(beat) ? accents[beat] : 2
                        RoundedRectangle(cornerRadius: 2)
                            .fill(beat == 0 ? Color.beat : Color.white.opacity(0.22))
                            .frame(width: 22, height: level >= 3 ? 14 : (level == 2 ? 9 : 5))
                    }
                }
            }
        }
    }

    private var groupRanges: [Range<Int>] {
        var start = 0
        return groups.map { size in defer { start += size }; return start..<(start + size) }
    }
}

/// Expanded island and lock screen share one layout (canvas «единая раскладка»).
struct ActivityPanel: View {
    let state: MetronomeActivityAttributes.ContentState
    var lockScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    SmallMark(color: state.targetReached ? .inTune : .ink)
                    Text(title).font(inter(13)).foregroundStyle(state.targetReached ? Color.inTune : Color.sub)
                }
                Spacer()
                if state.interrupted {
                    Text("прервано").font(inter(13)).foregroundStyle(Color.sharp)
                } else if !state.isPlaying {
                    Text("остановлен").font(inter(13)).foregroundStyle(Color.sub)
                } else if let end = state.timerEnd {
                    HStack(spacing: 4) {
                        Image(systemName: "timer").font(.system(size: 11))
                        Text(timerInterval: Date()...max(Date(), end), countsDown: true).font(inter(13)).monospacedDigit()
                    }
                    .foregroundStyle(Color.sub)
                    .frame(maxWidth: 70, alignment: .trailing)
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.bpm)").font(inter(34, "Light")).foregroundStyle(.white).monospacedDigit()
                    Text(state.interrupted ? "Остановлен из-за звонка" : state.detail).font(inter(12)).foregroundStyle(Color.sub)
                }
                Spacer()
                if !state.interrupted { ActivityBeats(groups: state.groups, accents: state.accents) }
            }
            button
        }
        .padding(lockScreen ? 16 : 4)
    }

    private var title: String {
        if state.targetReached { return "Цель достигнута" }
        let name = state.preset ?? "Метроном"
        return lockScreen ? "Truver · \(name)" : name
    }

    @ViewBuilder private var button: some View {
        if state.interrupted {
            Button(intent: MetronomeResumeIntent()) { label(icon: "play.fill", text: state.resumeTitle) }.buttonStyle(.plain)
        } else if state.isPlaying {
            Button(intent: MetronomeStopIntent()) { label(icon: "stop.fill", text: "Стоп") }.buttonStyle(.plain)
        } else {
            Button(intent: MetronomeStartIntent()) { label(icon: "play.fill", text: "Старт") }.buttonStyle(.plain)
        }
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(text).font(inter(15, "SemiBold"))
        }
        .foregroundStyle(Color(hex: 0x0a0b0d))
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Capsule().fill(Color.ink))
    }
}

struct MetronomeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MetronomeActivityAttributes.self) { context in
            ActivityPanel(state: context.state, lockScreen: true)
                .activityBackgroundTint(Color(hex: 0x141518, opacity: 0.92))
                .activitySystemActionForegroundColor(.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityPanel(state: context.state)
                }
            } compactLeading: {
                HStack(spacing: 7) {
                    SmallMark(color: context.state.targetReached ? .inTune : .ink)
                    if context.state.isPlaying {
                        Circle().fill(Color.beat).frame(width: 7, height: 7)
                    }
                }
                .padding(.leading, 2)
            } compactTrailing: {
                HStack(spacing: 3) {
                    if context.state.rising { Text("↑").font(inter(13, "SemiBold")) }
                    Text("\(context.state.bpm)").font(inter(15, "SemiBold")).monospacedDigit()
                }
                .foregroundStyle(.white)
            } minimal: {
                SmallMark(color: context.state.targetReached ? .inTune : .ink)
            }
            .keylineTint(.ink)
        }
    }
}

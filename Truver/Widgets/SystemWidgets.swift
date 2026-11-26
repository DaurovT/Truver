import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline from the App Group snapshot

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        var s = SharedSnapshot()
        s.bpm = 142
        s.preset = "Риф 7/8"
        s.meter = "7/8"
        s.presets = [SharedPreset(id: UUID(), name: "Риф 7/8", bpm: 142, meter: "7/8"),
                     SharedPreset(id: UUID(), name: "Разогрев", bpm: 90, meter: "4/4"),
                     SharedPreset(id: UUID(), name: "Соло", bpm: 160, meter: "4/4")]
        return SnapshotEntry(date: .now, snapshot: s)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapshotEntry(date: .now, snapshot: .load()))
    }

    /// The app reloads the timelines itself when something changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: .load())], policy: .never))
    }
}

// MARK: - Metronome widget (SYS-5): lock screen round and rectangular, home small

struct MetronomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.truver.widget.metronome", provider: SnapshotProvider()) { entry in
            MetronomeWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color(hex: 0x0c0d0f) }
        }
        .configurationDisplayName("Метроном")
        .description("Последний темп и пресет. Нажатие — старт и стоп без открытия приложения.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct MetronomeWidgetView: View {
    let snapshot: SharedSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Button(intent: ToggleMetronomeIntent()) {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: snapshot.isPlaying ? "stop.fill" : "metronome")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(snapshot.bpm)").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .buttonStyle(.plain)
            .widgetAccentable()
            .accessibilityLabel(snapshot.isPlaying ? "Остановить метроном, \(snapshot.bpm)" : "Запустить метроном, \(snapshot.bpm)")
        case .accessoryRectangular:
            Button(intent: ToggleMetronomeIntent()) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.preset ?? "Метроном").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text("\(snapshot.bpm) BPM · \(snapshot.meter)").font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                        if let mode = snapshot.mode { Text(mode).font(.system(size: 11)).lineLimit(1).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: snapshot.isPlaying ? "stop.fill" : "play.fill").font(.system(size: 16, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SmallMark(color: .sub)
                    Spacer()
                    Text(snapshot.meter).font(inter(13, "Medium")).foregroundStyle(Color.sub)
                }
                Spacer(minLength: 0)
                Text("\(snapshot.bpm)").font(inter(44, "SemiBold")).foregroundStyle(Color.ink).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(snapshot.preset ?? snapshot.mode ?? "BPM").font(inter(12)).foregroundStyle(Color.sub).lineLimit(1)
                Spacer(minLength: 6)
                Button(intent: ToggleMetronomeIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: snapshot.isPlaying ? "stop.fill" : "play.fill").font(.system(size: 12, weight: .bold))
                        Text(snapshot.isPlaying ? "Стоп" : "Старт").font(inter(14, "SemiBold"))
                    }
                    .foregroundStyle(Color(hex: 0x0c0d0f))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Presets widget (SYS-5): home medium — a tap starts the preset

struct PresetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.truver.widget.presets", provider: SnapshotProvider()) { entry in
            PresetsWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color(hex: 0x0c0d0f) }
        }
        .configurationDisplayName("Пресеты")
        .description("Пресеты метронома: нажатие запускает пресет.")
        .supportedFamilies([.systemMedium])
    }
}

struct PresetsWidgetView: View {
    let snapshot: SharedSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SmallMark(color: .sub)
                Spacer(minLength: 0)
                Text("\(snapshot.bpm)").font(inter(34, "SemiBold")).foregroundStyle(Color.ink).monospacedDigit()
                Text(snapshot.isPlaying ? "играет · \(snapshot.meter)" : "BPM · \(snapshot.meter)").font(inter(11)).foregroundStyle(Color.sub)
                Button(intent: ToggleMetronomeIntent()) {
                    Image(systemName: snapshot.isPlaying ? "stop.fill" : "play.fill").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0c0d0f))
                        .frame(width: 36, height: 36).background(Circle().fill(Color.ink))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityLabel(snapshot.isPlaying ? "Стоп" : "Старт")
            }
            .frame(width: 88, alignment: .leading)
            VStack(spacing: 6) {
                if snapshot.presets.isEmpty {
                    Text("Сохраните пресет в метрономе — он появится здесь").font(inter(12)).foregroundStyle(Color.sub)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    ForEach(snapshot.presets.prefix(3), id: \.id) { p in
                        Button(intent: StartPresetIntent(preset: PresetEntity(p))) {
                            HStack {
                                Text(p.name).font(inter(14, "Medium")).foregroundStyle(Color.ink).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(p.bpm)").font(inter(14, "SemiBold")).foregroundStyle(Color.sub).monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(p.name == snapshot.preset ? 0.14 : 0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Control Center (SYS-1; iOS 18): metronome toggle and «Тюнер»

@available(iOS 18.0, *)
struct MetronomeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.truver.control.metronome", provider: MetronomeControlProvider()) { value in
            ControlWidgetToggle(isOn: value.isPlaying, action: SetMetronomeIntent()) {
                Label(value.isPlaying ? "\(value.bpm) BPM" : "Метроном", systemImage: "metronome")
            } valueLabel: { isOn in
                Text(isOn ? "Играет · \(value.bpm)" : "\(value.bpm) BPM")
            }
        }
        .displayName("Метроном")
        .description("Старт и стоп последних настроек метронома.")
    }
}

@available(iOS 18.0, *)
struct MetronomeControlProvider: ControlValueProvider {
    struct Value: Sendable { var isPlaying: Bool; var bpm: Int }
    var previewValue: Value { Value(isPlaying: false, bpm: 120) }
    func currentValue() async throws -> Value {
        let s = SharedSnapshot.load()
        return Value(isPlaying: s.isPlaying, bpm: s.bpm)
    }
}

@available(iOS 18.0, *)
struct TunerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.truver.control.tuner") {
            ControlWidgetButton(action: OpenTunerIntent()) {
                Label("Тюнер", systemImage: "tuningfork")
            }
        }
        .displayName("Тюнер")
        .description("Открывает Truver сразу на тюнере.")
    }
}

// Shared by the app and the widget extension: Siri and Shortcuts (SYS-4), the Action button (SYS-2),
// Control Center (SYS-1) and widgets (SYS-5). The app publishes a snapshot to the App Group; widgets, controls and
// entity queries read it. Actions run in the app's process (AudioPlaybackIntent / openAppWhenRun) through the bridge.
#if os(iOS)
import AppIntents
import Foundation

// MARK: - Snapshot in the App Group

struct SharedPreset: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var bpm: Int
    var meter: String
}

struct SharedTuning: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
}

struct SharedSnapshot: Codable, Hashable, Sendable {
    var isPlaying = false
    var bpm = 100
    /// «Риф 7/8» or nil.
    var preset: String?
    var meter = "4/4"
    /// «Разгон 120 → 160», «Пропадающие такты» or nil.
    var mode: String?
    var presets: [SharedPreset] = []
    var tunings: [SharedTuning] = []
    var tuning: String?

    static let groupId = "group.app.truver.ios"
    private static let key = "truver.snapshot.v1"

    static func load() -> SharedSnapshot {
        guard let data = UserDefaults(suiteName: groupId)?.data(forKey: key),
              let value = try? JSONDecoder().decode(SharedSnapshot.self, from: data) else { return SharedSnapshot() }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.groupId)?.set(data, forKey: Self.key)
    }
}

// MARK: - Bridge to the app

enum IntentAction: Sendable, Equatable {
    case start(bpm: Int?, numerator: Int?, denominator: Int?)
    case stop
    case toggle
    case preset(UUID)
    case tuning(UUID)
    case openTuner
    case openMetronome
}

@MainActor
enum IntentBridge {
    /// Set by the app at launch; actions that arrive earlier wait in `pending`.
    static var handler: ((IntentAction) -> Void)? {
        didSet {
            guard let handler else { return }
            let queued = pending
            pending = []
            queued.forEach(handler)
        }
    }
    static var pending: [IntentAction] = []

    static func send(_ action: IntentAction) {
        if let handler { handler(action) } else { pending.append(action) }
    }
}

// MARK: - Parameters

enum MeterOption: String, AppEnum {
    case m24 = "2/4", m34 = "3/4", m44 = "4/4", m54 = "5/4", m68 = "6/8", m78 = "7/8", m98 = "9/8", m128 = "12/8", m1116 = "11/16"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Размер"
    static let caseDisplayRepresentations: [MeterOption: DisplayRepresentation] = [
        .m24: "2/4", .m34: "3/4", .m44: "4/4", .m54: "5/4", .m68: "6/8", .m78: "7/8", .m98: "9/8", .m128: "12/8", .m1116: "11/16",
    ]

    var parts: (Int, Int) {
        let p = rawValue.split(separator: "/").compactMap { Int($0) }
        return (p[0], p[1])
    }
}

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Пресет метронома"
    static let defaultQuery = PresetQuery()
    var id: UUID
    var name: String
    var detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ p: SharedPreset) {
        id = p.id
        name = p.name
        detail = "\(p.bpm) BPM · \(p.meter)"
    }
}

struct PresetQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        SharedSnapshot.load().presets.filter { identifiers.contains($0.id) }.map(PresetEntity.init)
    }

    func entities(matching string: String) async throws -> [PresetEntity] {
        let q = string.lowercased()
        return SharedSnapshot.load().presets.filter { $0.name.lowercased().contains(q) }.map(PresetEntity.init)
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        SharedSnapshot.load().presets.map(PresetEntity.init)
    }
}

// MARK: - Metronome

/// «Запусти метроном», «Метроном 7/8 на 140»: without parameters — the current settings (last preset).
struct StartMetronomeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Запустить метроном"
    static let description = IntentDescription("Метроном с текущими настройками или с заданным темпом и размером.")

    @Parameter(title: "Темп", inclusiveRange: (20, 400)) var tempo: Int?
    @Parameter(title: "Размер") var meter: MeterOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Метроном \(\.$meter) на \(\.$tempo)")
    }

    init() {}
    init(tempo: Int?, meter: MeterOption? = nil) {
        self.tempo = tempo
        self.meter = meter
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentBridge.send(.start(bpm: tempo, numerator: meter?.parts.0, denominator: meter?.parts.1))
        let s = SharedSnapshot.load()
        return .result(dialog: "Метроном \(meter?.rawValue ?? s.meter), \(tempo ?? s.bpm)")
    }
}

struct StopMetronomeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Остановить метроном"
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        IntentBridge.send(.stop)
        return .result()
    }
}

/// Action button and widgets: one press — start the last settings or stop.
struct ToggleMetronomeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Метроном старт/стоп"
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        IntentBridge.send(.toggle)
        return .result()
    }
}

/// Control Center toggle (SYS-1): the system passes the new state.
struct SetMetronomeIntent: SetValueIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Метроном"
    @Parameter(title: "Играет") var value: Bool
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        IntentBridge.send(value ? .start(bpm: nil, numerator: nil, denominator: nil) : .stop)
        return .result()
    }
}

/// «Запусти пресет Риф».
struct StartPresetIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Запустить пресет"
    @Parameter(title: "Пресет") var preset: PresetEntity

    static var parameterSummary: some ParameterSummary { Summary("Запустить \(\.$preset)") }

    init() {}
    init(preset: PresetEntity) { self.preset = preset }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentBridge.send(.preset(preset.id))
        return .result(dialog: "\(preset.name)")
    }
}

// MARK: - Tuner

/// «Открой тюнер» — Control Center button and the Action button (SYS-1, SYS-2).
struct OpenTunerIntent: AppIntent {
    static let title: LocalizedStringResource = "Открыть тюнер"
    static let openAppWhenRun = true
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        IntentBridge.send(.openTuner)
        return .result()
    }
}

struct OpenMetronomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Открыть метроном"
    static let openAppWhenRun = true
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        IntentBridge.send(.openMetronome)
        return .result()
    }
}
#endif

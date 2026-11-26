#if os(iOS)
import AppIntents
import Foundation
import TruverDSP
import TruverTheory
import WidgetKit

// MARK: - Tunings for Siri (app only: switching runs in the app process)

struct TuningEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Строй"
    static let defaultQuery = TuningQuery()
    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct TuningQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [TuningEntity] {
        SharedSnapshot.load().tunings.filter { identifiers.contains($0.id) }.map { TuningEntity(id: $0.id, name: $0.name) }
    }

    /// «Drop E», «дроп е», «стандарт»: letters only, case and spaces ignored.
    func entities(matching string: String) async throws -> [TuningEntity] {
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "дроп", with: "drop").replacingOccurrences(of: "стандарт", with: "standard")
                .filter { $0.isLetter || $0.isNumber }
        }
        let q = norm(string)
        return SharedSnapshot.load().tunings.filter { norm($0.name).contains(q) || q.contains(norm($0.name)) }
            .map { TuningEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [TuningEntity] {
        SharedSnapshot.load().tunings.map { TuningEntity(id: $0.id, name: $0.name) }
    }
}

/// «Включи строй Drop E».
struct SwitchTuningIntent: AppIntent {
    static let title: LocalizedStringResource = "Включить строй"
    @Parameter(title: "Строй") var tuning: TuningEntity

    static var parameterSummary: some ParameterSummary { Summary("Включить строй \(\.$tuning)") }

    init() {}

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentBridge.send(.tuning(tuning.id))
        return .result(dialog: "Строй \(tuning.name)")
    }
}

/// Siri phrases (SYS-4). Tempo and meter are asked by Siri or set in Shortcuts (phrases take only entities).
struct TruverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartMetronomeIntent(), phrases: [
            "Запусти метроном в \(.applicationName)",
            "Включи метроном \(.applicationName)",
            "Метроном \(.applicationName)",
        ], shortTitle: "Метроном", systemImageName: "metronome")
        AppShortcut(intent: StopMetronomeIntent(), phrases: [
            "Останови метроном в \(.applicationName)",
            "Выключи метроном \(.applicationName)",
        ], shortTitle: "Стоп", systemImageName: "stop.fill")
        AppShortcut(intent: StartPresetIntent(), phrases: [
            "Запусти пресет \(\.$preset) в \(.applicationName)",
            "Пресет \(\.$preset) \(.applicationName)",
        ], shortTitle: "Пресет", systemImageName: "list.bullet")
        AppShortcut(intent: OpenTunerIntent(), phrases: [
            "Открой тюнер \(.applicationName)",
            "Тюнер \(.applicationName)",
        ], shortTitle: "Тюнер", systemImageName: "tuningfork")
        AppShortcut(intent: SwitchTuningIntent(), phrases: [
            "Включи строй \(\.$tuning) в \(.applicationName)",
            "Строй \(\.$tuning) \(.applicationName)",
        ], shortTitle: "Строй", systemImageName: "guitars")
    }
}

// MARK: - The app side

/// Publishes the snapshot for widgets and controls and carries out intent actions.
@MainActor
final class SystemIntegration {
    private weak var app: AppModel?
    private var last: SharedSnapshot?

    init(app: AppModel) {
        self.app = app
        IntentBridge.handler = { [weak self] action in self?.perform(action) }
    }

    func perform(_ action: IntentAction) {
        guard let app else { return }
        let metronome = app.metronome
        switch action {
        case let .start(bpm, numerator, denominator):
            var meter = metronome.meter
            if let numerator, let denominator, numerator != meter.numerator || denominator != meter.denominator {
                meter.numerator = numerator
                meter.denominator = denominator
                meter.accents = MeterSettings(numerator: numerator, denominator: denominator).accents
                meter.grouping = nil
                meter.beatRhythms = nil
            }
            if let bpm { meter.bpm = Double(bpm).clamped(to: MetronomeController.bpmRange) }
            if meter != metronome.meter {
                metronome.meter = meter
                if bpm != nil { var s = metronome.state; s.modes.tempo = .none; metronome.state = s }
            }
            if !metronome.isPlaying { metronome.start() }
        case .stop:
            metronome.stop()
        case .toggle:
            metronome.toggle()
        case .preset(let id):
            if let preset = metronome.state.presets.first(where: { $0.id == id }) {
                metronome.load(preset)
                if !metronome.isPlaying { metronome.start() }
            }
        case .tuning(let id):
            app.selectTuning(id)
        case .openTuner:
            app.sheet = nil
            app.settings.lastTab = .tuner
        case .openMetronome:
            app.sheet = nil
            app.settings.lastTab = .metronome
        }
        publish()
    }

    /// Called when the metronome starts or stops and when settings change; reloads widgets only on a change.
    func publish() {
        guard let app else { return }
        let m = app.metronome
        let s = m.state
        var snap = SharedSnapshot()
        snap.isPlaying = m.isPlaying
        snap.bpm = Int(m.displayBPM.rounded())
        snap.preset = s.currentPreset?.name
        snap.meter = "\(s.meter.numerator)/\(s.meter.denominator)"
        snap.mode = s.modes.activeTitles.first
        snap.presets = s.presets.map { SharedPreset(id: $0.id, name: $0.name, bpm: Int($0.settings.bpm), meter: "\($0.settings.numerator)/\($0.settings.denominator)") }
        snap.tunings = app.instrument.tunings.map { SharedTuning(id: $0.id, name: $0.name) }
        snap.tuning = app.tuning.name
        guard snap != last else { return }
        let playingChanged = snap.isPlaying != last?.isPlaying
        last = snap
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
        if playingChanged, #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: "app.truver.control.metronome")
        }
    }
}
#else
/// Mac: no widgets or controls yet (MAC stage).
@MainActor
final class SystemIntegration {
    init(app: AppModel) {}
    func publish() {}
}
#endif

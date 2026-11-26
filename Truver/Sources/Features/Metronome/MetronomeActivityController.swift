#if os(iOS)
import ActivityKit
import Foundation
import TruverDSP

/// Live Activity of the metronome (6.2.9, SYS-6): started with the metronome, kept while the app lives (stopped —
/// «Старт» on the island), updated at most once a second (system limit), ended when the app launches anew.
@MainActor
final class MetronomeActivityController {
    private weak var app: AppModel?
    /// Id of our activity; the activity itself is looked up inside tasks (it is not Sendable).
    private var activityId: String?
    private var loop: Task<Void, Never>?
    private var last: MetronomeActivityAttributes.ContentState?

    init(app: AppModel) {
        self.app = app
        // A previous run may have left an activity behind.
        Task {
            for old in Activity<MetronomeActivityAttributes>.activities { await old.end(nil, dismissalPolicy: .immediate) }
        }
        MetronomeActivityBridge.handler = { [weak app] action in
            guard let metronome = app?.metronome else { return }
            switch action {
            case .stop: metronome.stop()
            case .start, .resume: metronome.start()
            }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        guard let app else { return }
        let metronome = app.metronome
        // Nothing to show until the metronome has been started once.
        guard activityId != nil || metronome.isPlaying else { return }
        let state = contentState(metronome)
        guard state != last else { return }
        last = state
        if let id = activityId {
            Task {
                for a in Activity<MetronomeActivityAttributes>.activities where a.id == id {
                    await a.update(ActivityContent(state: state, staleDate: nil))
                }
            }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activityId = (try? Activity.request(attributes: MetronomeActivityAttributes(), content: ActivityContent(state: state, staleDate: nil)))?.id
        }
    }

    private func contentState(_ m: MetronomeController) -> MetronomeActivityAttributes.ContentState {
        let s = m.state
        let modes = s.modes
        let bpm = Int(m.displayBPM.rounded())
        var detail = "BPM · \(s.meter.numerator)/\(s.meter.denominator)"
        var rising = false
        if m.targetReached && m.isPlaying {
            detail = "BPM · темп держится"
        } else if modes.tempo == .songMap && m.isPlaying {
            detail = "BPM · " + (modes.song[safe: m.songSection]?.name ?? "Карта песни")
        } else if modes.tempo == .fastSlow && m.isPlaying {
            detail = "BPM · \(Int(modes.start)) ↔ \(Int(modes.fast))"
        } else if modes.tempo != .none && m.isPlaying {
            let next = Int(min(modes.target, m.displayBPM + modes.step))
            detail = "BPM · \(modes.tempo == .speedUp ? "Разгон" : "Два вперёд") → \(next)"
            rising = true
        }
        let groups = (s.meter.grouping?.reduce(0, +) == s.meter.numerator ? s.meter.grouping : nil) ?? [s.meter.numerator]
        let accents = s.meter.accents.map { level -> Int in
            switch level {
            case .off: return 0
            case .soft: return 1
            case .normal: return 2
            case .strong: return 3
            }
        }
        return .init(bpm: bpm, isPlaying: m.isPlaying, preset: s.currentPreset?.name, detail: detail, rising: rising,
                     timerEnd: m.isPlaying ? m.timerEnd : nil, targetReached: m.targetReached && m.isPlaying,
                     interrupted: m.interrupted, resumeTitle: m.resumeTitle.replacingOccurrences(of: " BPM", with: ""),
                     groups: groups, accents: accents)
    }
}
#endif

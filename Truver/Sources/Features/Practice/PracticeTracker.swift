import Foundation
import Observation
import SwiftData

/// Simple v1 journal (PL-0). Time counts while the metronome plays or the tuner hears a note; pieces with a gap
/// under 5 minutes join into one session; background metronome time counts (6.1 п. 12).
@MainActor
@Observable
final class PracticeTracker {
    weak var app: AppModel?
    private let context: ModelContext
    private var current: PracticeEntry?
    private var lastActivity: Date?
    private var lastSave = Date.distantPast

    static let joinGap: TimeInterval = 5 * 60

    /// Screenshot demo of the play check's history (`-practiceDemo`: 14 days, ceiling 128 → 146, spread 8 ms;
    /// `-practiceEmpty`: none) — shown instead of the controller's.
    private(set) var demoHistory: [PlayAttempt]?

    init(context: ModelContext) {
        self.context = context
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-practiceDemo") || arguments.contains("-practiceEmpty") {
            try? context.delete(model: PracticeEntry.self)
            demoHistory = []
        }
        if arguments.contains("-practiceDemo") { seedDemo() }
        try? context.save()
    }

    /// The board «Занятия — графики»: 14 days in a row, 2 h 10 min over the last week, the ceiling 128 → 146.
    private func seedDemo() {
        let now = Date()
        let minutes = [20, 15, 25, 20, 15, 20, 15, 15, 20, 15, 20, 15, 20, 15]
        let ceilings: [Double] = [128, 129, 131, 132, 133, 135, 136, 137, 139, 140, 141, 143, 144, 146]
        var history: [PlayAttempt] = []
        for k in 0..<14 {
            let start = now.addingTimeInterval(-Double(k) * 86_400 - 3600)
            let entry = PracticeEntry(start: start, instrumentName: "8-струнная гитара", tuningName: "Стандарт F♯")
            entry.seconds = Double(minutes[k] * 60)
            entry.usedMetronome = true
            entry.presetName = "Риф 7/8"
            entry.lastBPM = ceilings[13 - k]
            entry.minBPM = ceilings[13 - k] - 8
            context.insert(entry)
            let i = 13 - k
            var a = PlayAttempt(date: start, preset: "Риф 7/8", seconds: Double(minutes[k] * 60), startBPM: 120,
                                endBPM: ceilings[i], ceiling: ceilings[i], accurateShare: 0.8, meanDeviation: -5,
                                spread: 14 - Double(i) * 6 / 13, weakestBeat: 3, weakestBeatDeviation: -12, bars: 40,
                                silenceDrift: nil)
            a.perBeat = [0: -2, 1: 4, 2: -6, 3: -13]
            history.append(a)
        }
        demoHistory = history.reversed()
    }

    func activity(tuned: Bool, bpm: Double? = nil) {
        guard let app else { return }
        let now = Date()
        if let last = lastActivity, let entry = current, now.timeIntervalSince(last) < Self.joinGap,
           entry.instrumentName == app.instrument.name {
            // Count at most 2 s per call so that sparse tuner readings do not inflate the time.
            entry.seconds += min(2, now.timeIntervalSince(last))
        } else {
            let entry = PracticeEntry(start: now, instrumentName: app.instrument.name, tuningName: app.tuning.name)
            context.insert(entry)
            current = entry
        }
        lastActivity = now
        if let bpm, let entry = current {
            entry.lastBPM = bpm
            entry.minBPM = entry.usedMetronome && entry.minBPM > 0 ? min(entry.minBPM, bpm) : bpm
            entry.usedMetronome = true
            if let preset = app.metronome.state.currentPreset?.name { entry.presetName = preset }
        }
        if tuned { current?.tuned = true }
        current?.tuningName = app.tuning.name
        if now.timeIntervalSince(lastSave) > 10 {
            try? context.save()
            lastSave = now
        }
    }

    func flush() { try? context.save() }
}

// Shared by the app and the widget extension: the metronome Live Activity (6.2.9, SYS-6) and its buttons.
#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

struct MetronomeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var bpm: Int
        var isPlaying: Bool
        /// «Риф 7/8»; nil — the meter is shown instead.
        var preset: String?
        /// Under the tempo: «BPM · Разгон → 146», «BPM · 7/8», «BPM · темп держится».
        var detail: String
        /// The tempo is rising by a mode (compact island: ↑).
        var rising: Bool
        var timerEnd: Date?
        var targetReached: Bool
        var interrupted: Bool
        /// «Продолжить · 142 · Разгон».
        var resumeTitle: String
        /// Beat bars: group sizes and accent levels 0 (off) … 3 (strong); no blinking (system limit).
        var groups: [Int]
        var accents: [Int]
    }
}

/// What a Live Activity button asks the app to do; the app registers the handler at launch.
enum MetronomeActivityAction: String, Sendable { case stop, start, resume }

@MainActor
enum MetronomeActivityBridge {
    static var handler: ((MetronomeActivityAction) -> Void)?
}

/// Buttons on the island and the lock screen: run in the app's process without opening it (LiveActivityIntent).
struct MetronomeStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Остановить метроном"
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        MetronomeActivityBridge.handler?(.stop)
        return .result()
    }
}

struct MetronomeStartIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Запустить метроном"
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        MetronomeActivityBridge.handler?(.start)
        return .result()
    }
}

struct MetronomeResumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Продолжить метроном"
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        MetronomeActivityBridge.handler?(.resume)
        return .result()
    }
}
#endif

import SwiftUI
import StoreKit

/// Hooks of the settings feature started by `AppModel`: the saved noise threshold and the rate prompt.
@MainActor
enum SettingsHooks {
    /// The tuner's noise threshold set on «Настройки → Порог шума» (the tuner itself keeps it only while running).
    static let noiseGateKey = "tuner.noiseGateDB"

    static func start(_ app: AppModel) {
        if let value = UserDefaults.standard.object(forKey: noiseGateKey) as? Double { app.tuner.noiseGate = value }
        RatePrompt.shared.observe(app)
        // Screenshot hook: `-ratePrompt` asks at once (with `-tunerDemo done` — the board «Оценка»).
        if ProcessInfo.processInfo.arguments.contains("-ratePrompt") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                RatePrompt.shared.request()
            }
        }
    }
}

/// Canvas «Оценка — системный запрос после удачной настройки (не чаще 3 раз в год)»: the system rating dialog (iOS
/// draws it; it also caps it at 3 a year and shows nothing in TestFlight). Our rule on top: after a successful tuning
/// (all strings in tune), from the 3rd such tuning on, not while the metronome plays, at most 3 requests in 365 days
/// and at least 60 days apart.
@MainActor
final class RatePrompt {
    static let shared = RatePrompt()

    private let defaults = UserDefaults.standard
    private let tuningsKey = "rate.successfulTunings"
    private let requestsKey = "rate.requests"
    private weak var app: AppModel?
    private var wasTuned = false

    func observe(_ app: AppModel) {
        self.app = app
        track()
    }

    private func track() {
        guard let app else { return }
        wasTuned = withObservationTracking { app.tuner.allTuned } onChange: {
            Task { @MainActor in RatePrompt.shared.changed() }
        }
    }

    private func changed() {
        guard let app else { return }
        let tuned = app.tuner.allTuned
        if tuned && !wasTuned { successfulTuning() }
        track()
    }

    private func successfulTuning() {
        let count = defaults.integer(forKey: tuningsKey) + 1
        defaults.set(count, forKey: tuningsKey)
        guard Self.shouldAsk(successfulTunings: count, requests: requests, now: .now), app?.metronome.isPlaying != true else { return }
        Task { @MainActor in
            // Let «Готово» show first.
            try? await Task.sleep(for: .seconds(1.5))
            request()
        }
    }

    private var requests: [Date] {
        (defaults.array(forKey: requestsKey) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
    }

    /// The rule, separately for tests.
    nonisolated static func shouldAsk(successfulTunings: Int, requests: [Date], now: Date) -> Bool {
        guard successfulTunings >= 3 else { return false }
        let year = now.addingTimeInterval(-365 * 86400)
        let recent = requests.filter { $0 > year }
        if recent.count >= 3 { return false }
        if let last = requests.max(), now.timeIntervalSince(last) < 60 * 86400 { return false }
        return true
    }

    func request(attempt: Int = 0) {
        #if os(iOS)
        // StoreKit ignores a scene that is not active yet (right after launch): wait for it.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            if attempt < 20 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    self.request(attempt: attempt + 1)
                }
            }
            return
        }
        defaults.set((requests + [.now]).suffix(6).map(\.timeIntervalSince1970), forKey: requestsKey)
        AppStore.requestReview(in: scene)
        #else
        defaults.set((requests + [.now]).suffix(6).map(\.timeIntervalSince1970), forKey: requestsKey)
        SKStoreReviewController.requestReview()
        #endif
    }
}

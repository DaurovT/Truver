import SwiftUI
import Observation

// MARK: - «Спасибо»: people and partners

/// A link of a person or partner: the platform and the handle shown under its name.
struct ThanksLink: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case youtube, instagram, tiktok, telegram, spotify, site }
    let kind: Kind
    let handle: String
    let url: String

    var id: String { url }

    /// Platform names (canvas «Ссылки на площадки — набор»).
    var platform: String {
        switch kind {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .telegram: return "Telegram"
        case .spotify: return "Spotify"
        case .site: return "Сайт"
        }
    }

    /// The second line of a link row: `@handle`, `t.me/handle` or the site's address (canvas «Музыкант»).
    var displayHandle: String {
        switch kind {
        case .telegram: return "t.me/\(handle)"
        case .site: return handle
        default: return handle.hasPrefix("@") ? handle : "@\(handle)"
        }
    }
}

/// A musician or a partner (school, shop, festival, channel) from `thanks.json`.
struct ThanksPerson: Codable, Hashable, Identifiable {
    /// Partner kinds — the badge on the square avatar (canvas «Спасибо — партнёры»).
    enum PartnerKind: String, Codable { case school, shop, festival, channel }

    let id: String
    let name: String
    let subtitle: String
    let thanks: String?
    let photo: String?
    let photoSmall: String?
    let links: [ThanksLink]
    var kind: PartnerKind?

    /// Initials for a person without a photo (canvas: «АВ», «MS»).
    var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "«" || $0 == "»" }).filter { $0.first?.isLetter == true }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}

private struct ThanksFile: Codable {
    var musicians: [ThanksPerson]
    var partners: [ThanksPerson]
}

/// The list of people to thank. Bundled `Resources/Thanks/thanks.json` (+ photos) for now.
/// TODO(server): load the list from our server (JSON + pictures), cache it with its date and show the cached copy
/// offline («Нет интернета · показан список от …», canvas ThanksOffline) — people get added without a new release.
@MainActor @Observable
final class ThanksStore {
    static let shared = ThanksStore()

    private(set) var musicians: [ThanksPerson] = []
    private(set) var partners: [ThanksPerson] = []
    /// Set when the server could not be reached and a saved list is shown (its date).
    var offlineSince: Date?

    private init() {
        if let url = Bundle.main.url(forResource: "thanks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(ThanksFile.self, from: data) {
            musicians = file.musicians
            partners = file.partners
        }
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        // Screenshot fixture: `-thanksFixture <path>` — the invented people of the canvas boards
        // (Truver/Tools/canvas/thanks_canvas_sample.json), read from the Mac's disk; never bundled.
        if let i = args.firstIndex(of: "-thanksFixture"), i + 1 < args.count,
           let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1])),
           let file = try? JSONDecoder().decode(ThanksFile.self, from: data) {
            musicians = file.musicians
            partners = file.partners
        }
        #endif
        // Screenshot hook: `-thanksOffline` — the toast of a saved list (canvas: 20 ноября).
        if args.contains("-thanksOffline") {
            var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 20
            offlineSince = Calendar.current.date(from: c)
        }
    }

    func person(id: String) -> ThanksPerson? { (musicians + partners).first { $0.id == id } }

    /// «20 ноября» for the offline toast.
    static func dayMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }

    /// A bundled photo (downscaled whole photo — never cropped; the circle aspect-fills it).
    nonisolated static func image(named name: String) -> Image? {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext.isEmpty ? nil : ext) else { return nil }
        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
        #else
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
        #endif
    }
}

// MARK: - Updates

/// One line of «Что нового»: a bold section and the change.
struct ReleaseNote: Hashable {
    let section: String
    let text: String
}

/// A version the store knows about.
struct UpdateInfo: Equatable {
    let version: String
    /// Download size, MB.
    let sizeMB: Int
    let notes: [ReleaseNote]
    /// Set for a mandatory update (only a critical error — wrong tuning or cents): why.
    var requiredReason: String?
}

/// Where the app learns about new versions.
protocol UpdateSource: Sendable {
    func latest() async throws -> UpdateInfo?
}

/// TODO(server): iOS/Mac — App Store lookup (`https://itunes.apple.com/lookup?bundleId=app.truver.ios`: version,
/// release notes, size) + our file with the minimum version (mandatory update); Android — Play In-App Updates.
/// There is no server yet: the stub always answers «no newer version».
struct StubUpdateSource: UpdateSource {
    func latest() async throws -> UpdateInfo? { nil }
}

/// Update notices (canvas «Спасибо · обновления»): 1) a newer version — once per version at launch (not while tuning
/// or while the metronome plays), «Позже» = in 3 days, plus the banner in «О Truver»; 2) «Что нового» — once after
/// an update, and from «О Truver»; 3) a mandatory update — only for a critical error, the metronome and the
/// fretboard keep working.
@MainActor @Observable
final class UpdateCenter {
    static let shared = UpdateCenter()

    enum State: Equatable { case unknown, checking, upToDate, available(UpdateInfo), required(UpdateInfo), failed }
    enum Sheet: Equatable { case available, whatsNew }

    private(set) var state: State = .unknown
    /// The notice sheet to show (host over the app, or «О Truver» for «Что нового»).
    var sheet: Sheet?
    /// «Нужно обновить Truver» — a full screen over the app.
    var showsRequired = false
    var source: UpdateSource = StubUpdateSource()

    let currentVersion: String
    let currentBuild: String

    private let defaults = UserDefaults.standard
    private enum Key {
        static let lastLaunched = "updates.lastLaunchedVersion"
        static let dismissed = "updates.dismissedVersion"
        static let remindAfter = "updates.remindAfter"
    }

    /// Notes of each released version, newest first («Что нового» and the history in «О Truver»).
    static let history: [(version: String, notes: [ReleaseNote])] = [
        ("1.0", [
            ReleaseNote(section: "Тюнер:", text: "строи для 6–9 струн и свои строи"),
            ReleaseNote(section: "Гриф:", text: "гаммы, аккорды и прогрессии на всём грифе"),
            ReleaseNote(section: "Метроном:", text: "ритмические фигуры, разгон и проверка игры"),
        ]),
    ]

    /// The canvas sample (debug launch arguments only).
    static let demo = UpdateInfo(version: "1.2", sizeMB: 18, notes: [
        ReleaseNote(section: "Тюнер:", text: "быстрее ловит низкий B0 на 9 струнах"),
        ReleaseNote(section: "Строи:", text: "Drop A и Drop G♯ для 8 струн"),
        ReleaseNote(section: "Метроном:", text: "не сбивается при блокировке экрана"),
    ], requiredReason: "В версии 1.0 найдена ошибка: на частоте A4 ≠ 440 Гц тюнер показывал неверные центы. Исправлено в 1.2.")

    private var demoWhatsNew: UpdateInfo?

    private init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let args = ProcessInfo.processInfo.arguments
        // Screenshot hooks: `-updateDemo available|whatsNew|required|failed` (canvas UpdateAvailable, UpdateWhatsNew,
        // UpdateRequired, UpdateCheckFailed); `available` also shows the banner of «О Truver» (ThanksAbout).
        if let i = args.firstIndex(of: "-updateDemo"), i + 1 < args.count {
            switch args[i + 1] {
            case "available": state = .available(Self.demo); sheet = args.contains("-settingsPage") ? nil : .available
            case "banner": state = .available(Self.demo)
            case "whatsNew": demoWhatsNew = Self.demo; state = .upToDate; sheet = .whatsNew
            case "required": state = .required(Self.demo); showsRequired = true
            case "failed": state = .failed
            default: break
            }
            demoMode = true
        }
    }

    private var demoMode = false

    /// The version «Что нового» describes: the newer one when known, otherwise this one.
    var whatsNew: (version: String, notes: [ReleaseNote])? {
        if let demoWhatsNew { return (demoWhatsNew.version, demoWhatsNew.notes) }
        if case .available(let info) = state, !info.notes.isEmpty { return (info.version, info.notes) }
        return Self.history.first { $0.version == currentVersion } ?? Self.history.first
    }

    var available: UpdateInfo? {
        if case .available(let info) = state { return info }
        if case .required(let info) = state { return info }
        return nil
    }

    /// At launch: «Что нового» once after an update, then the store check.
    func launch(canInterrupt: @escaping () -> Bool) {
        guard !demoMode else { return }
        let last = defaults.string(forKey: Key.lastLaunched)
        defaults.set(currentVersion, forKey: Key.lastLaunched)
        if let last, Self.compare(last, currentVersion) == .orderedAscending,
           Self.history.contains(where: { $0.version == currentVersion }) {
            sheet = .whatsNew
        }
        Task { await check(canInterrupt: canInterrupt) }
    }

    func check(canInterrupt: @escaping () -> Bool = { true }) async {
        guard !demoMode || state == .failed else { return }
        state = .checking
        do {
            guard let info = try await source.latest(), Self.compare(currentVersion, info.version) == .orderedAscending else {
                state = .upToDate
                return
            }
            if info.requiredReason != nil {
                state = .required(info)
                showsRequired = true
                return
            }
            state = .available(info)
            let remind = defaults.object(forKey: Key.remindAfter) as? Date ?? .distantPast
            if sheet == nil, defaults.string(forKey: Key.dismissed) != info.version || remind < Date(), canInterrupt() {
                sheet = .available
            }
        } catch {
            state = .failed
        }
    }

    /// «Позже»: once per version, again in 3 days.
    func later() {
        if let info = available {
            defaults.set(info.version, forKey: Key.dismissed)
            defaults.set(Date().addingTimeInterval(3 * 24 * 3600), forKey: Key.remindAfter)
        }
        sheet = nil
    }

    /// TODO(store): the App Store page of Truver (app id after publishing); `itms-apps://` opens the store app.
    static let storeURL = URL(string: "https://apps.apple.com/app/truver")!

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: .numeric)
    }
}

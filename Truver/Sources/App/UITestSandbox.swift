import Foundation

#if DEBUG
/// UI tests run on the owner's iPhone and reset settings: with `-uiTest` they work on a copy.
/// The first test launch saves all UserDefaults to a file (the instruments and journal stay untouched: the test
/// launch uses an in-memory store); the next normal launch puts the defaults back and removes the file.
enum UITestSandbox {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-uiTest")

    private static var backupURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("ui-test-defaults-backup.plist")
    }

    /// Call before anything reads UserDefaults.
    static func prepare() {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        let exists = FileManager.default.fileExists(atPath: backupURL.path)
        if isActive {
            if !exists {     // otherwise an earlier test launch already holds the owner's values
                let values = defaults.persistentDomain(forName: domain) ?? [:]
                do {
                    let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
                    try data.write(to: backupURL, options: .atomic)
                } catch {
                    fatalError("UI test sandbox: could not back up the settings: \(error)")   // never test over real data
                }
            }
        } else if exists {
            guard let data = try? Data(contentsOf: backupURL),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
            defaults.setPersistentDomain(values, forName: domain)
            defaults.synchronize()
            try? FileManager.default.removeItem(at: backupURL)
        }
        selfCheck(defaults)
    }

    /// `-sandboxProbe <value|read>`: stores a value and reports what the app sees to Library/sandbox-probe.txt, so the
    /// backup and restore can be checked from outside.
    private static func selfCheck(_ defaults: UserDefaults) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-sandboxProbe"), i + 1 < args.count else { return }
        if args[i + 1] != "read" {
            defaults.set(args[i + 1], forKey: "sandboxProbe")
            defaults.synchronize()
        }
        let url = backupURL.deletingLastPathComponent().appendingPathComponent("sandbox-probe.txt")
        // The stored value only: the launch argument itself also shows up in UserDefaults.
        let stored = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0)?["sandboxProbe"] as? String }
        try? (stored ?? "nil").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif

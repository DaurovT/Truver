#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif

/// Plain pthread mutex: the core avoids full Foundation (NSLock) so the Android/Windows library stays small.
final class TheoryLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    init() {
        mutex = .allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

extension StringProtocol {
    /// Spaces and tabs trimmed at both ends (`trimmingCharacters(in: .whitespaces)` without full Foundation).
    var trimmedSpaces: String {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }
        guard let first = firstIndex(where: { !isSpace($0) }), let last = lastIndex(where: { !isSpace($0) }) else { return "" }
        return String(self[first...last])
    }
}

#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
import TruverAtomics

/// Mutex that the render thread may only *try* (never wait on): a control call holding it makes the render
/// thread output silence for one buffer instead of blocking (same policy as the iOS host).
public final class PortableLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    public init() {
        mutex = .allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    public func lock() { pthread_mutex_lock(mutex) }
    public func unlock() { pthread_mutex_unlock(mutex) }
    public func tryLock() -> Bool { pthread_mutex_trylock(mutex) == 0 }

    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// Monotonic clock in nanoseconds — the time base of beat ticks and attack times on every platform.
public enum HostClock {
    public static func nowNanos() -> Int64 {
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return Int64(ts.tv_sec) * 1_000_000_000 + Int64(ts.tv_nsec)
    }
}

/// Single-producer single-consumer ring of samples: the input callback writes, the analysis thread reads.
/// Lock-free; when the reader falls behind, new samples are dropped (counted) rather than blocking the callback.
final class SampleRing: @unchecked Sendable {
    let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>
    /// [0] write index, [1] read index, [2] dropped samples — monotonically increasing.
    private let indices: UnsafeMutablePointer<Int64>

    init(capacityPowerOfTwo: Int) {
        precondition(capacityPowerOfTwo.nonzeroBitCount == 1)
        capacity = capacityPowerOfTwo
        mask = capacityPowerOfTwo - 1
        storage = .allocate(capacity: capacityPowerOfTwo)
        storage.initialize(repeating: 0, count: capacityPowerOfTwo)
        indices = .allocate(capacity: 3)
        indices.initialize(repeating: 0, count: 3)
    }

    deinit {
        storage.deallocate()
        indices.deallocate()
    }

    /// Producer: copies every `stride`-th sample starting at `source` (one channel of interleaved input).
    func write(_ source: UnsafePointer<Float>, count: Int, stride: Int) {
        let write = truver_load_relaxed(indices)
        let read = truver_load_acquire(indices + 1)
        let free = capacity - Int(write - read)
        let n = min(count, free)
        if n < count { truver_store_relaxed(indices + 2, truver_load_relaxed(indices + 2) + Int64(count - n)) }
        var w = Int(write)
        for i in 0..<n {
            storage[w & mask] = source[i * stride]
            w += 1
        }
        truver_store_release(indices, write + Int64(n))
    }

    /// Consumer: moves up to `maxCount` samples into `destination`; returns how many.
    func read(into destination: UnsafeMutablePointer<Float>, maxCount: Int) -> Int {
        let read = truver_load_relaxed(indices + 1)
        let write = truver_load_acquire(indices)
        let n = min(maxCount, Int(write - read))
        var r = Int(read)
        for i in 0..<n {
            destination[i] = storage[r & mask]
            r += 1
        }
        truver_store_release(indices + 1, read + Int64(n))
        return n
    }

    /// Consumer: discards everything buffered (a new tuner pipeline must not analyse stale audio).
    func clear() {
        truver_store_release(indices + 1, truver_load_acquire(indices))
    }

    var dropped: Int64 { truver_load_relaxed(indices + 2) }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Starts a detached pthread running `body` (Foundation's Thread is not in FoundationEssentials).
func startThread(_ body: @escaping @Sendable () -> Void) {
    final class Box { let body: @Sendable () -> Void; init(_ b: @escaping @Sendable () -> Void) { body = b } }
    let context = Unmanaged.passRetained(Box(body)).toOpaque()
    #if canImport(Darwin)
    var thread: pthread_t?
    #else
    var thread = pthread_t()
    #endif
    #if canImport(Darwin)
    let entry: @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? = { raw in
        Unmanaged<Box>.fromOpaque(raw).takeRetainedValue().body()
        return nil
    }
    #else
    let entry: @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { raw in
        Unmanaged<Box>.fromOpaque(raw!).takeRetainedValue().body()
        return nil
    }
    #endif
    if pthread_create(&thread, nil, entry, context) == 0 {
        #if canImport(Darwin)
        if let thread { pthread_detach(thread) }
        #else
        pthread_detach(thread)
        #endif
    } else {
        Unmanaged<Box>.fromOpaque(context).release()
    }
}

/// «12.3» — one decimal without `String(format:)`.
func oneDecimal(_ value: Double) -> String {
    let tenths = Int((value * 10).rounded())
    let sign = tenths < 0 ? "-" : ""
    return "\(sign)\(abs(tenths) / 10).\(abs(tenths) % 10)"
}

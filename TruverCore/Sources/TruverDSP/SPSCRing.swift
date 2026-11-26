import TruverAtomics

/// Lock-free single-producer / single-consumer ring buffer for trivial value types.
///
/// The producer (render thread) never waits and never allocates; if the ring is full the value is dropped and
/// counted. The consumer drains everything that was published. Used for the beat timeline (ME-12) so that no
/// tick is lost while the UI reads (PRD 13).
public final class SPSCRing<Element>: @unchecked Sendable {
    public let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Element>
    /// [0] = write index (producer), [1] = read index (consumer), [2] = dropped count. Monotonic counters.
    private let indices: UnsafeMutablePointer<Int64>

    /// `capacity` is rounded up to a power of two. `filler` initialises the storage (any value).
    public init(capacity: Int, filler: Element) {
        precondition(_isPOD(Element.self), "SPSCRing needs a trivial element type")
        var size = 1
        while size < max(2, capacity) { size <<= 1 }
        self.capacity = size
        self.mask = size - 1
        storage = .allocate(capacity: size)
        storage.initialize(repeating: filler, count: size)
        indices = .allocate(capacity: 3)
        indices.initialize(repeating: 0, count: 3)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
        indices.deallocate()
    }

    /// Producer only. Returns false (and counts a drop) when full.
    @discardableResult
    public func push(_ value: Element) -> Bool {
        let write = truver_load_relaxed(indices)
        let read = truver_load_acquire(indices + 1)
        guard write - read < Int64(capacity) else {
            truver_store_relaxed(indices + 2, truver_load_relaxed(indices + 2) + 1)
            return false
        }
        storage[Int(write) & mask] = value
        truver_store_release(indices, write + 1)
        return true
    }

    /// Consumer only: everything published so far, oldest first.
    public func drain() -> [Element] {
        let read = truver_load_relaxed(indices + 1)
        let write = truver_load_acquire(indices)
        guard write > read else { return [] }
        var result: [Element] = []
        result.reserveCapacity(Int(write - read))
        for i in read..<write { result.append(storage[Int(i) & mask]) }
        truver_store_release(indices + 1, write)
        return result
    }

    /// Values dropped because the consumer did not keep up.
    public var droppedCount: Int { Int(truver_load_relaxed(indices + 2)) }
}

/// A Double shared between threads without locks (e.g. output latency read by the render thread).
public final class AtomicDouble: @unchecked Sendable {
    private let bits: UnsafeMutablePointer<Int64>

    public init(_ value: Double) {
        bits = .allocate(capacity: 1)
        bits.initialize(to: Int64(bitPattern: value.bitPattern))
    }

    deinit { bits.deallocate() }

    public var value: Double {
        get { Double(bitPattern: UInt64(bitPattern: truver_load_acquire(bits))) }
        set { truver_store_release(bits, Int64(bitPattern: newValue.bitPattern)) }
    }
}

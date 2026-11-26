#if os(Android)
import Android
import CTruverAndroid
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch
import TruverDSP

/// AAudio streams for Android 10+: low-latency float output (stereo, the mono render copied to both channels)
/// and unprocessed float input (no AGC / noise suppression — the tuner needs the raw string).
public final class AndroidAudioBackend: AudioBackend, @unchecked Sendable {
    public var onDisconnect: (@Sendable (_ input: Bool) -> Void)?

    private var output: OpaquePointer?
    private var input: OpaquePointer?
    private var render: OutputRender?
    private var inputHandler: InputHandler?
    private var inputChannel = 0
    private var inputChannels = 1
    private var outputChannels = 2

    /// Mono scratch for the render (the device asks for at most its buffer capacity per callback).
    private var mono: UnsafeMutablePointer<Float>
    private var monoCapacity = 8192
    /// Nanoseconds from "now" in the callback until the block is heard, refreshed from AAudio timestamps.
    private let outputLatency = AtomicDouble(0)
    private let inputLatency = AtomicDouble(0)
    private var callbackCount = 0
    private let lock = PortableLock()

    public init() {
        mono = .allocate(capacity: monoCapacity)
        mono.initialize(repeating: 0, count: monoCapacity)
    }

    deinit {
        stopOutput()
        stopInput()
        mono.deallocate()
    }

    private var context: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    // MARK: Output

    public var isOutputRunning: Bool { lock.withLock { output.map { truver_aaudio_is_running($0) == 1 } ?? false } }

    public func startOutput(render: @escaping OutputRender) throws -> Double {
        lock.lock()
        defer { lock.unlock() }
        if let output { truver_aaudio_close(output); self.output = nil }
        self.render = render
        var stream: OpaquePointer?
        var result = truver_aaudio_open(0, 0, 2, 1, androidOutputCallback, androidErrorCallback, context, &stream)
        if result != 0 {
            // Exclusive (MMAP) is not available on every device: fall back to shared.
            result = truver_aaudio_open(0, 0, 2, 0, androidOutputCallback, androidErrorCallback, context, &stream)
        }
        guard result == 0, let stream else { throw AudioBackendError("Выход звука: \(Self.text(result))") }
        outputChannels = Int(truver_aaudio_channel_count(stream))
        let capacity = Int(truver_aaudio_capacity(stream))
        if capacity > monoCapacity {
            mono.deallocate()
            monoCapacity = capacity
            mono = .allocate(capacity: capacity)
            mono.initialize(repeating: 0, count: capacity)
        }
        output = stream
        let start = truver_aaudio_start(stream)
        guard start == 0 else {
            truver_aaudio_close(stream)
            output = nil
            throw AudioBackendError("Выход звука: \(Self.text(start))")
        }
        return Double(truver_aaudio_sample_rate(stream))
    }

    public func stopOutput() {
        lock.lock()
        let stream = output
        output = nil
        lock.unlock()
        if let stream { truver_aaudio_close(stream) }
    }

    fileprivate func renderOutput(_ stream: OpaquePointer, _ data: UnsafeMutableRawPointer, _ frames: Int) -> Int32 {
        let out = data.assumingMemoryBound(to: Float.self)
        let channels = outputChannels
        guard let render, frames <= monoCapacity else {
            out.update(repeating: 0, count: frames * channels)
            return 0
        }
        callbackCount &+= 1
        if callbackCount % 50 == 1 {
            let latency = truver_aaudio_latency_ns(stream, 0)
            if latency >= 0 { outputLatency.value = Double(latency) }
        }
        let presentation = truver_monotonic_ns() + Int64(outputLatency.value)
        render(mono, frames, presentation)
        if channels == 1 {
            out.update(from: mono, count: frames)
        } else {
            for i in 0..<frames {
                let v = mono[i]
                for c in 0..<channels { out[i * channels + c] = v }
            }
        }
        return 0   // AAUDIO_CALLBACK_RESULT_CONTINUE
    }

    // MARK: Input

    public var isInputRunning: Bool { lock.withLock { input.map { truver_aaudio_is_running($0) == 1 } ?? false } }

    public func startInput(channel: Int, handler: @escaping InputHandler) throws -> Double {
        lock.lock()
        defer { lock.unlock() }
        if let input { truver_aaudio_close(input); self.input = nil }
        inputHandler = handler
        var stream: OpaquePointer?
        // Channel count 0: the device's own (a multi-input interface gives all its inputs, AU-2).
        var result = truver_aaudio_open(1, 0, channel > 0 ? 0 : 1, 1, androidInputCallback, androidErrorCallback, context, &stream)
        if result != 0 {
            result = truver_aaudio_open(1, 0, channel > 0 ? 0 : 1, 0, androidInputCallback, androidErrorCallback, context, &stream)
        }
        guard result == 0, let stream else { throw AudioBackendError("Микрофон: \(Self.text(result))") }
        inputChannels = max(1, Int(truver_aaudio_channel_count(stream)))
        inputChannel = min(max(0, channel), inputChannels - 1)
        input = stream
        let start = truver_aaudio_start(stream)
        guard start == 0 else {
            truver_aaudio_close(stream)
            input = nil
            throw AudioBackendError("Микрофон: \(Self.text(start))")
        }
        return Double(truver_aaudio_sample_rate(stream))
    }

    public func stopInput() {
        lock.lock()
        let stream = input
        input = nil
        lock.unlock()
        if let stream { truver_aaudio_close(stream) }
    }

    fileprivate func receiveInput(_ stream: OpaquePointer, _ data: UnsafeMutableRawPointer, _ frames: Int) -> Int32 {
        guard let inputHandler else { return 0 }
        let samples = UnsafePointer(data.assumingMemoryBound(to: Float.self))
        inputHandler(samples + inputChannel, frames, inputChannels, 0)
        return 0
    }

    // MARK: Errors and diagnostics

    fileprivate func streamError(_ stream: OpaquePointer?) {
        let isInput = lock.withLock { stream != nil && stream == input }
        // AAudio requires the stream to be closed and reopened off the callback thread.
        DispatchQueue.global().async { [weak self] in self?.onDisconnect?(isInput) }
    }

    public var diagnostics: [String: String] {
        lock.withLock {
            var d: [String: String] = [:]
            if let output {
                d["output.rate"] = "\(truver_aaudio_sample_rate(output))"
                d["output.exclusive"] = truver_aaudio_is_exclusive(output) == 1 ? "да" : "нет"
                d["output.latencyMs"] = oneDecimal(outputLatency.value / 1e6)
            }
            if let input {
                d["input.rate"] = "\(truver_aaudio_sample_rate(input))"
                d["input.channels"] = "\(inputChannels)"
                d["input.exclusive"] = truver_aaudio_is_exclusive(input) == 1 ? "да" : "нет"
                let latency = truver_aaudio_latency_ns(input, 1)
                if latency >= 0 { d["input.latencyMs"] = oneDecimal(Double(latency) / 1e6) }
            }
            return d
        }
    }

    private static func text(_ result: Int32) -> String {
        truver_aaudio_error_text(result).map { String(cString: $0) } ?? "\(result)"
    }
}

private func backend(_ context: UnsafeMutableRawPointer?) -> AndroidAudioBackend? {
    guard let context else { return nil }
    return Unmanaged<AndroidAudioBackend>.fromOpaque(context).takeUnretainedValue()
}

private let androidOutputCallback: truver_aaudio_data_fn = { stream, context, data, frames in
    guard let stream, let data, let backend = backend(context) else { return 0 }
    return backend.renderOutput(stream, data, Int(frames))
}

private let androidInputCallback: truver_aaudio_data_fn = { stream, context, data, frames in
    guard let stream, let data, let backend = backend(context) else { return 0 }
    return backend.receiveInput(stream, data, Int(frames))
}

private let androidErrorCallback: truver_aaudio_error_fn = { stream, context, _ in
    backend(context)?.streamError(stream)
}
#endif

/// Called on the real-time output thread: fill `frames` mono samples. `presentationNanos` is when the first
/// sample of the block is heard (monotonic clock, output latency included).
public typealias OutputRender = (_ buffer: UnsafeMutablePointer<Float>, _ frames: Int, _ presentationNanos: Int64) -> Void

/// Called on the real-time input thread: `frames` samples of the selected channel are every `stride`-th value
/// from `samples`. `captureNanos` is when the first sample was captured (0 if unknown).
public typealias InputHandler = (_ samples: UnsafePointer<Float>, _ frames: Int, _ stride: Int, _ captureNanos: Int64) -> Void

/// One platform's audio device layer (AAudio on Android, WASAPI on Windows). `AudioHost` puts the Truver
/// metronome, synth and tuner on top of it.
public protocol AudioBackend: AnyObject, Sendable {
    /// Opens and starts output (mono render, the backend spreads it to the device channels). Returns the rate.
    func startOutput(render: @escaping OutputRender) throws -> Double
    func stopOutput()
    var isOutputRunning: Bool { get }

    /// Opens and starts input. `channel` picks an interface input (0-based, clamped). Returns the rate.
    func startInput(channel: Int, handler: @escaping InputHandler) throws -> Double
    func stopInput()
    var isInputRunning: Bool { get }

    /// Called (on any thread) when a stream was lost — headphones unplugged, interface removed (AU-7).
    /// The host restarts what was running.
    var onDisconnect: (@Sendable (_ input: Bool) -> Void)? { get set }

    /// Diagnostics for the «Диагностика» list: rate, latency, exclusive mode, burst.
    var diagnostics: [String: String] { get }
}

public struct AudioBackendError: Error, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

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
import TruverDSP
import TruverHost
import TruverTheory

/// C entry points for the Flutter app (dart:ffi) on Android and Windows.
///
/// One call shape for everything that is not real-time: `truver_call("method", "{json params}")` returns
/// `{"ok": value}` or `{"error": "text"}` as a malloc'ed UTF-8 string the caller frees with `truver_free`.
/// Real-time data (tuner readings, beat ticks) is polled every frame with `audio.poll`, so no callback ever
/// crosses into Dart from an audio thread.

@_cdecl("truver_call")
public func truver_call(_ method: UnsafePointer<CChar>?, _ params: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let name = method.map { String(cString: $0) } ?? ""
    let json = params.map { String(cString: $0) } ?? "{}"
    let response = Bridge.shared.call(name, json: json)
    return strdup(response)
}

@_cdecl("truver_free")
public func truver_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    free(pointer)
}

/// Monotonic nanoseconds — the clock of `hostNanos` in beat ticks, for the UI to place flashes in time.
@_cdecl("truver_now_ns")
public func truver_now_ns() -> Int64 {
    HostClock.nowNanos()
}

struct BridgeError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

/// Shared state the commands work on: the instrument and notation the app currently uses (the Dart side sends
/// them whenever they change), and the audio host.
final class Bridge: @unchecked Sendable {
    static let shared = Bridge()

    typealias Handler = (Data) throws -> any Encodable
    private var handlers: [String: Handler] = [:]
    private let lock = PortableLock()

    var instrument: Instrument = TuningTemplates.template(id: "g8-drop-e")?.makeInstrument()
        ?? TuningTemplates.all[0].makeInstrument()
    var notation: NoteNotation = .international
    var defaultA4: Double = 440

    var tuning: Tuning { instrument.currentTuning ?? instrument.tunings[0] }
    var a4: Double { tuning.effectiveA4(default: defaultA4) }
    var formatter: NoteFormatter { NoteFormatter(notation: notation, language: .ru) }

    lazy var audio: AudioHost? = Bridge.makeAudioHost()

    private init() {
        registerSession()
        registerAudio()
        registerTheory()
        // One file per feature so ports can add commands without touching each other's code.
        registerShell()
        registerTuner()
        registerMetronome()
        registerFretboard()
        registerInstrument()
        registerPractice()
    }

    func register(_ method: String, _ handler: @escaping Handler) {
        handlers[method] = handler
    }

    /// Registers a handler with typed parameters.
    func register<P: Decodable>(_ method: String, _ params: P.Type, _ handler: @escaping (P) throws -> any Encodable) {
        handlers[method] = { data in try handler(JSONDecoder().decode(P.self, from: data)) }
    }

    func call(_ method: String, json: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let handler = handlers[method] else { return Self.error("unknown method \(method)") }
        do {
            let value = try handler(Data(json.utf8))
            return try Self.ok(value)
        } catch let error as DecodingError {
            return Self.error("\(method): bad params — \(error)")
        } catch {
            return Self.error("\(method): \(error)")
        }
    }

    private static func ok<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(OK(ok: value))
        return String(decoding: data, as: UTF8.self)
    }

    private static func error(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(["error": text])) ?? Data(#"{"error":"?"}"#.utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private struct OK<T: Encodable>: Encodable { var ok: T }

    private static func makeAudioHost() -> AudioHost? {
        #if os(Android)
        return AudioHost(backend: AndroidAudioBackend())
        #else
        return nil
        #endif
    }

    func requireAudio() throws -> AudioHost {
        guard let audio else { throw BridgeError("audio is not available on this platform") }
        return audio
    }
}

struct Empty: Codable {}
struct Done: Encodable { var done = true }

extension Bridge {
    func registerSession() {
        register("core.version") { _ in ["core": "1", "platform": Self.platformName] }

        struct SessionParams: Decodable {
            var instrument: Instrument?
            var notation: NoteNotation?
            var defaultA4: Double?
        }
        register("session.set", SessionParams.self) { [unowned self] p in
            if let i = p.instrument { instrument = i }
            if let n = p.notation { notation = n }
            if let a = p.defaultA4 { defaultA4 = a }
            return Done()
        }
    }

    static var platformName: String {
        #if os(Android)
        "android"
        #elseif os(Windows)
        "windows"
        #elseif os(macOS)
        "macos"
        #else
        "other"
        #endif
    }
}

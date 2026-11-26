import AVFoundation
import Foundation
import TruverAudio
import TruverDSP
import TruverTheory
#if os(iOS)
import UIKit
#endif

/// JSON-lines log: Documents/autotest.jsonl, also printed to stdout (visible with `devicectl … launch --console`).
final class SpikeLog: @unchecked Sendable {
    static let shared = SpikeLog()
    let url: URL
    private let queue = DispatchQueue(label: "truver.log")
    private let handle: FileHandle?
    private let start = Date()

    init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("autotest.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func log(_ kind: String, _ fields: KeyValuePairs<String, Any> = [:]) {
        log(kind, pairs: fields.map { ($0.key, $0.value) })
    }

    func log(_ kind: String, pairs fields: [(String, Any)]) {
        var dict: [String: Any] = ["t": (Date().timeIntervalSince(start) * 1000).rounded() / 1000, "kind": kind]
        for (key, value) in fields {
            if let d = value as? Double, !d.isFinite { continue }
            dict[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        let line = text + "\n"
        print(line, terminator: "")
        let handle = self.handle
        queue.async { handle?.write(Data(line.utf8)) }
    }
}

/// Finds click onsets in the raw microphone signal for the acoustic loopback (SM-6) and click level (AU-6).
final class LoopbackProbe: @unchecked Sendable {
    struct Onset { var hostTime: UInt64; var peakDB: Double }

    private let lock = NSLock()
    private var onsets: [Onset] = []
    private var noise: Float = 0.001
    private var holdoff = 0
    private(set) var hostTimeMissing = false
    private var blocks = 0
    private var peak: Float = 0

    /// Input blocks and peak level since the last call (heartbeat).
    func heartbeat() -> (blocks: Int, peakDB: Double) {
        lock.lock()
        defer { lock.unlock() }
        let result = (blocks, 20 * log10(Double(max(peak, 1e-9))))
        blocks = 0
        peak = 0
        return result
    }

    func process(_ samples: [Float], hostTime: UInt64, sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        blocks += 1
        peak = max(peak, samples.map(abs).max() ?? 0)
        var base = hostTime
        if base == 0 {
            hostTimeMissing = true
            base = mach_absolute_time() - AVAudioTime.hostTime(forSeconds: Double(samples.count) / sampleRate)
        }
        for i in samples.indices {
            let a = abs(samples[i])
            if holdoff > 0 {
                holdoff -= 1
            } else if a > max(0.001, noise * 6) {
                let end = min(samples.count, i + Int(0.01 * sampleRate))
                let peak = samples[i..<end].map(abs).max() ?? a
                onsets.append(Onset(hostTime: base + AVAudioTime.hostTime(forSeconds: Double(i) / sampleRate),
                                    peakDB: 20 * log10(Double(max(peak, 1e-9)))))
                holdoff = Int(0.3 * sampleRate)
            } else {
                noise = noise * 0.9995 + a * 0.0005
            }
        }
    }

    func take() -> (onsets: [Onset], noiseDB: Double) {
        lock.lock()
        defer { lock.unlock() }
        let result = (onsets, 20 * log10(Double(max(noise, 1e-9))))
        onsets = []
        return result
    }
}

extension SpikeModel {
    static var autotestRequested: Bool { ProcessInfo.processInfo.arguments.contains("-autotest") }

    /// Stage-0 measurements without a person: environment, tuner on external tones, acoustic loopback of the
    /// metronome click in `.measurement` and `.default`, then the tuner again in `.default`.
    func runAutotest() async {
        let log = SpikeLog.shared
        log.log("start", ["device": Self.deviceDescription, "log": log.url.path])
        let probe = LoopbackProbe()
        host.onInputBlock = { samples, hostTime, rate in probe.process(samples, hostTime: hostTime, sampleRate: rate) }
        templateId = "g7-standard-b"
        useMeasurementMode = true
        let heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                if self.host.ensureRunning() == false { SpikeLog.shared.log("engineRestartFailed") }
                let input = probe.heartbeat()
                let counters = self.takeCounters()
                var fields: [(String, Any)] = [
                    ("engine", self.host.engine.isRunning), ("tuner", self.tunerRunning), ("metronome", self.metronomeRunning),
                    ("clock", self.host.isMetronomeRunning), ("inBlocks", input.blocks), ("inPeakDB", (input.peakDB * 10).rounded() / 10),
                    ("updates", counters.updates), ("ticks", counters.ticks),
                ]
                if let level = self.lastUpdate?.levelDB { fields.append(("lastLevel", (level * 10).rounded() / 10)) }
                if let error = self.lastError { fields.append(("error", error)) }
                #if os(iOS)
                fields.append(("volume", Double(AVAudioSession.sharedInstance().outputVolume)))
                #endif
                SpikeLog.shared.log("beat", pairs: fields)
            }
        }
        defer { heartbeat.cancel() }

        stopTuner()
        await startTuner(userConfirmedGap: true)
        logEnvironment("measurement")
        onTunerUpdate = { [weak self] update in self?.logTuner(update) }
        log.log("phase", ["name": "tuner-measurement", "seconds": 14])
        try? await Task.sleep(for: .seconds(14))

        onTunerUpdate = nil
        await loopback("loopback-measurement", probe: probe)

        stopTuner()
        #if os(iOS)
        try? session.deactivate()
        #endif
        useMeasurementMode = false
        await startTuner(userConfirmedGap: true)
        logEnvironment("default")
        await loopback("loopback-default", probe: probe)

        onTunerUpdate = { [weak self] update in self?.logTuner(update) }
        log.log("phase", ["name": "tuner-default", "seconds": 14])
        try? await Task.sleep(for: .seconds(14))
        onTunerUpdate = nil

        stopTuner()
        useMeasurementMode = true
        host.onInputBlock = nil
        log.log("done")
    }

    private func loopback(_ label: String, probe: LoopbackProbe) async {
        let log = SpikeLog.shared
        log.log("phase", ["name": label, "seconds": 9])
        _ = probe.take()
        recordedTicks = []
        bpm = 60
        numerator = 4
        subdivision = 1
        modeChoice = .none
        startMetronome()
        let outputLatency = host.outputLatency
        try? await Task.sleep(for: .seconds(9))
        stopMetronome()
        try? await Task.sleep(for: .milliseconds(500))
        let (onsets, noiseDB) = probe.take()
        let ticks = (recordedTicks ?? []).filter { $0.event.tick == 0 && !$0.event.isSilent }
        recordedTicks = nil

        var residuals: [Double] = []
        var peaks: [Double] = []
        for onset in onsets {
            let onsetSeconds = AVAudioTime.seconds(forHostTime: onset.hostTime)
            guard let nearest = ticks.min(by: {
                abs(AVAudioTime.seconds(forHostTime: $0.hostTime) - onsetSeconds) < abs(AVAudioTime.seconds(forHostTime: $1.hostTime) - onsetSeconds)
            }) else { continue }
            let residual = (onsetSeconds - AVAudioTime.seconds(forHostTime: nearest.hostTime)) * 1000
            log.log("onset", ["label": label, "residualMs": residual, "peakDB": onset.peakDB, "beat": nearest.event.beat])
            if abs(residual) < 250 {
                residuals.append(residual)
                peaks.append(onset.peakDB)
            }
        }
        func median(_ v: [Double]) -> Double { v.isEmpty ? .nan : v.sorted()[v.count / 2] }
        log.log("loopback", [
            "label": label,
            "ticks": ticks.count,
            "onsets": onsets.count,
            "matched": residuals.count,
            "residualMedianMs": median(residuals),
            "residualSpreadMs": (residuals.max() ?? .nan) - (residuals.min() ?? .nan),
            "clickPeakMedianDB": median(peaks),
            "noiseFloorDB": noiseDB,
            "outputLatencyUsedMs": outputLatency * 1000,
            "hostTimeMissing": probe.hostTimeMissing,
        ])
    }

    private func logTuner(_ update: TunerUpdate) {
        var fields: [(String, Any)] = [("level", (update.levelDB * 10).rounded() / 10)]
        switch update.display {
        case .idle: fields.append(("state", "idle"))
        case .listening: fields.append(("state", "listening"))
        case .outOfRange: fields.append(("state", "outOfRange"))
        case .reading(let r):
            fields.append(("state", "reading"))
            fields.append(("hz", (r.frequency * 100).rounded() / 100))
            fields.append(("cents", (r.target.deviationCents * 10).rounded() / 10))
            fields.append(("provisional", r.isProvisional))
            switch r.target {
            case let .string(ref, _, _): fields.append(("target", "string " + noteName(for: ref)))
            case let .chromatic(nearest, _, hint):
                fields.append(("target", "chromatic " + noteName(for: nearest)))
                if let hint { fields.append(("hint", noteName(for: hint.string))) }
            }
        }
        if !update.events.isEmpty { fields.append(("events", update.events.map { "\($0)" })) }
        SpikeLog.shared.log("tuner", pairs: fields)
    }

    private func logEnvironment(_ label: String) {
        let input = host.engine.inputNode.outputFormat(forBus: 0)
        let output = host.engine.outputNode.inputFormat(forBus: 0)
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        SpikeLog.shared.log("environment", [
            "label": label,
            "category": s.category.rawValue,
            "mode": s.mode.rawValue,
            "sampleRate": s.sampleRate,
            "ioBufferMs": s.ioBufferDuration * 1000,
            "inputLatencyMs": s.inputLatency * 1000,
            "outputLatencyMs": s.outputLatency * 1000,
            "inputs": s.currentRoute.inputs.map { "\($0.portType.rawValue): \($0.portName)" },
            "outputs": s.currentRoute.outputs.map { "\($0.portType.rawValue): \($0.portName)" },
            "inputGain": Double(s.inputGain),
            "inputGainSettable": s.isInputGainSettable,
            "engineInput": "\(input.sampleRate) Hz × \(input.channelCount)",
            "engineOutput": "\(output.sampleRate) Hz × \(output.channelCount)",
            "outputVolume": Double(s.outputVolume),
        ])
        #else
        SpikeLog.shared.log("environment", [
            "label": label,
            "engineInput": "\(input.sampleRate) Hz × \(input.channelCount)",
            "engineOutput": "\(output.sampleRate) Hz × \(output.channelCount)",
            "outputLatencyMs": host.engine.outputNode.presentationLatency * 1000,
        ])
        #endif
    }

    static var deviceDescription: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        #if os(iOS)
        return "\(machine) iOS \(UIDevice.current.systemVersion)"
        #else
        return "\(machine) macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
    }
}

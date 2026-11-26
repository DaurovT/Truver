#if canImport(AVFoundation)
import AVFoundation
import Foundation
import TruverDSP

/// An attack on the device clock (seconds, the same clock as the beat timeline's host times).
public struct TimedOnset: Equatable, Sendable {
    public var time: Double
    public var strength: Double

    public init(time: Double, strength: Double) {
        self.time = time
        self.strength = strength
    }
}

/// SM-1 on live input: runs the onset detector on the microphone blocks and puts every attack on the host clock
/// (input latency removed), so it can be compared with the beat timeline (ME-12). Keeps a short level history for
/// «не распознано» (SM-10: sound without a clear attack). Thread-safe: blocks come from the tap thread, readers
/// are on the main thread.
public final class PlayCheckAnalyzer: @unchecked Sendable {
    public let sampleRate: Double
    /// Input latency of the route (s): the tap's host time is when the block left the converter.
    public let inputLatency: Double

    private let detector: OnsetDetector
    private let queue = DispatchQueue(label: "truver.playcheck", qos: .userInteractive)
    private let lock = NSLock()
    private var onsets: [TimedOnset] = []
    private var levels: [(time: Double, db: Double)] = []
    private var blocks: [(start: Int64, time: Double)] = []
    private var streamPosition: Int64 = 0
    private let gateDB: Double

    public init(sampleRate: Double, inputLatency: Double, noiseGateDB: Double = -55) {
        self.sampleRate = sampleRate
        self.inputLatency = inputLatency
        gateDB = noiseGateDB
        var config = OnsetConfiguration(sampleRate: sampleRate)
        config.noiseGateDB = noiseGateDB
        detector = OnsetDetector(configuration: config)
    }

    public static func seconds(hostTime: UInt64) -> Double { AVAudioTime.seconds(forHostTime: hostTime) }

    /// Called from the input tap (any thread).
    public func process(_ samples: [Float], hostTime: UInt64) {
        let time = hostTime == 0 ? Self.seconds(hostTime: mach_absolute_time()) : Self.seconds(hostTime: hostTime)
        queue.async { [self] in
            let start = streamPosition
            streamPosition += Int64(samples.count)
            blocks.append((start, time - inputLatency))
            if blocks.count > 400 { blocks.removeFirst(blocks.count - 400) }
            // Level in 10 ms slices for «есть звук».
            let slice = max(1, Int(sampleRate * 0.01))
            var newLevels: [(Double, Double)] = []
            var i = 0
            while i < samples.count {
                let part = samples[i..<min(samples.count, i + slice)]
                newLevels.append((time - inputLatency + Double(i) / sampleRate, Level.rmsDB(part)))
                i += slice
            }
            let found = detector.process(samples).compactMap { onset -> TimedOnset? in
                guard let t = self.time(ofSample: onset.sample) else { return nil }
                return TimedOnset(time: t, strength: onset.strength)
            }
            lock.withLock {
                levels.append(contentsOf: newLevels)
                if levels.count > 1500 { levels.removeFirst(levels.count - 1500) }
                onsets.append(contentsOf: found)
                if onsets.count > 512 { onsets.removeFirst(onsets.count - 512) }
            }
        }
    }

    private func time(ofSample sample: Double) -> Double? {
        guard let block = blocks.last(where: { Double($0.start) <= sample }) else { return nil }
        return block.time + (sample - Double(block.start)) / sampleRate
    }

    /// Blocks until everything handed in so far is analysed (tests).
    public func waitUntilProcessed() { queue.sync {} }

        /// Attacks between `from` and `to` (seconds).
    public func onsets(from: Double, to: Double) -> [TimedOnset] {
        lock.withLock { onsets.filter { $0.time >= from && $0.time <= to } }
    }

    /// Was there sound above the gate around `time` (±30 ms)? For SM-10.
    public func isSounding(at time: Double) -> Bool {
        lock.withLock { levels.contains { abs($0.time - time) <= 0.03 && $0.db >= gateDB } }
    }

    /// The newest time the analyser has heard (seconds), nil before the first block.
    public var heardUntil: Double? {
        lock.withLock { levels.last?.time }
    }
}

#endif

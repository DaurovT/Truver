#if canImport(Accelerate) && !TRUVER_PORTABLE_DSP
import Accelerate
#endif
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

public struct OnsetConfiguration: Sendable {
    public var sampleRate: Double
    /// FFT frame and hop for detection (≈ 10.7 ms and 2.7 ms at 48 kHz).
    public var frameSize: Int = 512
    public var hop: Int = 128
    /// Below this level nothing is an onset (TU-3 gate, shared idea).
    public var noiseGateDB: Double = -55
    /// Two onsets closer than this are one (the fastest graded note is 40 ms, SM-4).
    public var minInterval: Double = 0.035
    /// Adaptive threshold: median of the recent flux × factor + offset.
    public var medianFrames: Int = 16
    public var thresholdFactor: Double = 2.0
    public var thresholdOffset: Double = 0.005
    /// SuperFlux reference: the maximum of this many previous frames (≈ 32 ms, longer than the period of B0) and
    /// of neighbouring bins. Suppresses the frame-to-frame "breathing" of low notes whose period is longer than
    /// the analysis frame.
    public var referenceFrames: Int = 12
    /// Bins below this frequency are ignored (room rumble, handling noise).
    public var minFrequency: Double = 60
    /// Fraction of the rise (baseline → peak envelope) that marks the attack start in the refinement.
    public var riseFraction: Double = 0.15
    /// The refinement envelope is taken above this frequency: the attack (pick noise, the first sharp edge) is
    /// broadband, while ringing low notes would make a sample-level envelope follow their waveform.
    public var refinementHighPass: Double = 3000
    /// A candidate needs a real transient: the high-passed envelope must jump at least this many times over its
    /// level 1 ms before. Spectral artefacts of a decaying note do not; a pick or a click does. Attacks with no
    /// transient at all are not reported (SM-10: "не распознано" rather than a wrong time).
    public var minSharpness: Double = 2

    public init(sampleRate: Double) { self.sampleRate = sampleRate }
}

public struct DetectedOnset: Equatable, Sendable {
    /// Absolute position in the input stream, in samples (fractional).
    public var sample: Double
    /// Peak spectral flux (relative loudness of the attack).
    public var strength: Double

    public func seconds(sampleRate: Double) -> Double { sample / sampleRate }
}

/// Attack detector for the smart mode (SM-1): spectral flux finds the attack, a time-domain envelope pins its
/// start. Streaming: feed blocks of any size; onsets come out about one frame after they happen.
///
/// Not thread-safe: feed it from one thread.
public final class OnsetDetector {
    public let configuration: OnsetConfiguration

    #if canImport(Accelerate) && !TRUVER_PORTABLE_DSP
    private let log2n: vDSP_Length
    private let fft: FFTSetup
    #else
    private let fft: PortableRealFFT
    #endif
    private let window: [Float]
    private var recentSpectra: [[Float]] = []
    private let firstBin: Int

    private var history: [Float] = []
    private let historyCapacity: Int
    private var total: Int64 = 0
    private var hopFill = 0

    private var fluxHistory: [Double] = []
    private var lastFlux = 0.0
    private var beforeLastFlux = 0.0
    private var lastFrameEnd: Int64 = 0
    private var lastFrameLevel = -160.0
    /// A candidate is held for `minInterval`: a stronger one in that time replaces it (a weak false rise just
    /// before a real attack must not shadow the attack).
    private var pending: DetectedOnset?
    /// Diagnostics hook: (time in seconds, flux) for every frame.
    var debugFlux: ((Double, Double) -> Void)?

    public init(configuration: OnsetConfiguration) {
        precondition(configuration.frameSize.nonzeroBitCount == 1, "frameSize must be a power of two")
        self.configuration = configuration
        #if canImport(Accelerate) && !TRUVER_PORTABLE_DSP
        log2n = vDSP_Length(log2(Double(configuration.frameSize)))
        fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: configuration.frameSize, isHalfWindow: false)
        #else
        fft = PortableRealFFT(size: configuration.frameSize)
        window = PortableDSP.hann(count: configuration.frameSize)
        #endif
        firstBin = max(1, Int(configuration.minFrequency / configuration.sampleRate * Double(configuration.frameSize)))
        historyCapacity = configuration.frameSize * 3 + configuration.hop * 2 + 128
    }

    #if canImport(Accelerate) && !TRUVER_PORTABLE_DSP
    deinit { vDSP_destroy_fftsetup(fft) }
    #endif

    /// Feeds samples; returns onsets confirmed by this block.
    public func process(_ samples: [Float]) -> [DetectedOnset] {
        var onsets: [DetectedOnset] = []
        var index = 0
        while index < samples.count {
            let take = min(configuration.hop - hopFill, samples.count - index)
            history.append(contentsOf: samples[index..<(index + take)])
            if history.count > historyCapacity { history.removeFirst(history.count - historyCapacity) }
            index += take
            hopFill += take
            total += Int64(take)
            if hopFill == configuration.hop {
                hopFill = 0
                if let onset = analyzeFrame() { onsets.append(onset) }
            }
        }
        return onsets
    }

    private func analyzeFrame() -> DetectedOnset? {
        let n = configuration.frameSize
        guard history.count >= n else { return nil }
        let frame = Array(history.suffix(n))
        let flux = spectralFlux(frame)
        debugFlux?(Double(total) / configuration.sampleRate, flux)
        let level = Level.rmsDB(frame[(n - configuration.hop)...])

        // Peak picking with one frame of look-ahead: the previous frame is an onset if it is a local maximum
        // above the adaptive threshold.
        var emitted: DetectedOnset?
        let holdSamples = configuration.minInterval * configuration.sampleRate
        if let held = pending, Double(total) - held.sample > holdSamples + Double(configuration.frameSize) {
            emitted = held
            pending = nil
        }
        let sorted = fluxHistory.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let threshold = median * configuration.thresholdFactor + configuration.thresholdOffset
        if lastFlux > beforeLastFlux, lastFlux >= flux, lastFlux > threshold,
           max(lastFrameLevel, level) >= configuration.noiseGateDB {
            let (position, sharpness) = refine(frameEnd: lastFrameEnd)
            let candidate = DetectedOnset(sample: position, strength: lastFlux)
            if sharpness < configuration.minSharpness {
                // No transient: not an attack.
            } else if let held = pending, candidate.sample - held.sample < holdSamples {
                if candidate.strength > held.strength { pending = candidate }
            } else {
                if let held = pending { emitted = held }
                pending = candidate
            }
        }

        fluxHistory.append(lastFlux)
        if fluxHistory.count > configuration.medianFrames { fluxHistory.removeFirst() }
        beforeLastFlux = lastFlux
        lastFlux = flux
        lastFrameEnd = total
        lastFrameLevel = level
        return emitted
    }

    /// Returns a held onset at the end of the input (e.g. when the exercise stops).
    public func flush() -> DetectedOnset? {
        defer { pending = nil }
        return pending
    }

    /// SuperFlux: half-wave rectified increase of log magnitudes over the max of recent frames and neighbouring
    /// bins, averaged over bins.
    private func spectralFlux(_ frame: [Float]) -> Double {
        let n = configuration.frameSize
        let half = n / 2
        var magnitudes = [Float](repeating: 0, count: half)
        #if canImport(Accelerate) && !TRUVER_PORTABLE_DSP
        var windowed = [Float](repeating: 0, count: n)
        vDSP.multiply(frame, window, result: &windowed)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        #else
        var windowed = [Float](repeating: 0, count: n)
        for i in 0..<n { windowed[i] = frame[i] * window[i] }
        fft.magnitudes(windowed, into: &magnitudes)
        #endif
        var current = [Float](repeating: 0, count: half)
        for k in 0..<half { current[k] = log1pf(magnitudes[k] * 0.05) }
        var sum = 0.0
        if !recentSpectra.isEmpty {
            for k in firstBin..<half {
                var reference: Float = 0
                for spectrum in recentSpectra {
                    reference = max(reference, spectrum[k], spectrum[max(0, k - 1)], spectrum[min(half - 1, k + 1)])
                }
                let rise = current[k] - reference
                if rise > 0 { sum += Double(rise) }
            }
        }
        recentSpectra.append(current)
        if recentSpectra.count > configuration.referenceFrames { recentSpectra.removeFirst() }
        return sum / Double(half - firstBin)
    }

    /// Attack start inside the detected frame: the first point, going back from the envelope peak, where the
    /// envelope falls below baseline + riseFraction × (peak − baseline). Resolution ≈ 0.33 ms (16-sample blocks)
    /// plus linear interpolation.
    private func refine(frameEnd: Int64) -> (sample: Double, sharpness: Double) {
        let block = 16
        let n = configuration.frameSize
        // Region: the detected frame plus the newest hop (look-ahead), as far as the history reaches.
        let regionEnd = history.count
        let regionStart = max(0, regionEnd - (n + configuration.hop + Int(total - frameEnd)))
        let blocks = (regionEnd - regionStart) / block
        guard blocks > 4 else { return (Double(frameEnd) - Double(n) / 2, 0) }
        // High-pass the region (with a short warm-up before it) so that ringing low notes do not shape the envelope.
        // Fourth order (two biquads): the harmonics of ringing notes must not leak into the envelope.
        var filter1 = Biquad.highPass(cutoff: configuration.refinementHighPass, sampleRate: configuration.sampleRate)
        var filter2 = filter1
        func filtered(_ x: Float) -> Double { filter2.process(filter1.process(Double(x))) }
        let warmup = max(0, regionStart - 128)
        for i in warmup..<regionStart { _ = filtered(history[i]) }
        var envelope = [Double](repeating: 0, count: blocks)
        for b in 0..<blocks {
            var peak = 0.0
            let start = regionStart + b * block
            for i in start..<(start + block) { peak = max(peak, abs(filtered(history[i]))) }
            envelope[b] = peak
        }
        // Attack: the block that rises most *relative* to the 1 ms before it (a quiet pick over a loud ringing
        // note is still a large ratio), among reasonably loud blocks, in the part of the region where the frame's
        // flux peak can come from (not the first quarter of the frame).
        let loudest = envelope.max() ?? 0
        let searchFrom = max(1, (n / 4) / block)
        var jumpAt = searchFrom
        var bestScore = -Double.infinity
        for b in searchFrom..<blocks where envelope[b] >= 0.3 * loudest {
            let before = envelope[max(0, b - 3)...(b - 1)].max()!
            let score = envelope[b] / (before + 1e-4)
            if score > bestScore { bestScore = score; jumpAt = b }
        }
        var peakAt = jumpAt
        while peakAt + 1 < blocks && envelope[peakAt + 1] >= envelope[peakAt] { peakAt += 1 }
        let pre = envelope[0..<max(1, jumpAt - 1)].sorted()
        let baseline = pre[pre.count / 2]
        let level = baseline + configuration.riseFraction * (envelope[peakAt] - baseline)
        var b = jumpAt
        while b > 0 && envelope[b - 1] >= level { b -= 1 }
        // Interpolate inside the crossing pair of blocks.
        let below = b > 0 ? envelope[b - 1] : baseline
        let above = envelope[b]
        let fraction = above > below ? (level - below) / (above - below) : 0
        let blockPosition = (Double(b) - 1 + fraction) * Double(block) + Double(block) / 2
        let streamStart = Double(total) - Double(regionEnd - regionStart)
        return (streamStart + max(0, blockPosition), bestScore)
    }
}

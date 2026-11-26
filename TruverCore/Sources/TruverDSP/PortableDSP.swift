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

/// Plain-Swift versions of the few Accelerate calls the core uses, for platforms without Accelerate
/// (Android, Windows). On Apple platforms the vDSP path stays; `PortableDSPTests` checks that both give the
/// same numbers, so the tuner and the onset detector behave identically everywhere.
enum PortableDSP {
    /// `r[τ] = Σ_{j<window} x[j]·x[j+τ]` for τ in 0…maxLag — what `vDSP_conv(x, 1, x, 1, r, 1, maxLag+1, window)` does.
    /// Float accumulation like vDSP; the inner loop is written over raw pointers so the compiler vectorises it.
    static func autocorrelation(_ x: UnsafePointer<Float>, window: Int, maxLag: Int, into out: UnsafeMutablePointer<Float>) {
        for tau in 0...maxLag {
            let shifted = x + tau
            var s0: Float = 0, s1: Float = 0, s2: Float = 0, s3: Float = 0
            var j = 0
            while j + 4 <= window {
                s0 += x[j] * shifted[j]
                s1 += x[j + 1] * shifted[j + 1]
                s2 += x[j + 2] * shifted[j + 2]
                s3 += x[j + 3] * shifted[j + 3]
                j += 4
            }
            while j < window {
                s0 += x[j] * shifted[j]
                j += 1
            }
            out[tau] = (s0 + s1) + (s2 + s3)
        }
    }

    /// Hann window with peak 1 (`vDSP.window(.hanningDenormalized, isHalfWindow: false)`): 0.5·(1 − cos(2πn/N)).
    static func hann(count: Int) -> [Float] {
        (0..<count).map { n in Float(0.5 * (1 - cos(2 * Double.pi * Double(n) / Double(count)))) }
    }
}

/// Radix-2 real FFT magnitudes with vDSP's scaling and packing, so `OnsetDetector` reads the same values:
/// `vDSP_fft_zrip` returns 2·X[k]; bin 0 packs DC (real) and Nyquist (imaginary), and `vDSP_zvabs` takes
/// the modulus of that pair.
final class PortableRealFFT {
    let size: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReverse: [Int]
    private var re: [Double]
    private var im: [Double]

    init(size: Int) {
        precondition(size >= 4 && size.nonzeroBitCount == 1, "size must be a power of two")
        self.size = size
        cosTable = (0..<(size / 2)).map { cos(-2 * Double.pi * Double($0) / Double(size)) }
        sinTable = (0..<(size / 2)).map { sin(-2 * Double.pi * Double($0) / Double(size)) }
        let bits = size.trailingZeroBitCount
        bitReverse = (0..<size).map { i in
            var r = 0
            for b in 0..<bits where i & (1 << b) != 0 { r |= 1 << (bits - 1 - b) }
            return r
        }
        re = [Double](repeating: 0, count: size)
        im = [Double](repeating: 0, count: size)
    }

    /// `input` has `size` samples; `magnitudes` gets `size / 2` values.
    func magnitudes(_ input: [Float], into magnitudes: inout [Float]) {
        let n = size
        for i in 0..<n {
            re[bitReverse[i]] = Double(input[i])
            im[bitReverse[i]] = 0
        }
        var length = 2
        while length <= n {
            let half = length / 2
            let step = n / length
            var start = 0
            while start < n {
                for k in 0..<half {
                    let wr = cosTable[k * step], wi = sinTable[k * step]
                    let a = start + k, b = a + half
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
                start += length
            }
            length *= 2
        }
        let half = n / 2
        // vDSP packing: [0] = (2·DC, 2·Nyquist), [k] = 2·X[k].
        magnitudes[0] = Float(2 * (re[0] * re[0] + re[half] * re[half]).squareRoot())
        for k in 1..<half {
            magnitudes[k] = Float(2 * (re[k] * re[k] + im[k] * im[k]).squareRoot())
        }
    }
}

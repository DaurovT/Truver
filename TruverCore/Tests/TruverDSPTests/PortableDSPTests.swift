#if canImport(Accelerate)
import Accelerate
import Foundation
import Testing
@testable import TruverDSP

/// The plain-Swift fallbacks used on Android and Windows must give the same numbers as vDSP on Apple platforms.
@Suite struct PortableDSPTests {
    private func signal(_ count: Int, seed: UInt64 = 7) -> [Float] {
        var state = seed
        return (0..<count).map { i in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float(Int64(bitPattern: state >> 11) % 1000) / 10_000
            return 0.6 * sin(Float(i) * 0.031) + 0.25 * sin(Float(i) * 0.173) + noise
        }
    }

    @Test func autocorrelationMatchesVDSPConv() {
        let window = 1300, maxLag = 1100
        let x = signal(window + maxLag)
        var expected = [Float](repeating: 0, count: maxLag + 1)
        var actual = [Float](repeating: 0, count: maxLag + 1)
        x.withUnsafeBufferPointer { p in
            vDSP_conv(p.baseAddress!, 1, p.baseAddress!, 1, &expected, 1, vDSP_Length(maxLag + 1), vDSP_Length(window))
            PortableDSP.autocorrelation(p.baseAddress!, window: window, maxLag: maxLag, into: &actual)
        }
        for tau in 0...maxLag {
            #expect(abs(expected[tau] - actual[tau]) <= 1e-4 * max(1, abs(expected[0])), "lag \(tau)")
        }
    }

    @Test func hannMatchesVDSP() {
        let expected = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 512, isHalfWindow: false)
        let actual = PortableDSP.hann(count: 512)
        for i in 0..<512 { #expect(abs(expected[i] - actual[i]) < 1e-6) }
    }

    @Test func realFFTMagnitudesMatchVDSP() {
        let n = 512, half = n / 2
        let x = signal(n, seed: 99)
        let log2n = vDSP_Length(9)
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        var real = [Float](repeating: 0, count: half), imag = [Float](repeating: 0, count: half)
        var expected = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                x.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &expected, 1, vDSP_Length(half))
            }
        }
        var actual = [Float](repeating: 0, count: half)
        PortableRealFFT(size: n).magnitudes(x, into: &actual)
        let peak = expected.max()!
        for k in 0..<half { #expect(abs(expected[k] - actual[k]) <= 1e-4 * peak, "bin \(k)") }
    }
}
#endif

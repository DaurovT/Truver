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

/// Rotation of the strobe band (motion spec, «Тюнер»): degrees per second = deviation in cents × 6, at most
/// 300 °/s; within ±1 cent the band stands still. The angle accumulates, so the band never jumps.
/// (The P1 phase strobe, TU-10, drives the band from the signal phase instead.)
public struct StrobeRotation: Sendable {
    public var degreesPerSecondPerCent = 6.0
    public var maxDegreesPerSecond = 300.0
    public var deadZoneCents = 1.0
    public private(set) var angle = 0.0

    public init() {}

    public func speed(cents: Double) -> Double {
        guard abs(cents) > deadZoneCents else { return 0 }
        return max(-maxDegreesPerSecond, min(maxDegreesPerSecond, cents * degreesPerSecondPerCent))
    }

    /// Advances by `dt` seconds at the speed for `cents`; returns the angle in degrees (0..<360).
    @discardableResult
    public mutating func advance(cents: Double, dt: Double) -> Double {
        angle = (angle + speed(cents: cents) * dt).truncatingRemainder(dividingBy: 360)
        if angle < 0 { angle += 360 }
        return angle
    }
}

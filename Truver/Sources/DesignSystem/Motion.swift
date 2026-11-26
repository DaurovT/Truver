import SwiftUI

/// Motion tokens of «Truver — спецификация движения». No bare durations or curves in views: everything comes
/// from here, and «Уменьшить движение» picks the replacement inside the token.
enum Motion {
    enum Duration {
        static let instant: Double = 0
        static let tick: Double = 0.09
        static let quick: Double = 0.16
        static let base: Double = 0.24
        static let move: Double = 0.32
        static let slow: Double = 0.6
        static let breath: Double = 2.4
    }

    /// Everything that appears or slides in.
    static func out(_ duration: Double) -> Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: duration) }
    /// Everything that leaves; one step shorter than its appearance.
    static func inCurve(_ duration: Double) -> Animation { .timingCurve(0.4, 0, 1, 1, duration: duration) }

    /// Needle spring: stiffness 300, damping 1.0 (critical, no overshoot) — values must never lie about pitch.
    static let needleStiffness: Double = 300
    static var needleDamping: Double { 2 * needleStiffness.squareRoot() }
    static let needle = Animation.interpolatingSpring(stiffness: needleStiffness, damping: needleDamping)
    /// Sheets, fretboard position, window handles.
    static let snap = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Rewards only: «Готово», «Цель достигнута», a string mark.
    static let pop = Animation.spring(response: 0.42, dampingFraction: 0.62)

    static func quick(_ reduceMotion: Bool) -> Animation { out(Duration.quick) }
    static func base(_ reduceMotion: Bool) -> Animation { out(Duration.base) }
    /// Sheets and steps: a crossfade instead of a slide when motion is reduced.
    static func move(_ reduceMotion: Bool) -> Animation { reduceMotion ? out(Duration.base) : snap }
    /// Rewards: a fade without scale when motion is reduced.
    static func reward(_ reduceMotion: Bool) -> Animation { reduceMotion ? out(Duration.base) : pop }
}

/// Critically damped spring integrated per display frame (needle, deviation slider). Used inside
/// `TimelineView(.animation)` + Canvas so that 30–40 readings per second never stack animations.
final class SpringFollower {
    private(set) var value: Double
    private var velocity: Double = 0
    private var lastTime: Date?

    init(_ value: Double = 0) { self.value = value }

    /// Moves towards `target`; with `reduceMotion` jumps straight there.
    func step(to target: Double, at time: Date, reduceMotion: Bool) -> Double {
        defer { lastTime = time }
        guard !reduceMotion, let last = lastTime else {
            value = target
            velocity = 0
            return value
        }
        var dt = min(0.05, max(0, time.timeIntervalSince(last)))
        let k = Motion.needleStiffness, c = Motion.needleDamping
        // Semi-implicit Euler in small steps for stability.
        while dt > 0 {
            let h = min(dt, 1.0 / 240)
            let acceleration = -k * (value - target) - c * velocity
            velocity += acceleration * h
            value += velocity * h
            dt -= h
        }
        return value
    }

    func reset(_ value: Double) {
        self.value = value
        velocity = 0
        lastTime = nil
    }
}

/// Button press feedback (motion spec: scale 96 % and slightly lighter while touched, `tick`).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(Motion.out(Motion.Duration.tick), value: configuration.isPressed)
    }
}

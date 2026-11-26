//
//  TruverDesignTokens.swift
//  Truver — design tokens (iOS 17+ / macOS 14+, SwiftUI)
//
//  Source of truth for numbers: the design canvas ("Truver — дизайн iOS и Mac").
//  This file is its copy in code; if they disagree, the canvas wins and this file
//  is fixed. Motion constants come from the motion spec. PRD §12b.
//
//  Rules that are not just numbers:
//  • Green (`Color.T.inTune`) is used ONLY for "in tune / target reached / exact".
//    Selection, toggles, checkmarks and "on" states use ink, never green.
//  • Flat = blue, sharp = orange, always paired with a word ("Ниже" / "Выше").
//  • Purple marks user-modified things (modified scale, custom tuning).
//

import SwiftUI

// MARK: - Colors

extension Color {
    enum T {
        // Surfaces (dark only in v1; light theme is P2)
        static let background   = Color(hex: 0x0A0B0D)
        static let surface      = Color(hex: 0x141518)
        static let surfaceHigh  = Color(hex: 0x1A1B1E)
        static let surfaceTop   = Color(hex: 0x202227)
        static let hairline     = Color.white.opacity(0.08)
        static let glassFill    = Color.white.opacity(0.04)

        // Text
        static let ink          = Color(hex: 0xF6F3EC)   // primary, selected, "on"
        static let text         = Color(hex: 0xE9E6DF)   // body
        static let secondary    = Color(hex: 0xA29F97)   // captions, units
        static let tertiary     = Color(hex: 0x8A877F)   // hints, disabled

        // Semantic — tuner
        static let inTune       = Color(hex: 0x46E08F)   // ONLY in tune / target
        static let flat         = Color(hex: 0x6AA8FF)
        static let sharp        = Color(hex: 0xFF9B52)
        static let error        = Color(hex: 0xFF6B5E)
        static let modified     = Color(hex: 0xC3A6FF)

        // Fretboard dots
        // Fretboard dots: fill / label / 1.5 pt ring
        static let dotTonic        = Color(hex: 0xF5EFE3, opacity: 0.96)
        static let dotTonicRing    = Color.white
        static let dotChordTone    = Color(hex: 0x8FC4FF, opacity: 0.95)
        static let dotChordRing    = Color(hex: 0xCFE5FF)
        static let dotOther        = Color(hex: 0x181A1E, opacity: 0.74)   // dark, not white
        static let dotOtherRing    = Color(hex: 0x969CA6, opacity: 0.70)
        static let dotOtherLabel   = Color(hex: 0xEEF0F3)
        static let dotLabelOnLight = Color(hex: 0x0C0D0F)
        static let dotGhost        = Color.white.opacity(0.08)

        // Controls
        static let toggleOnTrack = Color(hex: 0xECE8DF)
        static let toggleOnKnob  = Color(hex: 0x141518)
        static let primaryButton = ink
        static let onPrimary     = Color(hex: 0x0A0B0D)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double(hex         & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Typography
// Inter (SIL OFL 1.1 — may be bundled; license file goes in Resources/Fonts and "О Truver").
// Weights used: 200, 300, 400, 500, 600, 700. Sizes scale with Dynamic Type via relativeTo.

private func inter(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    let name: String
    switch weight {
    case .ultraLight: name = "Inter-ExtraLight"
    case .light:      name = "Inter-Light"
    case .medium:     name = "Inter-Medium"
    case .semibold:   name = "Inter-SemiBold"
    case .bold:       name = "Inter-Bold"
    default:          name = "Inter-Regular"
    }
    return .custom(name, size: size)
}

enum TFont {
    // Tuner note: 96 / 72 / 60 pt by name length (PRD 5.1.4).
    // 1 char ("E", "H") → 96; 2–3 chars ("F♯", "до") → 72; 4–5 chars ("соль♯") → 60.
    static func tunerNote(chars: Int) -> Font {
        let size: CGFloat = chars <= 1 ? 96 : (chars <= 3 ? 72 : 60)
        return inter(size, .light)
    }
    static let tunerOctave   = inter(22, .regular)
    static let tunerCents    = inter(22, .medium).monospacedDigit()
    static let tunerHz       = inter(12, .regular).monospacedDigit()
    static let tunerHint     = inter(17, .medium)

    static let bpm           = inter(64, .ultraLight).monospacedDigit()
    static let bpmStandBy    = inter(190, .ultraLight).monospacedDigit()

    static let screenTitle   = inter(17, .semibold)
    static let body          = inter(15, .regular)
    static let caption       = inter(12, .regular)
    static let stringKey     = inter(15, .semibold)
    static let stringKeySolf = inter(12, .semibold)   // solfège keys
    static let fretDot       = inter(12, .bold)
    static let fretDotSolf   = inter(9, .bold)       // "сол♯" in a dot

    static let letterTight: CGFloat = -0.02   // em, for big numerals and note names
}

// MARK: - Spacing, radii, sizes

enum TSpace {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 6
    static let s:   CGFloat = 8
    static let m:   CGFloat = 12
    static let l:   CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
    static let screenH: CGFloat = 20      // horizontal screen inset
}

enum TRadius {
    static let chip:   CGFloat = 10
    static let key:    CGFloat = 12
    static let card:   CGFloat = 16
    static let sheet:  CGFloat = 26
    static let widget: CGFloat = 22
    static let pill:   CGFloat = 999
}

enum TSize {
    static let minHit:        CGFloat = 44   // every tappable thing
    static let roundButton:   CGFloat = 44
    static let fretPlayPill:  CGFloat = 52   // height; capsule "▶ Сыграть", padding 14/18
    static let metroPlay:     CGFloat = 88   // round start/stop in the metronome
    static let tunerDial:     CGFloat = 320  // outer; inner glass 294; Mac uses ×1.25
    static let fretDot:       CGFloat = 32   // never below 26 on dense necks (FB-18)
    static let fretDotPath:   CGFloat = 24
    static let fretDotGhost:  CGFloat = 14
    static let macMinWindow = CGSize(width: 620, height: 560)
}

// MARK: - Motion

enum TMotion {
    // Tuner signal pipeline (not animation curves — signal processing constants)
    static let medianWindow            = 3          // samples
    static let smoothingFar: Double    = 0.6        // EMA alpha when |cents| > 15
    static let smoothingNear: Double   = 0.25       // EMA alpha within ±15 c
    static let smoothingSwitchCents    = 15.0

    // In-tune hysteresis
    static let inTuneEnterCents        = 3.0        // must hold within ±3 c…
    static let inTuneEnterHold         = 0.300      // …for 300 ms
    static let inTuneExitCents         = 5.0        // leave only past ±5 c

    // Strobe band
    static let strobeDegPerSecPerCent  = 6.0
    static let strobeMaxDegPerSec      = 300.0

    // Deviation marker: critically damped spring, stiffness 300
    static let marker = Animation.interpolatingSpring(stiffness: 300, damping: 2 * sqrt(300.0))

    // UI transitions (match the canvas keyframes)
    static let sheetIn   = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)
    static let popIn     = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.38)
    static let fade      = Animation.easeOut(duration: 0.20)
    static let noteHop   = Animation.spring(response: 0.25, dampingFraction: 0.6)
    static let inTuneGlowPeriod: Double = 1.6   // seconds, slow breathe — never in tempo

    // Reduce Motion: strobe stops (static band + text), springs become 0.15 s fades.
    static func resolved(_ a: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : a
    }
}

// MARK: - Notation

enum TNotation: String, CaseIterable {
    case english, german, solfege
    /// Longest label per system — use for layout tests.
    var longestName: String {
        switch self {
        case .english: "C♯"
        case .german:  "Cis"
        case .solfege: "соль♯"
        }
    }
}

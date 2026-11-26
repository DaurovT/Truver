import SwiftUI
import CoreText
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Inter (OFL), bundled. Sizes follow the canvas; every font scales with Dynamic Type relative to a text style.
enum Typo {
    enum Weight: String {
        case extraLight = "Inter-ExtraLight"
        case light = "Inter-Light"
        case regular = "Inter-Regular"
        case medium = "Inter-Medium"
        case semibold = "Inter-SemiBold"
        case bold = "Inter-Bold"

        /// SwiftUI's name for weight 200 (canvas `font-weight: 200`) — Inter ExtraLight.
        static var ultraLight: Weight { .extraLight }
    }

    /// Inter with the system font as fallback for glyphs Inter lacks (♯, ♭, 𝄪, 𝄫), scaled with Dynamic Type.
    static func inter(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle? = nil) -> Font {
        let textStyle = style ?? self.textStyle(for: size)
        #if os(iOS)
        guard let base = UIFont(name: weight.rawValue, size: size) else { return .custom(weight.rawValue, size: size, relativeTo: textStyle) }
        let fallback = UIFont.systemFont(ofSize: size, weight: uiWeight(weight)).fontDescriptor
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [fallback], .featureSettings: [tabularFigures]])
        let font = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: uiStyle(textStyle)).scaledFont(for: font))
        #else
        guard let base = NSFont(name: weight.rawValue, size: size) else { return .custom(weight.rawValue, size: size, relativeTo: textStyle) }
        let fallback = NSFont.systemFont(ofSize: size).fontDescriptor
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [fallback], .featureSettings: [tabularFigures]])
        return Font(NSFont(descriptor: descriptor, size: size) ?? base)
        #endif
    }

    /// Inter at a fixed size (instrument numerals whose layout is sized by the canvas; large-text layouts).
    static func fixed(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        #if os(iOS)
        guard let base = UIFont(name: weight.rawValue, size: size) else { return .custom(weight.rawValue, fixedSize: size) }
        let fallback = UIFont.systemFont(ofSize: size, weight: uiWeight(weight)).fontDescriptor
        return Font(UIFont(descriptor: base.fontDescriptor.addingAttributes([.cascadeList: [fallback], .featureSettings: [tabularFigures]]), size: size))
        #else
        return .custom(weight.rawValue, fixedSize: size)
        #endif
    }

    /// `font-variant-numeric: tabular-nums` — set on the root of every canvas board, so all digits of the design are
    /// tabular («6-струнная», «109,1 Гц», tab labels), not only the `.monospacedDigit()` ones.
    #if os(iOS)
    private static let tabularFigures: [UIFontDescriptor.FeatureKey: Int] = [.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector]
    #else
    private static let tabularFigures: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector]
    #endif

    #if os(iOS)
    private static func uiWeight(_ weight: Weight) -> UIFont.Weight {
        switch weight {
        case .extraLight: return .ultraLight
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .caption2: return .caption2
        case .caption: return .caption1
        case .footnote: return .footnote
        case .subheadline: return .subheadline
        case .body: return .body
        case .title2: return .title2
        default: return .largeTitle
        }
    }
    #endif

    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<17: return .subheadline
        case ..<20: return .body
        case ..<28: return .title2
        default: return .largeTitle
        }
    }

    // Named roles of the canvas
    /// Screen title of the canvas header: 26 semibold, letter-spacing −0.02 em, line height 1.15.
    static let screenTitle = inter(26, .semibold)
    static let body = inter(15)
    static let row = inter(15)
    static let caption = inter(12)
    static let chip = inter(12, .medium)
    static let segment = inter(13, .medium)
    static let segmentSelected = inter(13, .semibold)
    static let status = inter(17, .medium)
    static let button = inter(15, .semibold)
    static let tab = inter(11)
    static let tabSelected = inter(11, .semibold)
}

extension Typo {
    /// Note text whose accidentals (♯ ♭ 𝄪 𝄫) are set in the system font, as on the canvas: Inter's own ♯ looks like «#».
    static func notes(_ string: String, size: CGFloat, weight: Weight = .regular, fixed: Bool = false) -> Text {
        let accidentals: Set<Character> = ["♯", "♭", "𝄪", "𝄫", "♮"]
        let base = fixed ? Typo.fixed(size, weight) : Typo.inter(size, weight)
        let system = Font.system(size: size, weight: weight.systemWeight)
        var result = Text("")
        var run = ""
        func flush() { if !run.isEmpty { result = result + Text(run).font(base); run = "" } }
        for ch in string {
            if accidentals.contains(ch) { flush(); result = result + Text(String(ch)).font(system) } else { run.append(ch) }
        }
        flush()
        return result
    }
}

extension Typo.Weight {
    var systemWeight: Font.Weight {
        switch self {
        case .extraLight: return .ultraLight
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// Numbers as on the canvas: decimal comma («109,1 Гц», «×1,6»).
func decimalComma(_ value: Double, digits: Int = 1) -> String {
    String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
}

/// Compact chord symbols of the canvas: «G♯°», «B°», «C+», «Bø7».
func compactChordName(_ name: String) -> String {
    var s = name
    for (long, short) in [("m7♭5", "ø7"), ("dim7", "°7"), ("dim", "°"), ("aug", "+")] where s.hasSuffix(long) {
        s = String(s.dropLast(long.count)) + short
        break
    }
    return s
}

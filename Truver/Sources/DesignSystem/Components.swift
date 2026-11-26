import SwiftUI

/// Round graphite button (settings, reference tone, ± tempo). Canvas: `radial-gradient(circle at 50% 35%, #26282c,
/// #141518)` (to the farthest corner), 1 pt border white 10 %, `0 8px 18px` shadow, inner top highlight. The button
/// takes exactly `size` in the layout, like the canvas; the touch area still reaches 44 × 44 around it.
struct RoundIconButton: View {
    let icon: AppIcon
    var size: CGFloat = 40
    var iconSize: CGFloat = 18
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize)
                .frame(width: size, height: size)
                .background(RoundButtonFace(size: size))
        }
        .buttonStyle(PressableStyle())
        .frame(width: size, height: size)
        .touchArea(minimum: 44, size: size)
        .accessibilityLabel(label)
    }
}

/// The disc of the canvas round buttons (graphite face, hairline, inner top highlight, drop shadow).
struct RoundButtonFace: View {
    let size: CGFloat

    var body: some View {
        // `circle at 50% 35%` reaches the farthest corner of the box: √(0.5² + 0.65²) · size.
        Circle().fill(RadialGradient(colors: [Theme.panelHigh, Theme.panel], center: UnitPoint(x: 0.5, y: 0.35),
                                     startRadius: 0, endRadius: size * 0.82))
            .overlay(Circle().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            // inset 0 1px 0 rgba(255,255,255,0.08): a hairline of light on the top edge, inside the border.
            .overlay(Circle().inset(by: 1).trim(from: 0.55, to: 0.95).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 9, y: 8)
    }
}

extension View {
    /// Extends the hit area to at least `minimum` points without changing the layout (the canvas lays out 36 and 40 pt
    /// buttons at their visual size).
    func touchArea(minimum: CGFloat, size: CGFloat) -> some View {
        let extra = max(0, (minimum - size) / 2)
        return padding(extra).contentShape(Rectangle()).padding(-extra)
    }
}

/// Big ivory round button (start / stop: 88 pt, 100 pt with large text).
struct PrimaryRoundButton: View {
    let icon: AppIcon
    var size: CGFloat = 88
    var iconSize: CGFloat = 30
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize, color: Theme.background)
                .frame(width: size, height: size)
                // inset 0 1px 0 rgba(255,255,255,0.08) on ivory: invisible, so only the drop shadow. The shadow is on the
                // disc alone: on the whole label it would also cast the icon's grey halo onto the ivory.
                .background(Circle().fill(Theme.primaryFill).shadow(color: .black.opacity(0.6), radius: 9, y: 8))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Small header chip ("Микрофон", preset name). Canvas: a `<span>` 32 pt high plus a 1 pt border outside it — 34 pt
/// in all, radius 16, padding 12, icon 14 (the metronome's chevron 12) and 6 pt gap, 12 medium.
struct HeaderChip: View {
    let text: String
    var icon: AppIcon?
    var tint: Color?
    var iconSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Icon(icon, size: iconSize, color: tint ?? Theme.textTertiary) }
            Text(text).font(Typo.chip).lineLimit(1)
        }
        .foregroundStyle(tint ?? Theme.textBody)
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.map { $0.opacity(0.08) } ?? Theme.fill))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.map { $0.opacity(0.45) } ?? Theme.hairlineStrong, lineWidth: 1))
    }
}

/// Ivory capsule for the main action of a state ("Включить микрофон", "Продолжить").
struct PrimaryButton: View {
    let title: String
    var icon: AppIcon?
    var height: CGFloat = 50
    var maxWidth: CGFloat? = 260
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 18, color: Theme.background) }
                Text(title).font(Typo.button)
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 18)
            .frame(maxWidth: maxWidth ?? .infinity, minHeight: height)
            .background(Capsule(style: .circular).fill(Theme.primaryFill))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Segmented control (Авто / Ручной / Хром.) — the canvas tray: 30 pt segments (radius 15), padding 3, 1 pt border
/// inside, radius 18 — 38 pt in all. Same as `Segments` at its regular size.
struct SegmentedPill<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Segments(options: options, selection: $selection)
    }
}

/// Screen header of the canvas (`left 20, top 50, width 350`, a 44 pt row): title 26 semibold (−0.02 em, line
/// height 1.15) with an optional 12 pt subtitle under it, chips and the 40 pt settings button on the right, 8 apart.
/// On the reference phone the safe area ends at 47, so the row starts 3 pt below it.
struct ScreenHeader<Trailing: View>: View {
    @Environment(AppModel.self) private var app
    let title: String
    let leading: AnyView?
    /// Second line under the title (canvas «Гриф и гаммы» / «8-струнная · Стандарт F♯»): 12 pt, tertiary.
    let subtitle: String?
    let trailing: () -> Trailing
    /// CSS `line-height: 1.15` on 26 pt Inter: the line box is 29.9, the text's own line 31.48 — 0.79 pt less on each side.
    @ScaledMetric(relativeTo: .title2) private var titleHalfLeading: CGFloat = 0.79

    static var topPadding: CGFloat { 3 }

    init(title: String, leading: AnyView? = nil, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.leading = leading
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Typo.screenTitle).foregroundStyle(Theme.textPrimary).kerning(-0.52).lineLimit(1)
                    .padding(.vertical, -titleHalfLeading)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let leading { leading }
            Spacer(minLength: 0)
            trailing()
            RoundIconButton(icon: .gear, label: "Настройки") { app.showSettings = true }
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.top, Self.topPadding)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, leading: nil, subtitle: subtitle, trailing: { EmptyView() })
    }
}


/// Card group with rows (lists in settings, journal, onboarding).
struct CardGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(.horizontal, 4)
            }
            // Canvas card: radius 16, 1 pt border inside (white 8 %), card fill, `overflow: hidden`.
            // The rows sit inside the border, as in CSS (`border: 1px` around the content box).
            VStack(spacing: 0) { content() }
                .padding(1)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}

/// A row of a card (canvas: padding 0 16, gap 10, title 15 body, subtitle 12 tertiary 2 pt below, trailing 14
/// secondary, divider white 6 %). `minHeight` — the canvas uses 52, 56, 58 and 60.
struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsDivider = true
    var minHeight: CGFloat = 56
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.row).foregroundStyle(Theme.textBody)
                if let subtitle { Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary) }
            }
            Spacer(minLength: 8)
            trailing().font(Typo.inter(14)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: minHeight)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }
}

/// A small card with a caption and a big light number (journal summary).
struct StatCard: View {
    let caption: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(Typo.caption).foregroundStyle(Theme.textTertiary)
            Text(value).font(Typo.inter(28, .light)).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)   // 14 + the 1 pt border
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(13)   // 12 + the 1 pt border
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

/// Toast at the top: slides in by 14 pt, stays 3 s, a new one replaces the old in place (motion spec).
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.inter(13, .medium))
            .foregroundStyle(Theme.textBody)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Capsule().fill(Theme.panel))
            .overlay(Capsule().stroke(Theme.hairlineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 8)
            .padding(.horizontal, 20)
    }
}

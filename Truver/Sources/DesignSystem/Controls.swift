import SwiftUI

// Controls of the canvas sheets: switch, radio, value stepper, segments, chips, toast, sheet chrome.

/// iOS-size switch (51 × 31): ivory track when on, graphite knob.
struct ToggleSwitch: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            withAnimation(Motion.out(Motion.Duration.quick)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.accent : Color.white.opacity(0.14))
                Circle().fill(isOn ? Theme.panel : Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                    .padding(2)
            }
            .frame(width: 51, height: 31)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "включено" : "выключено")
        .accessibilityAddTraits(.isButton)
    }
}

/// Radio mark (20 pt ring, 10 pt dot).
struct RadioMark: View {
    let selected: Bool

    var body: some View {
        Circle()
            .strokeBorder(selected ? Theme.textPrimary : Color.white.opacity(0.3), lineWidth: 1.5)
            .frame(width: 20, height: 20)
            .overlay { if selected { Circle().fill(Theme.textPrimary).frame(width: 10, height: 10) } }
    }
}

/// A row with a radio mark: title 15, optional subtitle 12 (min height 56, padding 6 × 16).
struct RadioRow: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    var showsDivider = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RadioMark(selected: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.inter(15)).foregroundStyle(Theme.textPrimary)
                    if let subtitle { Text(subtitle).font(Typo.caption).foregroundStyle(Theme.textTertiary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) { if showsDivider { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «− 120 +» inside a row: 36 pt round buttons, value 16 pt, min width 44.
struct ValueStepper: View {
    let value: String
    var canDecrement = true
    var canIncrement = true
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            RoundIconButton(icon: .minus, size: 36, iconSize: 16, label: "Меньше", action: decrement)
                .disabled(!canDecrement).opacity(canDecrement ? 1 : 0.4)
            Text(value).font(Typo.inter(16)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                .frame(minWidth: 44)
            RoundIconButton(icon: .plus, size: 36, iconSize: 16, label: "Больше", action: increment)
                .disabled(!canIncrement).opacity(canIncrement ? 1 : 0.4)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Segmented control of the canvas: segments 30 pt (radius 15) in a tray with padding 3, a 1 pt border inside and
/// radius 18 — 38 pt in all (`.regular` and `.compact` are the same since the corrected canvas). `.large` — 38 pt
/// segments, radius 22 (large-text boards).
struct Segments<Value: Hashable>: View {
    enum Size { case regular, compact, large }
    let options: [(Value, String)]
    @Binding var selection: Value
    var size: Size = .regular

    var body: some View {
        let height: CGFloat = size == .large ? 38 : 30
        let radius: CGFloat = size == .large ? 22 : 18
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    withAnimation(Motion.out(Motion.Duration.quick)) { selection = value }
                } label: {
                    Text(title)
                        .font(selected ? Typo.segmentSelected : Typo.segment)
                        .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background(Capsule(style: .circular).fill(selected ? Theme.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: radius).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Chip of the canvas. `.regular`: a `<span>` 32 pt + 1 pt border outside — 34 pt, radius 16, 12 medium;
/// `.large`: a 36 pt button (border inside), radius 18, 14 medium (metronome chips). Padding 12 + border, gap 6.
/// Variants: plain, emphasized (ivory ring and tint), positive (green), muted.
struct Chip: View {
    enum Style { case plain, emphasized, positive, muted }
    enum Size { case regular, large }
    let text: String
    var icon: AppIcon?
    var style: Style = .plain
    var size: Size = .regular

    var body: some View {
        let large = size == .large
        HStack(spacing: 6) {
            if let icon { Icon(icon, size: 14, lineWidth: icon == .check ? 2 : 1.6, color: iconColor) }
            Text(text).font(large ? Typo.inter(14, .medium) : Typo.chip).lineLimit(1)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 13)
        .frame(height: large ? 36 : 34)
        .background(RoundedRectangle(cornerRadius: large ? 18 : 16).fill(fillColor))
        .overlay(RoundedRectangle(cornerRadius: large ? 18 : 16).strokeBorder(borderColor, lineWidth: 1))
        .fixedSize()
    }

    private var fillColor: Color {
        switch style {
        case .emphasized: return Color(hex: 0xf6f3ec, opacity: 0.1)
        case .positive: return Theme.inTune.opacity(0.08)
        default: return Theme.fill
        }
    }

    private var textColor: Color {
        switch style {
        case .plain: return Theme.textBody
        case .emphasized: return Theme.textPrimary
        case .positive: return Theme.inTune
        case .muted: return Theme.textSecondary
        }
    }

    private var iconColor: Color {
        switch style {
        case .emphasized: return Theme.beat
        case .positive: return Theme.inTune
        default: return Theme.textTertiary
        }
    }

    private var borderColor: Color {
        switch style {
        case .emphasized: return Color(hex: 0xf6f3ec, opacity: 0.55)
        case .positive: return Theme.inTune.opacity(0.45)
        default: return Theme.hairlineStrong
        }
    }
}

/// Toast of the canvas: 16 pt radius, icon 16 + text 13 medium, padding 11 × 16.
struct DesignToast: View {
    var icon: AppIcon?
    var iconColor: Color = Theme.beat
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            if let icon { Icon(icon, size: 16, lineWidth: icon == .check ? 2 : 1.6, color: icon == .check ? Theme.inTune : iconColor) }
            Text(text).font(Typo.inter(13, .medium)).foregroundStyle(Theme.textBody).fixedSize(horizontal: false, vertical: true)
        }
        // Canvas padding 11 × 16 plus the 1 pt border, which the app draws inside the shape.
        .padding(.horizontal, 17).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x26282d, opacity: 0.96))
            .shadow(color: .black.opacity(0.6), radius: 15, y: 14))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

/// Section caption above a card in sheets (12 pt, padding 0 4 6 4).
struct SectionCaption: View {
    let text: String
    var body: some View {
        Text(text).font(Typo.caption).foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A card without a title (rows inside).
struct Card<Content: View>: View {
    var radius: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        // The rows sit inside the border, as in CSS (`border: 1px` around the content box).
        VStack(spacing: 0) { content() }
            .padding(1)
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.cardFill))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: Sheet

/// Sheet of the canvas: dim 0.62 over everything, panel with 26 pt top corners, grabber, title 18 semibold and a
/// round close button; an optional ivory action at the bottom over a fade. Heights come from the canvas (844 − top).
struct DesignSheet<Content: View, Footer: View>: View {
    let title: String
    let height: CGFloat
    /// Landscape: a tall sheet fits the screen (the header of «Ритм» ended up above the screen — UX check).
    @Environment(\.isPhoneLandscape) private var landscape
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.22)).frame(width: 40, height: 5).padding(.bottom, 12)
            HStack {
                Text(title).font(Typo.inter(18, .semibold)).foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                RoundIconButton(icon: .close, size: 36, iconSize: 16, label: "Закрыть", action: close)
            }
            .frame(height: 40)
            .padding(.bottom, 10)
            ScrollView {
                content().padding(.bottom, Footer.self == EmptyView.self ? 34 : 110)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, 11)   // border-top 1 + padding 10
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: landscape ? min(height, 360) : height, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1d1f23), Theme.panel], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.6), radius: 25, y: -20)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .bottom) {
            if Footer.self != EmptyView.self {
                HStack(spacing: 10) { footer() }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 34)
                    .background(LinearGradient(stops: [.init(color: Theme.panel.opacity(0), location: 0), .init(color: Theme.panel, location: 0.3)],
                                               startPoint: .top, endPoint: .bottom))
            }
        }
        .offset(y: max(0, drag))
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in if value.translation.height > 120 || value.predictedEndTranslation.height > 260 { close() } }
        )
    }
}

extension DesignSheet where Footer == EmptyView {
    init(title: String, height: CGFloat, close: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, height: height, close: close, content: content, footer: { EmptyView() })
    }
}

/// Ivory action button of sheets and states (50 pt by default — the canvas sheet footers).
struct SheetButton: View {
    let title: String
    var icon: AppIcon?
    var height: CGFloat = 50
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 18, color: Theme.background) }
                Text(title).font(Typo.button)
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule(style: .circular).fill(Theme.primaryFill))
        }
        .buttonStyle(PressableStyle())
    }
}

/// System-like alert of the canvas (290 wide, 22 radius, #202227) with a text field.
struct TextFieldAlert: View {
    let title: String
    @Binding var text: String
    let cancel: () -> Void
    let save: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(hex: 0x030304, opacity: 0.66).ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text(title).font(Typo.inter(17, .semibold)).foregroundStyle(Theme.textPrimary)
                    TextField("", text: $text)
                        .font(Typo.inter(16)).foregroundStyle(Theme.textPrimary).tint(Theme.flat)
                        .focused($focused)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.flat, lineWidth: 1.5))
                        .submitLabel(.done)
                        .onSubmit(save)
                }
                .padding(20)
                HStack(spacing: 0) {
                    Button(action: cancel) {
                        Text("Отмена").font(Typo.inter(17)).foregroundStyle(Theme.textBody).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    Rectangle().fill(Theme.hairlineStrong).frame(width: 1, height: 50)
                    Button(action: save) {
                        Text("Сохранить").font(Typo.inter(17, .semibold)).foregroundStyle(Theme.textPrimary).frame(maxWidth: .infinity, minHeight: 50)
                    }
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairlineStrong).frame(height: 1) }
            }
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x202227)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .onAppear { focused = true }
    }
}

/// Alert of the canvas (290 wide, radius 22, #202227): title 17 semibold, message 13; two buttons side by side,
/// three or more stacked; destructive ones in red (#ff6b5e).
struct DesignAlert: View {
    struct Action: Identifiable {
        enum Role { case normal, preferred, destructive }
        let title: String
        var role: Role = .normal
        let perform: () -> Void
        var id: String { title }
    }

    let title: String
    var message: String?
    let actions: [Action]
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0x030304, opacity: 0.66).ignoresSafeArea().onTapGesture(perform: dismiss)
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(title).font(Typo.inter(17, .semibold)).foregroundStyle(Theme.textPrimary)
                    // line-height 1.4 on 13 pt
                    if let message { Text(message).font(Typo.inter(13)).foregroundStyle(Theme.textSecondary).lineSpacing(2.47) }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)
                if actions.count == 2 {
                    HStack(spacing: 0) {
                        button(actions[0])
                        Rectangle().fill(Theme.hairlineStrong).frame(width: 1, height: 50)
                        button(actions[1])
                    }
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairlineStrong).frame(height: 1) }
                } else {
                    ForEach(actions) { action in
                        button(action).overlay(alignment: .top) { Rectangle().fill(Theme.hairlineStrong).frame(height: 1) }
                    }
                }
            }
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0x202227)))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.7), radius: 35, y: 30)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func button(_ action: Action) -> some View {
        Button(action: action.perform) {
            Text(action.title)
                .font(Typo.inter(17, action.role == .preferred ? .semibold : .regular))
                .foregroundStyle(action.role == .destructive ? Color(hex: 0xff8a80) : (action.role == .preferred ? Theme.textPrimary : Theme.textBody))
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

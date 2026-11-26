import SwiftUI

/// Page header of «О Truver» and «Спасибо» (canvas): back button 40, gap 10, title 17 medium, 44 pt row 50 pt from
/// the top of the screen (3 below the safe area); no hairline under it.
struct ThanksHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RoundIconButton(icon: .chevronLeft, label: "Назад", action: back)
            Text(title).font(Typo.inter(17, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.top, 3)
    }
}

/// The canvas sheet chrome for this page (dim 0.62, panel with 26 pt corners, grabber, title 18 semibold, optional
/// round close button, optional footer over a fade). Like `DesignSheet`, but the update notices have no close button.
struct ThanksSheetPanel<Content: View, Footer: View>: View {
    let title: String
    let height: CGFloat
    var close: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.22)).frame(width: 40, height: 5).padding(.bottom, 12)
            HStack {
                Text(title).font(Typo.inter(18, .semibold)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer()
                if let close { RoundIconButton(icon: .close, size: 36, iconSize: 16, label: "Закрыть", action: close) }
            }
            .frame(height: 40)
            .padding(.bottom, 10)
            ScrollView {
                content().padding(.bottom, Footer.self == EmptyView.self ? 34 : 110)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, 11)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
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
                .onEnded { value in
                    if value.translation.height > 120 || value.predictedEndTranslation.height > 260 { close?() }
                }
        )
    }
}

extension ThanksSheetPanel where Footer == EmptyView {
    init(title: String, height: CGFloat, close: (() -> Void)?, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, height: height, close: close, content: content, footer: { EmptyView() })
    }
}

/// Presents a sheet of this page over a screen, like the app's `SheetHost`: the dim fades in (280 ms), the panel
/// rises 60 pt with a fade (340 ms).
struct ThanksSheetHost<Item: Equatable, Sheet: View>: View {
    let item: Item?
    var dim: Color = Theme.sheetDim
    let dismiss: () -> Void
    @ViewBuilder var sheet: (Item) -> Sheet

    var body: some View {
        ZStack(alignment: .bottom) {
            if item != nil {
                dim.ignoresSafeArea()
                    .onTapGesture(perform: dismiss)
                    .accessibilityElement()
                    .accessibilityLabel("Закрыть лист")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { dismiss() }
                    .transition(.opacity.animation(.easeOut(duration: 0.28)))
            }
            if let item {
                sheet(item)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.asymmetric(insertion: .offset(y: 60).combined(with: .opacity), removal: .move(edge: .bottom)))
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { dismiss() }
            }
        }
        .animation(Motion.out(0.34), value: item)
    }
}

/// A row of the canvas cards: title 15 body (+ subtitle 12 tertiary), trailing 14 secondary + chevron, divider.
struct ThanksRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// Canvas rows are `min-height` + the 1 pt bottom border (content-box): 52 → 53.
    var minHeight: CGFloat = 53
    var divider = true
    var action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            CardRow(title: title, subtitle: subtitle, showsDivider: divider, minHeight: minHeight) {
                HStack(spacing: 8) {
                    trailing()
                    Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

extension ThanksRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, minHeight: CGFloat = 53, divider: Bool = true, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, minHeight: minHeight, divider: divider, action: action, trailing: { EmptyView() })
    }
}

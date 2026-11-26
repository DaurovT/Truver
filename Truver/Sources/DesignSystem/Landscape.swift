import SwiftUI

extension EnvironmentValues {
    /// iPhone held sideways: the canvas landscape boards (844 × 390) replace the portrait screens, and the tab bar
    /// with the tuning pill hides (canvas «Тюнер/Метроном/Гриф — альбом»).
    var isPhoneLandscape: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }
}

/// Lays content out in the canvas landscape board's points (844 × 390, top-left origin) and scales it to fit the
/// screen, edge to edge: on an 844 × 390 phone the result matches the board one to one.
struct LandscapeCanvas<Content: View>: View {
    static var size: CGSize { CGSize(width: 844, height: 390) }
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.size.width, proxy.size.height / Self.size.height)
            content()
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        #if os(iOS)
        // The boards run to the bottom edge: the home indicator dims until touched.
        .persistentSystemOverlays(.hidden)
        #endif
    }
}

extension View {
    /// Places a block at the board's point (x, y), optionally with the board's width.
    func board(x: CGFloat, y: CGFloat, width: CGFloat? = nil) -> some View {
        frame(width: width, alignment: .topLeading)
            .offset(x: x, y: y)
    }
}

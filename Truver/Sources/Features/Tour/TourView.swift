import SwiftUI
#if os(iOS)
import UIKit
#endif

/// «Знакомство» (canvas Tour1Tuner … Tour4Practice): four cards after the welcome screen, before the instrument.
/// «N из 4» and «Пропустить» at the top (none on the last card), a 280 × 420 miniature of the screen at 104 (radius 30,
/// white 10 % border, shadow `0 24px 60px` black 55 %), the title 26 semibold and the text 15 / 1.5 at 552, the dots
/// and the 56 pt button 128 pt above the bottom. Steps slide left 320 ms (ease-out), the dots stretch in 200 ms.
///
/// The miniatures are the canvas renders of the boards' inner screens (`Resources/Tour/*.jpg`, 3×): the tour shows the
/// app before an instrument is chosen, with the canvas's sample states (8-string fretboard, «Риф 7/8» speeding up,
/// two weeks of practice), so pictures rather than live screens.
struct TourView: View {
    enum Mode {
        /// After the welcome screen: the last card leads to the instrument.
        case firstRun
        /// Settings → «Обучение» → «Знакомство с приложением».
        case replay
    }

    let mode: Mode
    let finish: () -> Void
    @State private var page: Int
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(mode: Mode, page: Int = 0, finish: @escaping () -> Void) {
        self.mode = mode
        self.finish = finish
        _page = State(initialValue: min(max(page, 0), Self.pages.count - 1))
    }

    struct Page {
        let image: String
        let title: String
        let text: String
    }

    static let pages: [Page] = [
        Page(image: "tour-tuner", title: "Настройте гитару за минуту",
             text: "Сыграйте струну — Truver покажет ноту и подскажет, подтянуть её или ослабить. Для 6, 7, 8 и 9 струн и любого строя"),
        Page(image: "tour-fret", title: "Гаммы и аккорды на вашем грифе",
             text: "Выберите гамму — её ноты появятся на всех ладах, сразу в вашем строе. Нажмите на ноту, чтобы построить от неё аккорд или прогрессию"),
        Page(image: "tour-metro", title: "Метроном, с которым растёт темп",
             text: "Сам поднимает скорость, умеет пропускать доли и подсказывает, где вы спешите или отстаёте"),
        Page(image: "tour-practice", title: "Прогресс считается сам",
             text: "Минуты, дни подряд и ваш потолок темпа. Бесплатно, без регистрации и рекламы, звук не записывается"),
    ]

    private var isLast: Bool { page == Self.pages.count - 1 }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ScreenBackground()
                ZStack(alignment: .topLeading) {
                    card(Self.pages[page], width: w)
                }
                .id(page)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                                                  removal: .move(edge: forward ? .leading : .trailing)))
                .frame(width: w, height: h, alignment: .topLeading)
                header.frame(width: w - 40).offset(x: 20, y: 50)
                VStack(spacing: 18) {
                    dots
                    PrimaryButton(title: isLast ? (mode == .firstRun ? "Выбрать инструмент" : "Готово") : "Дальше", height: 56, maxWidth: nil) {
                        if isLast { finish() } else { go(page + 1) }
                    }
                }
                .frame(width: w - 40)
                .offset(x: 20, y: h - (844 - 716))
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -40, !isLast { go(page + 1) }
                if value.translation.width > 40, page > 0 { go(page - 1) }
            })
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private func go(_ next: Int) {
        forward = next > page
        withAnimation(reduceMotion ? Motion.out(Motion.Duration.base) : Motion.out(Motion.Duration.move)) { page = next }
    }

    /// «1 из 4» 13 tertiary · «Пропустить» 15 secondary (padding 10 0 10 20) in a 44 pt row.
    private var header: some View {
        HStack(spacing: 0) {
            Text("\(page + 1) из \(Self.pages.count)").font(Typo.inter(13)).foregroundStyle(Theme.textTertiary)
                .accessibilityLabel("Карточка \(page + 1) из \(Self.pages.count)")
            Spacer(minLength: 8)
            if !isLast {
                Button(action: finish) {
                    Text("Пропустить").font(Typo.inter(15)).foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 10).padding(.leading, 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 44)
    }

    /// Dots: the current 18 × 6 ivory, the others 6 × 6 white 20 %, 6 apart.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pages.count, id: \.self) { i in
                Capsule(style: .circular).fill(i == page ? Theme.textPrimary : Color.white.opacity(0.2))
                    .frame(width: i == page ? 18 : 6, height: 6)
            }
        }
        .animation(Motion.out(0.2), value: page)
        .accessibilityHidden(true)
    }

    private func card(_ p: Page, width w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TourMiniature(image: p.image)
                .offset(x: (w - 280) / 2, y: 104)
            // Title 26 semibold (−0.02 em, normal line height) and the text 15 / 1.5, 10 apart, centred in 334.
            VStack(spacing: 10) {
                Text(lines(p.title, weight: .semibold, size: 26, kerning: -0.52))
                    .font(Typo.inter(26, .semibold)).kerning(-0.52).foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lines(p.text, weight: .regular, size: 15, kerning: 0))
                    .font(Typo.inter(15)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(15 * 1.5 - 15 * 1.2109)
                    .padding(.vertical, (15 * 1.5 - 15 * 1.2109) / 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: w - 56)
            .offset(x: 28, y: 552)
            .accessibilityElement(children: .combine)
        }
    }

    /// Browser line breaks at the default text size (SwiftUI moves a lone last word down with the one before it).
    private func lines(_ text: String, weight: Typo.Weight, size: CGFloat, kerning: CGFloat) -> String {
        guard typeSize == .large else { return text }
        return TourText.greedy(text, font: weight.rawValue, size: size, kerning: kerning, width: 334)
    }
}

/// The miniature of a screen in its rounded frame.
struct TourMiniature: View {
    let image: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .circular).fill(Color(hex: 0x0d0e10))
                .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
            if let ui = TourImages.image(image) {
                Image(uiImage: ui).resizable().interpolation(.high)
                    .frame(width: 278, height: 418)
                    .clipShape(RoundedRectangle(cornerRadius: 29, style: .circular))
            }
            RoundedRectangle(cornerRadius: 30, style: .circular).strokeBorder(Theme.hairlineStrong, lineWidth: 1)
        }
        .frame(width: 280, height: 420)
        .accessibilityHidden(true)
    }
}

enum TourImages {
    #if os(iOS)
    typealias Image = UIImage
    #else
    typealias Image = NSImage
    #endif
    @MainActor private static var cache: [String: Image] = [:]

    @MainActor static func image(_ name: String) -> Image? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"), let data = try? Data(contentsOf: url) else { return nil }
        #if os(iOS)
        let image = UIImage(data: data, scale: 3)
        #else
        let image = NSImage(data: data)
        #endif
        cache[name] = image
        return image
    }
}

#if os(macOS)
extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}
#endif

enum TourText {
    /// Greedy line breaks with letter spacing (the canvas wraps like a browser).
    static func greedy(_ text: String, font name: String, size: CGFloat, kerning: CGFloat, width: CGFloat) -> String {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let string = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): kerning,
        ])
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let ns = text as NSString
        var lines: [String] = []
        var start = 0
        while start < ns.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            lines.append(ns.substring(with: NSRange(location: start, length: count)).trimmingCharacters(in: .whitespaces))
            start += count
        }
        return lines.joined(separator: "\n")
    }
}

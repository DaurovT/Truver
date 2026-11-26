import SwiftUI
import CoreImage.CIFilterBuiltins

/// «Поделиться Truver» (canvas ShareSheet): the link card, four targets (Сообщения, Telegram, Instagram, «Ещё» —
/// the system share sheet), «Скопировать ссылку» and a QR code for a friend's camera.
struct ShareTruverSheet: View {
    let close: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var showsQR = false
    @State private var copied = false

    static var link: URL { UpdateCenter.storeURL }
    static let title = "Truver — тюнер, гриф и метроном"
    static var message: String { "\(title): \(link.absoluteString)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TruverAppIconArt(size: 44, radius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title).font(Typo.inter(15, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text("для 6–9 струн · бесплатно · apps.apple.com").font(Typo.inter(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoundIconButton(icon: .close, size: 30, iconSize: 14, label: "Закрыть", action: close)
            }
            .padding(.bottom, 15)   // 14 + the border
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            if showsQR {
                qr
            } else {
                HStack(spacing: 0) {
                    target("Сообщения", tile: messagesTile) { open("sms:&body=\(Self.encoded(Self.message))") }
                    Spacer(minLength: 0)
                    target("Telegram", tile: AnyView(PlatformTile(kind: .telegram, size: 58, radius: 16, glyph: 39))) {
                        open("https://t.me/share/url?url=\(Self.encoded(Self.link.absoluteString))&text=\(Self.encoded(Self.title))")
                    }
                    Spacer(minLength: 0)
                    target("Instagram", tile: AnyView(PlatformTile(kind: .instagram, size: 58, radius: 16, glyph: 39))) {
                        // Instagram takes no links from other apps: copy it and open Instagram to paste.
                        copy()
                        open("https://instagram.com")
                    }
                    Spacer(minLength: 0)
                    ShareLink(item: Self.link, subject: Text(Self.title), message: Text(Self.title)) {
                        targetLabel("Ещё", tile: moreTile)
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 4)
                Card {
                    Button(action: copy) {
                        CardRow(title: copied ? "Ссылка скопирована" : "Скопировать ссылку", minHeight: 51) {
                            Icon(copied ? .check : .plus, size: 16, color: Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation(Motion.out(Motion.Duration.base)) { showsQR = true } } label: {
                        CardRow(title: "Показать QR-код", subtitle: "чтобы друг навёл камеру", minHeight: 59) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 414, alignment: .top)
        .background(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .circular).fill(Color(hex: 0x1f2125)).ignoresSafeArea(edges: .bottom))
    }

    private var messagesTile: AnyView {
        AnyView(RoundedRectangle(cornerRadius: 14, style: .circular)
            .fill(cssLinearGradient(160, [.init(color: Color(hex: 0x5fe07a), location: 0), .init(color: Color(hex: 0x2bb44a), location: 1)]))
            .overlay(ZStack {
                SVGPath(data: "M9 18V6l10-2v12").stroke(.white, lineWidth: 1.6 * 26 / 24)
                SVGPath(data: "M4.8 18a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0M14.8 16a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0").stroke(.white, lineWidth: 1.6 * 26 / 24)
            }.frame(width: 26, height: 26))
            .frame(width: 58, height: 58))
    }

    private var moreTile: AnyView {
        AnyView(RoundedRectangle(cornerRadius: 14, style: .circular)
            .fill(cssLinearGradient(160, [.init(color: Color(hex: 0x6b7380), location: 0), .init(color: Color(hex: 0x3d434c), location: 1)]))
            .overlay(SVGPath(data: "M12 19V5M6 11l6-6 6 6").stroke(.white, style: StrokeStyle(lineWidth: 1.6 * 26 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 26, height: 26))
            .frame(width: 58, height: 58))
    }

    private func target(_ title: String, tile: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) { targetLabel(title, tile: tile) }.buttonStyle(PressableStyle())
    }

    private func targetLabel(_ title: String, tile: AnyView) -> some View {
        VStack(spacing: 6) {
            tile
            Text(title).font(Typo.inter(11)).foregroundStyle(Theme.textBody).lineLimit(1).fixedSize()
        }
        .frame(width: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var qr: some View {
        VStack(spacing: 12) {
            if let image = Self.qrImage(Self.link.absoluteString) {
                image.interpolation(.none).resizable().scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(Color.white))
            }
            Text("Наведите камеру телефона на код").font(Typo.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("QR-код ссылки на Truver")
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.url = Self.link
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.link.absoluteString, forType: .string)
        #endif
        copied = true
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { openURL(url) }
    }

    static func encoded(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    static func qrImage(_ text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}

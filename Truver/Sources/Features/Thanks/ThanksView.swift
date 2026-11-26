import SwiftUI

/// «Спасибо» (canvas ThanksMusicians / ThanksPartners / ThanksOffline / ThanksLargeText): people who tell about
/// Truver, with their links. Real people only (`thanks.json`); the «Партнёры» segment appears once there are partners.
struct ThanksView: View {
    let back: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tab: Tab = .musicians
    @State private var profile: ThanksPerson?
    private var store: ThanksStore { .shared }

    enum Tab: Hashable { case musicians, partners }

    private var people: [ThanksPerson] { tab == .partners && !store.partners.isEmpty ? store.partners : store.musicians }

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                if typeSize.isAccessibilitySize {
                    HStack(spacing: 12) {
                        Text("Спасибо").font(Typo.fixed(34, .bold)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                        Spacer()
                        RoundIconButton(icon: .close, iconSize: 16, label: "Назад", action: back)
                    }
                    .frame(height: 44).padding(.horizontal, 20).padding(.top, 3)
                } else {
                    ThanksHeader(title: "Спасибо", back: back)
                }
                ScrollView {
                    Group {
                        if typeSize.isAccessibilitySize { largeList } else { list }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, store.offlineSince != nil ? 60 : 40)
                }
                .scrollIndicators(.hidden)
            }
            if let since = store.offlineSince {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Icon(.warning, size: 14, color: Theme.textSecondary)
                        Text("Нет интернета · показан список от \(ThanksStore.dayMonth(since))")
                            .font(Typo.inter(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 13)
                    .background(RoundedRectangle(cornerRadius: 12, style: .circular).fill(Color(red: 30 / 255, green: 31 / 255, blue: 35 / 255, opacity: 0.98)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 844 - 806 - 32.5)   // canvas: top 806 of 844
                }
                .ignoresSafeArea(edges: .bottom)
            }
            ThanksSheetHost(item: profile, dismiss: { profile = nil }) { person in
                ThanksProfileSheet(person: person) { profile = nil }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationBarBackButtonHidden()
        .onAppear {
            // Screenshot hooks: `-thanksTab partners`, `-thanksProfile <id>`.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-thanksTab"), i + 1 < args.count, args[i + 1] == "partners" { tab = .partners }
            if let i = args.firstIndex(of: "-thanksProfile"), i + 1 < args.count { profile = store.person(id: args[i + 1]) }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ThanksPick(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Спасибо, что рассказываете о Truver").font(Typo.inter(15, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Растём только благодаря вам").font(Typo.inter(12)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)   // 108 from the top of the screen
            if !store.partners.isEmpty {
                Segments(options: [(Tab.musicians, "Музыканты \(store.musicians.count)"), (Tab.partners, "Партнёры \(store.partners.count)")],
                         selection: $tab)
                    .padding(.top, 18)   // 166
            }
            VStack(spacing: 8) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    Button { profile = person } label: { card(person, index: index) }
                        .buttonStyle(PressableStyle(scale: 0.98))
                }
                tellUs
            }
            .padding(.top, store.partners.isEmpty ? 18 : 12)   // 216 under the segments
        }
    }

    /// A card 92 pt: avatar 48 with the gold badge, name 15 semibold, who it is 12, platform tiles 22.
    private func card(_ person: ThanksPerson, index: Int) -> some View {
        HStack(spacing: 14) {
            ThanksAvatar(person: person, index: index)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(Typo.inter(15, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(person.subtitle).font(Typo.inter(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(person.links) { PlatformTile(kind: $0.kind) }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Icon(.chevronRight, size: 16, color: Theme.textTertiary)
        }
        .padding(.horizontal, 15)
        .frame(height: 92)
        .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .circular).strokeBorder(Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ссылки")
    }

    /// «Рассказали о Truver? Добавим вас и ваши ссылки · Написать» in a dashed gold frame.
    private var tellUs: some View {
        HStack(spacing: 12) {
            ThanksPick(size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Рассказали о Truver?").font(Typo.inter(14, .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Добавим вас и ваши ссылки").font(Typo.inter(12)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            GraphiteCapsuleButton(title: "Написать") { openURL(AboutView.feedbackURL) }.fixedSize()
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(ThanksColors.gold.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .circular).inset(by: 0.5).stroke(ThanksColors.gold.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    /// Large text (canvas ThanksLargeText): cards in a column — avatar 56 and name 24, who it is 19, tiles 40.
    private var largeList: some View {
        VStack(spacing: 10) {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                Button { profile = person } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            ThanksAvatar(person: person, size: 56, font: 19, badge: 22, badgeGlyph: 16, index: index)
                            Text(person.name).font(Typo.fixed(24, .semibold)).foregroundStyle(Theme.textPrimary)
                        }
                        Text(person.subtitle).font(Typo.fixed(19)).foregroundStyle(Theme.textSecondary)
                            .lineSpacing(19 * 1.35 - 23.01).padding(.vertical, (19 * 1.35 - 23.01) / 2)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            ForEach(person.links) { PlatformTile(kind: $0.kind, size: 40, radius: 11, glyph: 27) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
                    .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(Theme.cardFill))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .circular).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
        .padding(.top, 22)   // 116 from the top of the screen
    }
}

/// «Музыкант» / «Партнёр» (canvas ThanksProfile): avatar 64, name 20, what we thank for, links as 56 pt rows with
/// «opens outside» arrows.
struct ThanksProfileSheet: View {
    let person: ThanksPerson
    let close: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ThanksSheetPanel(title: person.kind == nil ? "Музыкант" : "Партнёр", height: 544, close: close) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ThanksAvatar(person: person, size: 64, font: 22, badge: 26, badgeGlyph: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.name).font(Typo.inter(20, .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(person.subtitle).font(Typo.inter(13)).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let thanks = person.thanks {
                    HStack(spacing: 10) {
                        ThanksPick(size: 24)
                        Text(thanks).font(Typo.inter(14)).foregroundStyle(Theme.textBody)
                            .lineSpacing(14 * 1.4 - 16.95).padding(.vertical, (14 * 1.4 - 16.95) / 2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 13).padding(.horizontal, 15)
                    .background(RoundedRectangle(cornerRadius: 14, style: .circular).fill(ThanksColors.gold.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(ThanksColors.gold.opacity(0.25), lineWidth: 1))
                }
                if !person.links.isEmpty {
                    Card {
                        ForEach(person.links) { link in
                            Button {
                                if let url = URL(string: link.url) { openURL(url) }
                            } label: { linkRow(link) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Ссылки открываются в приложении площадки или в браузере").font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func linkRow(_ link: ThanksLink) -> some View {
        HStack(spacing: 12) {
            PlatformTile(kind: link.kind, size: 32, radius: 9, glyph: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(link.platform).font(Typo.inter(15, .medium)).foregroundStyle(Theme.textPrimary)
                Text(link.displayHandle).font(Typo.inter(12)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SVGPath(data: "M9 6h9v9M18 6L7 17").stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 2 * 14 / 24, lineCap: .round))
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 14)
        .frame(height: 57)   // 56 + the bottom border
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Откроется снаружи")
    }
}

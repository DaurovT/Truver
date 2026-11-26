import SwiftUI
import StoreKit

/// «О Truver» (canvas ThanksAbout / UpdateCheckFailed): the app icon and word mark, the update banner, «Спасибо»
/// and «Что нового», then share, feedback, rating and privacy. Opened from «Настройки → О Truver».
struct AboutView: View {
    let back: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var showPrivacy = false
    @State private var showThanks = false
    @State private var overlay: Overlay?
    private var store: ThanksStore { .shared }
    private var updates: UpdateCenter { .shared }

    enum Overlay: Equatable { case share, whatsNew }

    static let feedbackURL = URL(string: "mailto:?subject=Truver")!

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                ThanksHeader(title: "О Truver", back: back)
                ScrollView {
                    content.padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            // «Спасибо» slides in from the right over this page (as in Flutter): a `navigationDestination(isPresented:)`
            // inside the settings' path-driven stack did not push reliably.
            if showThanks {
                ThanksView { withAnimation(Motion.out(Motion.Duration.move)) { showThanks = false } }
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
            ThanksSheetHost(item: overlay, dim: overlay == .share ? Color(hex: 0x030304, opacity: 0.55) : Theme.sheetDim,
                            dismiss: { overlay = nil }) { item in
                switch item {
                case .share: ShareTruverSheet { overlay = nil }
                case .whatsNew: WhatsNewFromAbout { overlay = nil }
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
        .onAppear {
            // Screenshot hooks: `-settingsPage thanks` (the list), `-shareSheet`, `-thanksProfile <id>` (opens the list).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-shareSheet") { overlay = .share }
            if args.contains("-aboutWhatsNew") { overlay = .whatsNew }
            if UserDefaults.standard.string(forKey: "settingsPage") == "thanks" || args.contains("-thanksProfile") {
                showThanks = true
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                TruverAppIconArt(size: 96, radius: 21)
                Wordmark(size: 34).frame(height: 34)
            }
            .padding(.top, 18)       // 112 from the top of the screen
            .padding(.bottom, 46)    // cards from 300
            VStack(spacing: 14) {
                UpdateBanner()
                Card {
                    Button { withAnimation(Motion.out(Motion.Duration.move)) { showThanks = true } } label: { thanksRow }.buttonStyle(.plain)
                    let notes = updates.whatsNew
                    ThanksRow(title: "Что нового", action: { overlay = .whatsNew }) {
                        Text(notes?.version ?? updates.currentVersion)
                    }
                }
                Card {
                    ThanksRow(title: "Поделиться Truver") { overlay = .share }
                    ThanksRow(title: "Обратная связь") { openURL(Self.feedbackURL) }
                    // The system rating sheet works before the App Store page exists (no app id needed).
                    ThanksRow(title: "Оценить в App Store") { requestReview() }
                    ThanksRow(title: "Конфиденциальность", subtitle: "звук не записывается и не отправляется", minHeight: 61) { showPrivacy = true }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// «Спасибо · музыканты и партнёры» with the first three avatars (26 pt, overlapping by 8).
    private var thanksRow: some View {
        HStack(spacing: 12) {
            ThanksPick(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Спасибо").font(Typo.row).foregroundStyle(Theme.textBody)
                Text("музыканты и партнёры").font(Typo.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: -8) {
                ForEach(Array((store.musicians + store.partners).prefix(3).enumerated()), id: \.element.id) { index, person in
                    ThanksAvatar(person: person, size: 26, font: 9, badge: nil, index: index)
                }
            }
            Icon(.chevronRight, size: 16, color: Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 65)   // 64 + the bottom border
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// «Что нового» opened from «О Truver» (no footnote pointing back here).
private struct WhatsNewFromAbout: View {
    let close: () -> Void
    var body: some View {
        UpdateSheetBody(close: close)
    }
}

/// The «Что нового» sheet with its own close action (the shared `UpdateSheet` closes the launch notice).
private struct UpdateSheetBody: View {
    let close: () -> Void
    private var updates: UpdateCenter { .shared }

    var body: some View {
        let notes = updates.whatsNew
        ThanksSheetPanel(title: "Что нового в \(notes?.version ?? updates.currentVersion)", height: 374, close: nil) {
            ReleaseNotesList(notes: notes?.notes ?? []).frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            IvoryCapsuleButton(title: "Понятно", height: 54, fullWidth: true, action: close)
        }
    }
}

/// Privacy policy (6.2 «О приложении»): what the app does and does not do with data. Kept in the app, so it works
/// offline and before a web page exists.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, String)] = [
        ("Микрофон", "Truver слушает микрофон, только пока открыт тюнер. Звук анализируется на устройстве и сразу отбрасывается: он не записывается, не сохраняется и никуда не отправляется."),
        ("Данные", "Строи, пресеты метронома, журнал занятий и настройки хранятся только на этом устройстве. Удалите приложение — они удалятся вместе с ним."),
        ("Сеть", "Truver не обращается к интернету: нет аккаунтов, серверов и синхронизации."),
        ("Аналитика и реклама", "Нет аналитики, рекламы, трекинга и сторонних SDK. Мы не знаем, кто и как пользуется приложением."),
        ("Обратная связь", "Если вы напишете нам письмо, мы увидим только то, что вы в нём отправили, и используем это лишь для ответа."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.0) { title, text in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title).font(Typo.inter(15, .medium)).foregroundStyle(Theme.textPrimary)
                            Text(text).font(Typo.inter(14)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.panel)
            .navigationTitle("Конфиденциальность")
            .navigationBarTitleDisplayModeInline()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationBackground(Theme.panel)
    }
}

private extension View {
    @ViewBuilder func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

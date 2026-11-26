import SwiftUI

/// Update notices over the whole app (installed on the root in `TruverApp`): «Вышла версия» and «Что нового» sheets,
/// and «Нужно обновить Truver» over the tuner (canvas UpdateAvailable, UpdateWhatsNew, UpdateRequired).
struct UpdateNoticeHost: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    private var updates: UpdateCenter { .shared }

    var body: some View {
        ZStack {
            ThanksSheetHost(item: updates.sheet, dismiss: { updates.later() }) { sheet in
                UpdateSheet(kind: sheet, atLaunch: true)
            }
            if updates.showsRequired, app.settings.lastTab == .tuner, let info = updates.available {
                UpdateRequiredView(info: info) {
                    // «Метроном и гриф работают и без обновления»: the caption leads there.
                    app.settings.lastTab = .metronome
                }
                .transition(.opacity)
            }
        }
        .task {
            updates.launch { [app] in
                // Not while the metronome plays or tuning is in progress (canvas note), not over another sheet.
                !app.metronome.isPlaying && app.sheet == nil && !app.showOnboarding
            }
        }
    }
}

/// «Вышла версия 1.2» (with «Позже» / «Обновить») or «Что нового в 1.2» («Понятно»).
struct UpdateSheet: View {
    let kind: UpdateCenter.Sheet
    /// Shown by itself at launch (the footnote points to the full list) or opened from «О Truver».
    var atLaunch = true
    @Environment(\.openURL) private var openURL
    private var updates: UpdateCenter { .shared }

    var body: some View {
        switch kind {
        case .available:
            let info = updates.available ?? UpdateCenter.demo
            ThanksSheetPanel(title: "Вышла версия \(info.version)", height: 400, close: nil) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("У вас \(updates.currentVersion) · обновление \(info.sizeMB) МБ · бесплатно")
                        .font(Typo.inter(13)).foregroundStyle(Theme.textSecondary)
                    ReleaseNotesList(notes: info.notes)
                    Text("«Позже» — напомним через 3 дня.").font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, (16.8 - 14.53) / 2)   // line-height 1.4
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } footer: {
                GraphiteCapsuleButton(title: "Позже", height: 54, width: 120) { updates.later() }
                IvoryCapsuleButton(title: "Обновить", height: 54, fullWidth: true) {
                    updates.sheet = nil
                    openURL(UpdateCenter.storeURL)
                }
            }
        case .whatsNew:
            let notes = updates.whatsNew
            ThanksSheetPanel(title: "Что нового в \(notes?.version ?? updates.currentVersion)", height: 374, close: nil) {
                VStack(alignment: .leading, spacing: 16) {
                    ReleaseNotesList(notes: notes?.notes ?? [])
                    if atLaunch {
                        Text("Полный список — Настройки → О Truver → Что нового").font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } footer: {
                IvoryCapsuleButton(title: "Понятно", height: 54, fullWidth: true) { updates.sheet = nil }
            }
        }
    }
}

/// Green checks with «<b>Раздел:</b> изменение» (15, line height 1.4), 10 pt apart.
struct ReleaseNotesList: View {
    let notes: [ReleaseNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 10) {
                    SVGPath(data: "M5 12.5l4.5 4.5L19 7.5")
                        .stroke(Theme.inTune, style: StrokeStyle(lineWidth: 2 * 18 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                    (Text(note.section).font(Typo.inter(15, .semibold)).foregroundColor(Theme.textPrimary)
                     + Text(" " + note.text).font(Typo.inter(15)).foregroundColor(Theme.textBody))
                        // CSS line-height 1.4 (21 pt): the extra leading between lines and half of it above/below.
                        .lineSpacing(21 - 18.15)
                        .padding(.vertical, (21 - 18.15) / 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// «Нужно обновить Truver» (canvas UpdateRequired): only for a critical error; the metronome and the fretboard work.
struct UpdateRequiredView: View {
    let info: UpdateInfo
    var openMetronome: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()
            VStack(spacing: 18) {
                TruverAppIconArt(size: 88, radius: 19)
                Text("Нужно обновить Truver").font(Typo.inter(24, .semibold)).foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(info.requiredReason ?? "")
                    .font(Typo.inter(15)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    // CSS line-height 1.5 (22.5 pt).
                    .lineSpacing(22.5 - 18.15)
                    .padding(.vertical, (22.5 - 18.15) / 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 143)   // 190 from the top of the screen
            VStack(spacing: 10) {
                IvoryCapsuleButton(title: "Обновить в App Store", height: 56, fullWidth: true) { openURL(UpdateCenter.storeURL) }
                Button(action: openMetronome) {
                    Text("Метроном и гриф работают и без обновления").font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Открывает метроном")
            }
            .padding(.horizontal, 24)
            .padding(.top, 643)   // 690 from the top of the screen
        }
    }
}

/// The banner of «О Truver»: a newer version (gold) or a failed check (neutral) — canvas ThanksAbout and
/// UpdateCheckFailed. Nothing when the app is up to date.
struct UpdateBanner: View {
    @Environment(\.openURL) private var openURL
    private var updates: UpdateCenter { .shared }

    var body: some View {
        switch updates.state {
        case .available(let info), .required(let info):
            banner(title: "Доступна версия \(info.version)", subtitle: "У вас \(updates.currentVersion) (\(updates.currentBuild)) · \(info.sizeMB) МБ",
                   button: "Обновить", fill: ThanksColors.gold.opacity(0.08), border: ThanksColors.gold.opacity(0.35)) {
                openURL(UpdateCenter.storeURL)
            }
        case .failed:
            banner(title: "Не удалось проверить обновления", subtitle: "Нет связи с App Store · версия \(updates.currentVersion) (\(updates.currentBuild))",
                   button: "Повторить", fill: Color.white.opacity(0.04), border: Color.white.opacity(0.12)) {
                Task { await updates.check() }
            }
        default:
            EmptyView()
        }
    }

    private func banner(title: String, subtitle: String, button: String, fill: Color, border: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.inter(15, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(Typo.inter(12)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            IvoryCapsuleButton(title: button, action: action).fixedSize()
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .circular).strokeBorder(border, lineWidth: 1))
    }
}

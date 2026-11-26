import SwiftUI

/// Settings → «Обучение» (canvas SettingsHelp): the tour again, the hints switch and «Показать подсказки заново».
/// Its own header as on the board: back 40 and the title 17 medium 10 apart in the 44 pt row at 50, no hairline,
/// the card at 108 (rows 60 / 52 / 60 + their 1 pt bottom border), the note 14 under it (12 / 1.45, padding 0 4).
struct HelpSettingsPage: View {
    @Environment(AppModel.self) private var app
    let back: () -> Void
    @State private var showTour = false
    private var coach: CoachCenter { CoachCenter.shared }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScreenBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    RoundIconButton(icon: .chevronLeft, label: "Назад", action: back)
                    Text("Обучение").font(Typo.inter(17, .medium)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .frame(height: 44).padding(.horizontal, 20).padding(.top, 3)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Card {
                            Button { showTour = true } label: {
                                CardRow(title: "Знакомство с приложением", subtitle: "4 экрана · 30 секунд", minHeight: 61) {
                                    Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            CardRow(title: "Подсказки на экранах", minHeight: 53) {
                                ToggleSwitch(isOn: Binding(get: { coach.enabled }, set: { on in
                                    if on && !coach.armed { coach.arm() } else { coach.enabled = on }
                                }), label: "Подсказки на экранах")
                            }
                            Button {
                                coach.arm()
                                // Back to the app: the current screen shows its hints right away.
                                app.showSettings = false
                            } label: {
                                CardRow(title: "Показать подсказки заново", subtitle: "тюнер, гриф, табулатура, метроном, занятия", minHeight: 61) {
                                    Icon(.chevronRight, size: 16, color: Theme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Подсказка появляется один раз — когда вы впервые открываете раздел или функцию. Пропустить можно в любой момент.")
                            .font(Typo.caption).foregroundStyle(Theme.textTertiary)
                            .lineSpacing(12 * 1.45 - 12 * 1.2109)
                            .padding(.vertical, (12 * 1.45 - 12 * 1.2109) / 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showTour) { TourView(mode: .replay) { showTour = false } }
        #else
        .sheet(isPresented: $showTour) { TourView(mode: .replay) { showTour = false }.frame(minWidth: 420, minHeight: 760) }
        #endif
        .navigationBarBackButtonHidden()
    }
}

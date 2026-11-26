/// Port of Truver/Sources/Features/Tour/HelpSettingsPage.swift
///
/// Settings → «Обучение» (canvas SettingsHelp): the tour again, the hints switch and «Показать подсказки заново».
/// Its own header as on the board: back 40 and the title 17 medium 10 apart in the 44 pt row at 50, no hairline,
/// the card at 108 (rows 60 / 52 / 60 + their 1 pt bottom border), the note 14 under it (12 / 1.45, padding 0 4).
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'coach_marks.dart';

class HelpSettingsPage extends StatelessWidget {
  const HelpSettingsPage({super.key, required this.back});
  final VoidCallback back;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final padding = MediaQuery.paddingOf(context);
    const chevron = AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary);
    const spacing = 12 * 1.45 - 12 * interLineHeight;
    return Stack(
      children: [
        const Positioned.fill(child: ScreenBackground()),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: padding.top + 3),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    RoundIconButton(icon: AppIcon.chevronLeft, label: 'Назад', onTap: back),
                    const SizedBox(width: 10),
                    Semantics(header: true, child: Text('Обучение', style: Typo.inter(17, TypoWeight.medium, TruverColors.textPrimary))),
                  ],
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 40 + padding.bottom),
                  child: ListenableBuilder(
                    listenable: CoachCenter.instance,
                    builder: (context, _) {
                      final coach = CoachCenter.instance;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(children: [
                            Pressable(
                              scale: 1,
                              onTap: () => TourReplay.show.value = true,
                              child: const CardRow(title: 'Знакомство с приложением', subtitle: '4 экрана · 30 секунд', minHeight: 61, trailing: chevron),
                            ),
                            CardRow(
                              title: 'Подсказки на экранах',
                              minHeight: 53,
                              trailing: ToggleSwitch(
                                isOn: coach.enabled,
                                onChanged: (on) => on && !coach.armed ? coach.arm() : coach.enabled = on,
                                label: 'Подсказки на экранах',
                              ),
                            ),
                            Pressable(
                              scale: 1,
                              onTap: () {
                                coach.arm();
                                // Back to the app: the current screen shows its hints right away.
                                app.showSettings = false;
                              },
                              child: const CardRow(
                                title: 'Показать подсказки заново',
                                subtitle: 'тюнер, гриф, табулатура, метроном, занятия',
                                minHeight: 61,
                                trailing: chevron,
                              ),
                            ),
                          ]),
                          // − 1: SkParagraph sets the first line of a line-spaced paragraph 1 pt lower (onboarding).
                          const SizedBox(height: 14 + spacing / 2 - 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Подсказка появляется один раз — когда вы впервые открываете раздел или функцию. Пропустить можно в любой момент.',
                              textHeightBehavior: swiftLineSpacing,
                              style: lineSpaced(Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary), spacing),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// «Знакомство с приложением» from the settings: the tour over everything (`FeatureRegistry.overlays`).
abstract final class TourReplay {
  static final show = ValueNotifier(false);
}

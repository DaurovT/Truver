/// Port of Truver/Sources/Features/Settings/SettingsView.swift
///
/// Settings by the corrected canvas («Настройки», «Частота настройки (A4)», «Вход», «Громкость и задержка»,
/// «Обозначение нот», «Выход звука», «крупный шрифт»): a full screen with a pinned header and pages. Metronome sounds,
/// flash and the session timer open the metronome's sheets.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../metronome/metronome_sheets.dart' show SoundsSheet;
import '../root/root_view.dart' show isAccessibilityTextSize;
import '../tuner/tuner_controller.dart' show TunerChoice;
import 'about_view.dart';
import '../tour/help_settings_page.dart';

enum SettingsPage { noise, target, notation, a4, input, output, volume, about, help }

/// `Tuning.a4Range`.
const a4Range = (415.0, 466.0);

/// `SoundsSheet.title`: names of the click sounds (`ClickSounds.Kind`).
String clickSoundTitle(String kind) => SoundsSheet.title(kind);

/// `SettingsFormat`.
abstract final class SettingsFormat {
  /// «−55 дБ» with a typographic minus (canvas).
  static String decibels(double value) {
    final v = value.round();
    return '${v < 0 ? '−${-v}' : '$v'} дБ';
  }

  /// «440», «441,5» (decimal comma, no «,0»).
  static String hz(double value) =>
      value.roundToDouble() == value ? '${value.toInt()}' : value.toStringAsFixed(1).replaceAll('.', ',');
}

/// The canvas line spacing of 12 pt text with `line-height: 1.4` over SwiftUI's own line height.
const _captionLineSpacing = 12 * 0.4 - 2.5;

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  /// NavigationStack path; the last page slides in from the right.
  final List<SettingsPage> _path = [];

  @override
  void initState() {
    super.initState();
    // Screenshot hook: `-settingsPage noise|target|notation|a4|input|output|volume|about`.
    final raw = AppScope.read(context).args.value('-settingsPage');
    // `thanks`: «О Truver» opens «Спасибо» itself.
    final page = SettingsPage.values.where((p) => p.name == (raw == 'thanks' ? 'about' : raw)).firstOrNull;
    if (page != null) _path.add(page);
  }

  void _push(SettingsPage page) => setState(() => _path.add(page));

  void _pop() {
    if (_path.isNotEmpty) setState(() => _path.removeLast());
  }

  Widget _page(SettingsPage page) => switch (page) {
    SettingsPage.noise => SettingsPageFrame(title: 'Порог шума', back: _pop, child: const NoiseGatePage()),
    SettingsPage.target => SettingsPageFrame(title: 'Цель', back: _pop, child: const TargetPage()),
    SettingsPage.notation => SettingsPageFrame(title: 'Обозначение нот', back: _pop, child: const NotationPage()),
    SettingsPage.a4 => SettingsPageFrame(title: 'Частота настройки (A4)', back: _pop, child: const A4Page()),
    SettingsPage.input => SettingsPageFrame(
      title: 'Вход',
      back: _pop,
      child: InputPage(openNoise: () => _push(SettingsPage.noise)),
    ),
    SettingsPage.output => SettingsPageFrame(
      title: 'Выход звука',
      back: _pop,
      child: OutputPage(openCheck: () => _push(SettingsPage.volume)),
    ),
    SettingsPage.volume => SettingsPageFrame(title: 'Громкость и задержка', back: _pop, child: const VolumePage()),
    SettingsPage.about => AboutView(back: _pop),
    SettingsPage.help => HelpSettingsPage(back: _pop), // «Обучение» (features/tour)
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final large = isAccessibilityTextSize(context);
    return PopScope(
      canPop: false,
      // Android back: the page, then the cover (the iOS swipe-back / back button).
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // The tour replayed from «Обучение» lies above the settings: back closes it first.
        if (TourReplay.show.value) {
          TourReplay.show.value = false;
          return;
        }
        if (_path.isNotEmpty) {
          _pop();
        } else {
          app.showSettings = false;
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: SettingsPageFrame(
              title: 'Настройки',
              style: large ? SettingsFrameStyle.large : SettingsFrameStyle.regular,
              fade: !large,
              back: () => app.showSettings = false,
              child: _Main(push: _push, large: large),
            ),
          ),
          for (var i = 0; i < _path.length; i++)
            Positioned.fill(
              child: _PushedPage(key: ValueKey('${_path[i].name}$i'), child: _page(_path[i])),
            ),
        ],
      ),
    );
  }
}

/// A NavigationStack push: slides in from the right edge.
class _PushedPage extends StatefulWidget {
  const _PushedPage({super.key, required this.child});
  final Widget child;

  @override
  State<_PushedPage> createState() => _PushedPageState();
}

class _PushedPageState extends State<_PushedPage> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: Motion.move);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The launch argument opens the page in place (no animation for the screenshot).
    if (_controller.value == 0 && !_controller.isAnimating) {
      if (Motion.reduced(context) || AppScope.read(context).args.has('-settingsPage')) {
        _controller.value = 1;
      } else {
        _controller.animateTo(1, curve: Motion.out);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => FractionalTranslation(translation: Offset(1 - _controller.value, 0), child: child),
    child: widget.child,
  );
}

class _Main extends StatelessWidget {
  const _Main({required this.push, required this.large});
  final ValueChanged<SettingsPage> push;
  final bool large;

  static String notationValue(String notation) => switch (notation) {
    'german' => 'C D E … H',
    'solfege' => 'До Ре Ми …',
    _ => 'C D E … B',
  };

  static String flashValue(FlashTarget flash) => switch (flash) {
    FlashTarget.off => 'Выкл',
    FlashTarget.strip => 'Полоса долей',
    FlashTarget.screen => 'Весь экран',
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    void openSheet(String kind) {
      app.showSettings = false;
      app.sheet = AppSheet(kind);
    }

    final metronome = app.settings.metronome;
    final timer = metronome.timerEnabled ? '${metronome.timerMinutes} мин' : 'выкл';
    final noise = SettingsFormat.decibels(app.tuner.noiseGate);
    final target = app.tuner.choice == TunerChoice.chromatic ? 'Ближайшая ступень' : 'Струны строя';
    // TODO(android): the routed input / output names (AudioDeviceInfo) — the built-in ones until the host reports routes.
    const input = 'Микрофон';
    final output = app.audio.outputName;
    final r = large ? largeSettingsRow : settingsRow;

    Widget section(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The caption keeps its 12 pt on the large-text board.
        large ? MediaQuery.withNoTextScaling(child: SectionCaption(text: title)) : SectionCaption(text: title),
        Card(children: rows),
      ],
    );

    final vibration = large
        ? DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: rowDivider,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 15),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Вибрация',
                      textScaler: TextScaler.noScaling,
                      style: Typo.fixed(22, TypoWeight.regular, TruverColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToggleSwitch(
                    isOn: app.settings.vibration,
                    onChanged: (v) => app.updateSettings((s) => s.vibration = v),
                    label: 'Вибрация',
                  ),
                ],
              ),
            ),
          )
        : CardRow(
            title: 'Вибрация',
            minHeight: 51,
            trailing: ToggleSwitch(
              isOn: app.settings.vibration,
              onChanged: (v) => app.updateSettings((s) => s.vibration = v),
              label: 'Вибрация',
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('Тюнер и ноты', [
          r('Порог шума', value: noise, onTap: () => push(SettingsPage.noise)),
          if (!large) r('Цель', value: target, onTap: () => push(SettingsPage.target)),
          r('Частота настройки (A4)', value: '${app.settings.defaultA4.toInt()} Гц', onTap: () => push(SettingsPage.a4)),
          r('Обозначение нот', value: notationValue(app.settings.notation), last: true, onTap: () => push(SettingsPage.notation)),
        ]),
        const SizedBox(height: 14),
        section('Звук', [
          r('Вход', value: input, onTap: () => push(SettingsPage.input)),
          // Large text (board): only the two device rows; «Громкость и задержка» stays reachable from «Выход».
          r('Выход', value: output, last: large, onTap: () => push(SettingsPage.output)),
          if (!large) r('Громкость и задержка', last: true, onTap: () => push(SettingsPage.volume)),
        ]),
        const SizedBox(height: 14),
        section('Метроном', [
          r('Звуки', value: clickSoundTitle(metronome.sound), onTap: () => openSheet('metroSounds')),
          vibration,
          r('Вспышка', value: flashValue(metronome.flash), onTap: () => openSheet('metroSounds')),
          r('Таймер занятия', value: timer, last: true, onTap: () => openSheet('metroTimer')),
        ]),
        const SizedBox(height: 14),
        section('О приложении', [
          r('О Truver', value: 'версия $appVersion', onTap: () => push(SettingsPage.about)),
          r('Обучение', onTap: () => push(SettingsPage.help)),
          r('Обратная связь', last: true, onTap: openFeedback),
        ]),
      ],
    );
  }
}

/// `row(_:_:last:action:)`: title, optional value (notes) and a chevron; 50 pt (corrected canvas).
Widget settingsRow(String title, {String? value, bool last = false, required VoidCallback onTap}) => Pressable(
  scale: 1,
  onTap: onTap,
  child: CardRow(
    title: title,
    showsDivider: !last,
    minHeight: 51,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null) ...[
          NoteText(value, style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
          const SizedBox(width: 8),
        ],
        const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
      ],
    ),
  ),
);

/// `largeRow`: title 22, the value 19 under it, padding 14 × 18, no chevron (large-text board).
Widget largeSettingsRow(String title, {String? value, bool last = false, required VoidCallback onTap}) => Pressable(
  scale: 1,
  onTap: onTap,
  child: DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: last ? const BoxDecoration() : rowDivider,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 15),
      child: MediaQuery.withNoTextScaling(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwiftText(title, style: Typo.fixed(22, TypoWeight.regular, TruverColors.textPrimary)),
            if (value != null) ...[
              const SizedBox(height: 4),
              NoteText(value, scale: false, style: Typo.fixed(19, TypoWeight.regular, TruverColors.textSecondary)),
            ],
          ],
        ),
      ),
    ),
  ),
);

enum SettingsFrameStyle { regular, large }

/// Page frame of the corrected canvas: back button 40 + title 17 medium (gap 12) in a 44 pt row 50 pt from the top,
/// a hairline under the pinned header (102), content from 116 in a scroll view with 20 pt margins. `large` — the
/// large-text board: a 34 pt bold title instead of the back button and no hairline (a round close button stays on the
/// right, so the cover can still be closed).
class SettingsPageFrame extends StatelessWidget {
  const SettingsPageFrame({
    super.key,
    required this.title,
    this.style = SettingsFrameStyle.regular,
    this.fade = false,
    required this.back,
    required this.child,
  });
  final String title;
  final SettingsFrameStyle style;
  final bool fade;
  final VoidCallback back;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final large = style == SettingsFrameStyle.large;
    return Stack(
      children: [
        const Positioned.fill(child: ScreenBackground()),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: padding.top + 3, bottom: large ? 9 : 8),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: large
                      ? [
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              textScaler: TextScaler.noScaling,
                              style: Typo.fixed(34, TypoWeight.bold, TruverColors.textPrimary),
                            ),
                          ),
                          const Spacer(),
                          RoundIconButton(icon: AppIcon.close, iconSize: 16, label: 'Закрыть', onTap: back),
                        ]
                      : [
                          RoundIconButton(icon: AppIcon.chevronLeft, label: 'Назад', onTap: back),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Typo.inter(17, TypoWeight.medium, TruverColors.textPrimary),
                              ),
                            ),
                          ),
                        ],
                ),
              ),
            ),
            if (!large) SizedBox(height: 1, child: ColoredBox(color: TruverColors.white(0.08))),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 13, bottom: 40 + padding.bottom),
                  child: child,
                ),
              ),
            ),
          ],
        ),
        // The main page fades its scrolled content out at the bottom (canvas: 54 pt from 790 down to #0d0e10).
        if (fade)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 54,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000D0E10), Color(0xFF0D0E10)],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A row with a check mark on the right (canvas lists of devices and notations): title 15, optional subtitle 12.
/// `dimmed` — a device that is not connected (title tertiary).
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.title,
    this.subtitle,
    this.selected = false,
    this.dimmed = false,
    this.titleColor,
    this.minHeight = 53,
    this.showsDivider = true,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool dimmed;
  final Color? titleColor;
  final double minHeight;
  final bool showsDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: showsDivider ? rowDivider : const BoxDecoration(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwiftText(
                      title,
                      style: Typo.row.copyWith(color: titleColor ?? (dimmed ? TruverColors.textTertiary : TruverColors.textBody)),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      SwiftText(subtitle!, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                    ],
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 18),
                const AppIconView(AppIcon.check, size: 20, lineWidth: 2, color: TruverColors.textPrimary),
              ],
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return Semantics(container: true, child: row);
    return Pressable(scale: 1, selected: selected, onTap: onTap, child: row);
  }
}

// MARK: - Tuner and notes

/// The saved noise threshold (`SettingsHooks.noiseGateKey`).
const noiseGateKey = 'tuner.noiseGateDB';

/// «Порог шума» (not drawn on the canvas; the same control as the tuner's pro panel).
class NoiseGatePage extends StatelessWidget {
  const NoiseGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tuner = app.tuner;
    return ListenableBuilder(
      listenable: tuner,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SwiftText('Порог шума', style: Typo.row.copyWith(color: TruverColors.textBody)),
                        const Spacer(),
                        SwiftText(
                          SettingsFormat.decibels(tuner.noiseGate),
                          style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    VolumeSlider(
                      value: (tuner.noiseGate + 75) / 45,
                      onChanged: (v) {
                        tuner.noiseGate = (-75 + v * 45).roundToDouble();
                        app.store.setDouble(noiseGateKey, tuner.noiseGate);
                      },
                    ),
                    const SizedBox(height: 6),
                    SwiftText('выше — не реагирует на гул', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.15), // lh 1.4: half-leading above and below
            child: SwiftText(
              'Тише порога тюнер молчит. Шумно в комнате — поднимите порог; тихий звукосниматель — опустите.',
              style: Typo.caption.copyWith(color: TruverColors.textTertiary),
              lineSpacing: _captionLineSpacing,
            ),
          ),
        ],
      ),
    );
  }
}

/// «Цель»: the strings of the tuning or the nearest semitone (the tuner's «Авто» / «Хром.»).
class TargetPage extends StatelessWidget {
  const TargetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tuner = AppScope.of(context).tuner;
    return ListenableBuilder(
      listenable: tuner,
      builder: (context, _) {
        final chromatic = tuner.choice == TunerChoice.chromatic;
        return Card(
          children: [
            CheckRow(
              title: 'Струны строя',
              subtitle: 'тюнер ищет ближайшую струну',
              selected: !chromatic,
              minHeight: 61,
              onTap: () => tuner.choice = TunerChoice.auto,
            ),
            CheckRow(
              title: 'Ближайшая ступень',
              subtitle: 'любая нота, без привязки к строю',
              selected: chromatic,
              minHeight: 61,
              showsDivider: false,
              onTap: () => tuner.choice = TunerChoice.chromatic,
            ),
          ],
        );
      },
    );
  }
}

/// «Обозначение нот»: names (English, solfège, German), accidentals of the current tuning and a preview.
class NotationPage extends StatelessWidget {
  const NotationPage({super.key});

  /// `NoteName.simpleSpelling`: letter (C = 0 … B = 6) and accidental of a pitch class.
  static Map<String, dynamic> spelling(int pc, {required bool flats}) {
    const sharps = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)];
    const flatted = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)];
    final (letter, accidental) = (flats ? flatted : sharps)[pc];
    return {'letter': letter, 'accidental': accidental};
  }

  /// The 12 notes from E (the guitar's low string): ♯, ♭ or the usual mix (C♯ E♭ F♯ G♯ B♭).
  static List<Map<String, dynamic>> preview(String preference) => [
    for (var i = 0; i < 12; i++)
      () {
        final pc = (4 + i) % 12;
        return spelling(pc, flats: preference == 'flat' || (preference == 'auto' && (pc == 3 || pc == 10)));
      }(),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final n = app.settings.notation;
    void set(String v) => app.updateSettings((s) => s.notation = v);
    final preference = app.tuning['accidentalPreference'] as String? ?? 'auto';
    void setAccidentals(String v) {
      final id = app.instrument['currentTuningId'];
      app.updateInstrument((i) {
        for (final t in (i['tunings'] as List).cast<Map<String, dynamic>>()) {
          if (t['id'] == id) {
            t['accidentalPreference'] = v;
            t['isTemplateCopy'] = false;
          }
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(text: 'Названия'),
        Card(
          children: [
            CheckRow(
              title: 'C D E F G A B',
              subtitle: 'английское',
              selected: n == 'international',
              minHeight: 61,
              onTap: () => set('international'),
            ),
            CheckRow(
              title: 'До Ре Ми Фа Соль Ля Си',
              subtitle: 'сольфеджио',
              selected: n == 'solfege',
              minHeight: 61,
              onTap: () => set('solfege'),
            ),
            CheckRow(
              title: 'C D E F G A H',
              subtitle: 'немецкое: H вместо B',
              selected: n == 'german',
              minHeight: 61,
              showsDivider: false,
              onTap: () => set('german'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          children: [
            CardRow(
              title: 'Знаки',
              showsDivider: false,
              minHeight: 57,
              trailing: SizedBox(
                width: 150,
                child: Segments<String>(
                  options: const [('sharp', '♯'), ('flat', '♭'), ('auto', 'Авто')],
                  selection: preference,
                  onChanged: setAccidentals,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionCaption(text: 'Как будет выглядеть'),
        Card(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FlowLayout(
                  spacing: 8,
                  children: [
                    for (final name in preview(preference))
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        child: ShapeBox(
                          shape: const SwiftShape.rounded(10),
                          fills: [SwiftFill(TruverColors.white(0.06))],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Center(
                              widthFactor: 1,
                              heightFactor: 1,
                              child: NoteText(
                                app.noteName(name),
                                style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// «Частота настройки (A4)»: − value +, presets, «Сыграть A4» and which tunings have their own A4.
class A4Page extends StatelessWidget {
  const A4Page({super.key});

  static void set(AppModel app, double value) {
    app.updateSettings((s) => s.defaultA4 = value.clamp(a4Range.$1, a4Range.$2));
    app.tuner.tuningChanged();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a4 = app.settings.defaultA4;
    final caption = Typo.caption.copyWith(color: TruverColors.textTertiary);
    final tunings = app.tunings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShapeBox(
          shape: const SwiftShape.rounded(18),
          fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: Padding(
            // 18 + the 1 pt border outside the content box (CSS).
            padding: const EdgeInsets.all(19),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RoundIconButton(icon: AppIcon.minus, size: 48, iconSize: 20, label: 'Меньше', onTap: () => set(app, a4 - 1)),
                const SizedBox(width: 18),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 56,
                      child: OverflowBox(
                        maxHeight: 100,
                        maxWidth: 300,
                        fit: OverflowBoxFit.deferToChild,
                        child: Text(
                          '${a4.toInt()}',
                          textScaler: TextScaler.noScaling,
                          style: Typo.fixed(56, TypoWeight.extraLight, TruverColors.textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwiftText('Гц · от ${a4Range.$1.toInt()} до ${a4Range.$2.toInt()}', style: caption),
                  ],
                ),
                const SizedBox(width: 18),
                RoundIconButton(icon: AppIcon.plus, size: 48, iconSize: 20, label: 'Больше', onTap: () => set(app, a4 + 1)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final (i, value) in const [415, 432, 440, 442, 443].indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Pressable(
                  selected: a4.toInt() == value,
                  label: '$value',
                  onTap: () => set(app, value.toDouble()),
                  child: SizedBox(
                    height: 40,
                    child: ShapeBox(
                      shape: SwiftShape.capsule,
                      fills: [SwiftFill(TruverColors.white(a4.toInt() == value ? 0.1 : 0.05))],
                      strokes: [
                        SwiftStroke(a4.toInt() == value ? const Color(0x99F3EFE6) : TruverColors.hairlineStrong, inside: true),
                      ],
                      child: Center(child: Text('$value', style: Typo.inter(14, TypoWeight.regular, TruverColors.textPrimary))),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Card(
          children: [
            CardRow(
              title: 'Сыграть A4',
              subtitle: 'проверить на слух',
              showsDivider: false,
              minHeight: 59,
              trailing: RoundIconButton(
                icon: AppIcon.play,
                size: 36,
                iconSize: 16,
                label: 'Сыграть A4',
                // `playNote` takes cents from A4 = 440.
                onTap: () => app.audio.playNote(1200 * math.log(app.settings.defaultA4 / 440) / math.ln2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionCaption(text: 'Строи · у каких свой A4'),
        Card(children: [for (final (i, t) in tunings.indexed) _tuningRow(app, t, a4, last: i == tunings.length - 1)]),
      ],
    );
  }

  Widget _tuningRow(AppModel app, Map<String, dynamic> tuning, double a4, {required bool last}) {
    final own = (tuning['a4'] as num?)?.toDouble();
    final name = tuning['name'] as String? ?? '';
    if (own != null && own != a4) {
      return Pressable(
        scale: 1,
        onTap: () {
          app.showSettings = false;
          app.sheet = AppSheet('tuningEditor', tuning['id']);
        },
        child: CardRow(
          title: name,
          showsDivider: !last,
          minHeight: 53,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${SettingsFormat.hz(own)} · свой'),
              const SizedBox(width: 8),
              const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
            ],
          ),
        ),
      );
    }
    return CardRow(title: name, showsDivider: !last, minHeight: 53, trailing: Text('${SettingsFormat.hz(a4)} · как здесь'));
  }
}

// MARK: - Sound

/// «Вход»: built-in microphone, wired headset and USB interface (those not connected are dimmed), a big level meter
/// with the good zone, the noise threshold (AU-2, AU-7). Android: the built-in microphone (the tuner opens the default
/// input).
class InputPage extends StatelessWidget {
  const InputPage({super.key, this.openNoise});
  final VoidCallback? openNoise;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tuner = app.tuner;
    // `-inputLevelDemo <bars>`: a fixed level for screenshots, in lit bars of 24 (the board shows 12).
    final demoBars = double.tryParse(app.args.value('-inputLevelDemo') ?? '');
    final demo = demoBars == null ? null : LevelMeter.levelFor(bars: demoBars);
    // TODO(android): list AudioManager.getDevices(GET_DEVICES_INPUTS) (USB interfaces, headsets) and route the
    // tuner to the chosen one; «Номер входа» for multi-channel interfaces as on iOS (`tuner.inputChannel`).
    return ListenableBuilder(
      listenable: tuner,
      builder: (context, _) {
        final level = demo ?? (tuner.isListening ? tuner.level : null);
        final caption = Typo.caption.copyWith(color: TruverColors.textTertiary);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionCaption(text: 'Устройство'),
            Card(
              children: [
                CheckRow(title: 'Встроенный микрофон', selected: true, onTap: tuner.handleAudioRestart),
                const CheckRow(title: 'Проводная гарнитура', subtitle: 'не подключена', dimmed: true, minHeight: 59),
                const CheckRow(
                  title: 'USB-интерфейс',
                  subtitle: 'подключите — появится здесь',
                  dimmed: true,
                  minHeight: 59,
                  showsDivider: false,
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionCaption(text: 'Уровень сигнала'),
            Card(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LevelMeter(level: level),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SwiftText('тихо', style: caption),
                          const Spacer(),
                          SwiftText('хорошо', style: caption.copyWith(color: TruverColors.inTune)),
                          const Spacer(),
                          SwiftText('громко', style: caption),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwiftText(
                        level == null
                            ? 'Уровень виден, пока открыт тюнер.'
                            : 'Сыграйте открытую струну: полоса должна доходить до зелёной зоны.',
                        style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              children: [
                Pressable(
                  scale: 1,
                  onTap: openNoise,
                  child: CardRow(
                    title: 'Порог шума',
                    subtitle: 'выше — не реагирует на гул',
                    showsDivider: false,
                    minHeight: 59,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(SettingsFormat.decibels(tuner.noiseGate)),
                        const SizedBox(width: 8),
                        const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The level of the corrected canvas: 24 bars 8…31 pt, gap 3, radius 2; lit — ivory, green in the good zone (bars
/// 15–20), orange above it; unlit — white 12 %, the good zone green 35 %. −70…0 dBFS.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level});
  final double? level;

  static const count = 24;
  static const zoneStart = 14, zoneEnd = 20;

  /// The level that lights `bars` bars.
  static double levelFor({required double bars}) => -70 + (bars + 0.5) / count * 70;

  Color _color(int i, bool lit) {
    final inZone = i >= zoneStart && i < zoneEnd;
    if (lit) return i >= zoneEnd ? TruverColors.sharp : (inZone ? TruverColors.inTune : TruverColors.beat);
    return inZone ? TruverColors.inTune.withValues(alpha: 0.35) : TruverColors.white(0.12);
  }

  @override
  Widget build(BuildContext context) {
    final l = level;
    final lit = l == null ? 0 : (((l + 70) / 70).clamp(0.0, 1.0) * count).floor();
    return Semantics(
      label: l == null ? 'Уровень входа недоступен' : 'Уровень входа ${l.toInt()} дБ',
      child: SizedBox(
        height: 34,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: SizedBox(
                  height: 8.0 + i,
                  child: ShapeBox(shape: const SwiftShape.rounded(2), fills: [SwiftFill(_color(i, i < lit))]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// «Выход звука»: where the metronome, notes and the reference sound go, Bluetooth delay warning, latency correction.
class OutputPage extends StatelessWidget {
  const OutputPage({super.key, this.openCheck});
  final VoidCallback? openCheck;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final offset = app.settings.latencyOffsets[app.audio.outputName] ?? 0;
    final List<CheckRow> rows;
    if (app.args.has('-audioRoutesDemo')) {
      // The board's sample: AirPods and a USB interface connected, the phone speaker in use.
      rows = const [
        CheckRow(title: 'Динамик телефона', selected: true, minHeight: 61),
        CheckRow(title: 'Проводные наушники', subtitle: 'не подключены', minHeight: 61),
        CheckRow(
          title: 'AirPods',
          subtitle: 'задержка ~180 мс — метроном будет опаздывать',
          titleColor: TruverColors.sharp,
          minHeight: 61,
        ),
        CheckRow(title: 'USB-интерфейс', subtitle: 'Focusrite 2i2 · выход 1–2', minHeight: 61, showsDivider: false),
      ];
    } else {
      // TODO(android): AudioManager.getDevices(GET_DEVICES_OUTPUTS) — wired, Bluetooth (with its delay), USB.
      rows = const [
        CheckRow(title: 'Динамик телефона', selected: true, minHeight: 61),
        CheckRow(title: 'Проводные наушники', subtitle: 'не подключены', minHeight: 61),
        CheckRow(title: 'USB-интерфейс', subtitle: 'подключите — появится здесь', minHeight: 61, showsDivider: false),
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(text: 'Куда звучат метроном, ноты и эталон'),
        Card(children: rows),
        const SizedBox(height: 14),
        const SectionCaption(text: 'Задержка'),
        Card(
          children: [
            CardRow(
              title: 'Поправка задержки',
              subtitle: 'если щелчок отстаёт от вспышки',
              minHeight: 69,
              trailing: ValueStepper(
                value: '${offset > 0 ? '+' : ''}${offset.toInt()} мс',
                valueMaxWidth: null,
                canDecrement: offset > -100,
                canIncrement: offset < 400,
                decrement: () => LatencySection.set(app, offset - 5),
                increment: () => LatencySection.set(app, offset + 5),
              ),
            ),
            Pressable(
              scale: 1,
              onTap: openCheck,
              child: const CardRow(
                title: 'Проверить на слух',
                subtitle: 'щелчок и вспышка одновременно?',
                showsDivider: false,
                minHeight: 61,
                trailing: AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// «Громкость и задержка» (SND-7, ME-9): click, notes and chords, reference and drone; output latency.
class VolumePage extends StatefulWidget {
  const VolumePage({super.key});

  @override
  State<VolumePage> createState() => _VolumePageState();
}

class _VolumePageState extends State<VolumePage> {
  late AppModel app = AppScope.read(context);
  late double _click = app.store.getDouble('vol.click') ?? 0.8;
  late double _notes = app.store.getDouble('vol.notes') ?? 0.6;
  late double _reference = app.store.getDouble('vol.reference') ?? 0.5;

  void _apply() {
    app.store.setDouble('vol.click', _click);
    app.store.setDouble('vol.notes', _notes);
    app.store.setDouble('vol.reference', _reference);
    app.audio.setVolumes(click: _click, notes: _notes, reference: _reference);
  }

  Widget _slider(String title, AppIcon icon, double value, ValueChanged<double> set, String caption, {bool last = false}) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: last ? const BoxDecoration() : rowDivider,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), // measured on the board: 97 pt a row
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwiftText(title, style: Typo.row.copyWith(color: TruverColors.textBody)),
                const Spacer(),
                SwiftText('${(value * 100).round()} %', style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                AppIconView(icon, size: 16, color: TruverColors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: VolumeSlider(
                    value: value,
                    onChanged: (v) {
                      setState(() => set(v));
                      _apply();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwiftText(caption, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(text: 'Громкость'),
        Card(
          children: [
            _slider('Щелчок метронома', AppIcon.metronome, _click, (v) => _click = v, 'сильная доля громче'),
            _slider('Ноты и аккорды', AppIcon.music, _notes, (v) => _notes = v, 'гитарный тембр'),
            _slider('Эталон и бурдон', AppIcon.waveform, _reference, (v) => _reference = v, 'тюнер', last: true),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.15), // lh 1.4: half-leading above and below
          child: SwiftText(
            // iOS: «Беззвучный режим iPhone…» — the phone's own name on Android.
            'Беззвучный режим телефона не глушит Truver. Пока телефон звучит, тюнер не слушает.',
            style: Typo.caption.copyWith(color: TruverColors.textTertiary),
            lineSpacing: _captionLineSpacing,
          ),
        ),
        const SizedBox(height: 14),
        const LatencySection(),
      ],
    );
  }
}

/// Slider of the corrected canvas: 24 pt tall, 4 pt track (white 12 %), ivory fill, white 24 pt knob.
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key, required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(v * 100).toInt()} процентов',
      increasedValue: '${(math.min(1.0, v + 0.05) * 100).toInt()} процентов',
      decreasedValue: '${(math.max(0.0, v - 0.05) * 100).toInt()} процентов',
      onIncrease: () => onChanged((v + 0.05).clamp(0.0, 1.0)),
      onDecrease: () => onChanged((v - 0.05).clamp(0.0, 1.0)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          void at(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => at(d.localPosition),
            onHorizontalDragStart: (d) => at(d.localPosition),
            onHorizontalDragUpdate: (d) => at(d.localPosition),
            child: SizedBox(
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  SizedBox(
                    width: w,
                    height: 4,
                    child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.12))]),
                  ),
                  SizedBox(
                    width: w * v,
                    height: 4,
                    child: const ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.accent)]),
                  ),
                  Positioned(
                    left: w * v - 12,
                    top: 0,
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: ShapeBox(shape: SwiftShape.circle, fills: [SwiftFill(Color(0xFFFFFFFF))]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ME-9: output latency = what the system reports + a manual correction for this output. The check plays the
/// metronome; the play button flashes on the beat as the timeline sees it — move the correction until the flash and
/// the click land together.
class LatencySection extends StatefulWidget {
  const LatencySection({super.key});

  static void set(AppModel app, double value) {
    final name = app.audio.outputName;
    app.updateSettings((s) {
      final offsets = Map.of(s.latencyOffsets);
      if (value == 0) {
        offsets.remove(name);
      } else {
        offsets[name] = value.clamp(-100.0, 400.0);
      }
      s.latencyOffsets = offsets;
    });
  }

  @override
  State<LatencySection> createState() => _LatencySectionState();
}

class _LatencySectionState extends State<LatencySection> with SingleTickerProviderStateMixin {
  /// 1 → 0 after each beat (`pulse = true; withAnimation(.easeOut(0.18)) { pulse = false }`).
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 180), value: 0);
  late final AppModel _app = AppScope.read(context);
  Object? _lastBeat;
  bool _help = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _app.metronome.addListener(_beat);
    });
  }

  void _beat() {
    final m = _app.metronome;
    final beat = m.currentBeat;
    if (beat == _lastBeat) return;
    _lastBeat = beat;
    if (!m.isPlaying) return;
    _pulse.value = 1;
    _pulse.animateTo(0, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _app.metronome.removeListener(_beat);
    _pulse.dispose();
    super.dispose();
  }

  /// The system output latency in ms (AAudio timestamps, `audio.diagnostics`).
  int _systemLatency(AppModel app) {
    final d = app.audio.call('audio.diagnostics');
    final ms = d is Map ? double.tryParse('${d['output.latencyMs'] ?? ''}') : null;
    return (ms ?? 0).round();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final name = app.audio.outputName;
    final offset = app.settings.latencyOffsets[name] ?? 0;
    final system = _systemLatency(app);
    final metronome = app.metronome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // «Задержка · динамик»: the speaker in lower case, device names as they are.
        SectionCaption(text: 'Задержка · ${name == 'Динамик' ? 'динамик' : name}'),
        Card(
          children: [
            CardRow(title: 'Из системы', minHeight: 51, trailing: Text('$system мс')),
            CardRow(
              title: 'Поправка',
              subtitle: 'итого ${math.max(0, system + offset.toInt())} мс',
              minHeight: 59,
              trailing: ValueStepper(
                value: '${offset > 0 ? '+' : ''}${offset.toInt()}',
                canDecrement: offset > -100,
                canIncrement: offset < 400,
                decrement: () => LatencySection.set(app, offset - 5),
                increment: () => LatencySection.set(app, offset + 5),
              ),
            ),
            ListenableBuilder(
              listenable: metronome,
              builder: (context, _) => CardRow(
                title: 'Проверить на слух',
                subtitle: 'щелчок и вспышка совпадают?',
                showsDivider: offset != 0,
                minHeight: 59,
                trailing: Stack(
                  children: [
                    RoundIconButton(
                      icon: metronome.isPlaying ? AppIcon.stop : AppIcon.play,
                      size: 36,
                      iconSize: 16,
                      label: metronome.isPlaying ? 'Стоп' : 'Проверить',
                      onTap: metronome.toggle,
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) => Opacity(
                            opacity: 0.9 * _pulse.value,
                            child: const ShapeBox(shape: SwiftShape.circle, fills: [SwiftFill(TruverColors.beat)]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (offset != 0)
              Pressable(
                scale: 1,
                onTap: () => LatencySection.set(app, 0),
                child: const CardRow(title: 'Сбросить поправку', showsDivider: false, minHeight: 51),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pressable(
                scale: 1,
                onTap: () => setState(() => _help = !_help),
                // CSS: a 13 pt span in a 16 pt line box sits ~3 pt lower.
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SwiftText(
                    'Bluetooth-наушники опаздывают · как настроить ›',
                    style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary),
                  ),
                ),
              ),
              if (_help) ...[
                const SizedBox(height: 8),
                SwiftText(
                  'Наушники Bluetooth часто звучат позже, чем говорит система. Включите проверку и меняйте поправку, пока вспышка не совпадёт со щелчком. Поправка хранится для каждого выхода и влияет на полосу долей, вспышку и подсветку нот.',
                  style: Typo.caption.copyWith(color: TruverColors.textTertiary),
                  lineSpacing: 3,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

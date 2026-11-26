/// Port of Truver/Sources/Features/Metronome/PlayCheckViews.swift
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'metronome_controller.dart';
import 'metronome_sheets.dart';
import 'play_check_controller.dart';
import 'rhythm_library.dart';

/// Panel under the controls while «Проверка игры» is on (in place of Tap): the last notes as dots on a
/// rushed ← 0 → dragged line, coloured by grade, and the last bar in one line (SM-3).
class PlayCheckPanel extends StatelessWidget {
  const PlayCheckPanel({super.key, this.height = 60});
  final double height;

  /// ±half the subdivision spans the width; missing / extra notes sit at the edges.
  static double? position(GradedNote note, double width) {
    final interval = note.interval;
    if (interval == null) return null;
    final d = note.deviation;
    if (d == null) return note.grade == RhythmGrade.missing ? -width / 2 + 5 : null;
    final x = (d / (interval / 2)).clamp(-1.0, 1.0);
    return x * (width / 2 - 5);
  }

  static Color color(RhythmGrade grade) => switch (grade) {
    RhythmGrade.exact => TruverColors.inTune,
    RhythmGrade.good => TruverColors.textPrimary,
    RhythmGrade.inaccurate => TruverColors.flat,
    RhythmGrade.unrecognized => TruverColors.textTertiary,
    _ => TruverColors.sharp,
  };

  static String line(AppModel app) {
    final check = app.playCheck;
    if (check.gradingUnavailable) return 'Деление короче 40 мс — оценка ритма недоступна';
    final m = app.metronome;
    // Step by step: what to do now (user: «не до конца понятно, как это работает»).
    final what = PlayCheckSheet.whatToPlay(m.meter, short: true);
    if (!m.isPlaying) return 'Нажмите ▶ · такт отсчёта · потом играйте $what';
    if (m.currentBar == 0 && check.lastBar == null) return 'Отсчёт — слушайте этот такт, играть со следующего';
    if (check.idle) return 'Не слышу игры — играйте $what';
    final bar = check.lastBar;
    if (bar == null) return 'Играйте $what · оценка после такта';
    if (!bar.isCounted) return 'Такт ${bar.bar} не засчитан — много нераспознанных нот';
    final share = (bar.accurateShare * 100).round();
    final parts = ['Такт ${bar.bar} · $share %'];
    final mean = bar.meanDeviation;
    if (mean != null) {
      final ms = (mean * 1000).round();
      parts.add(ms == 0 ? 'ровно' : (ms < 0 ? 'спешите ${-ms} мс' : 'тянете $ms мс'));
    }
    final s = bar.spread;
    if (s != null) parts.add('разброс ${(s * 1000).round()} мс');
    if (bar.missing > 0) parts.add('пропусков ${bar.missing}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final check = app.playCheck;
    final text = line(app);
    return Semantics(
      label: 'Проверка игры',
      value: text,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
        child: ShapeBox(
          shape: const SwiftShape.rounded(18, continuous: true),
          fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 20,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final w = box.maxWidth;
                        final recent = check.recent;
                        return Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: 4,
                              width: w,
                              child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.06))]),
                            ),
                            const SizedBox(width: 1.5, height: 18, child: ColoredBox(color: TruverColors.textTertiary)),
                            for (var i = 0; i < recent.length; i++)
                              if (position(recent[i], w) case final x?)
                                Transform.translate(
                                  offset: Offset(x, 0),
                                  child: Opacity(
                                    opacity: 0.25 + 0.75 * (i + 1) / (recent.isEmpty ? 1 : recent.length),
                                    child: SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: ShapeBox(shape: SwiftShape.circle, fills: [SwiftFill(color(recent[i].grade))]),
                                    ),
                                  ),
                                ),
                            Positioned(
                              left: 0,
                              bottom: -10,
                              child: Text('раньше', style: Typo.inter(9, TypoWeight.regular, TruverColors.textTertiary)),
                            ),
                            Positioned(
                              right: 0,
                              bottom: -10,
                              child: Text('позже', style: Typo.inter(9, TypoWeight.regular, TruverColors.textTertiary)),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4 + 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      style: Typo.monospacedDigit(Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Проверка игры» settings: on / off, source hint (SM-7), tempo by result (SM-8), the ceiling (SM-9).
class PlayCheckSheet extends StatelessWidget {
  const PlayCheckSheet({super.key});

  /// What one plays so that every attack has its click: the subdivision or the figure.
  static String whatToPlay(Map<String, dynamic> m, {required bool short}) {
    final r = m.rhythm == null ? null : RhythmLibrary.describe(m.rhythm!);
    if (r != null && !r.isPlain) {
      return short ? 'по рисунку «${r.name}»' : 'по рисунку «${r.name}» — нота на каждый щелчок фигуры';
    }
    final n = m.subdivision;
    final name = switch (n) {
      1 => 'четвертями',
      2 => 'восьмыми',
      3 => 'триолями',
      4 => 'шестнадцатыми',
      6 => 'секстолями',
      _ => 'по $n на долю',
    };
    if (short) return name;
    return n == 1 ? 'четвертями — одна нота на каждый щелчок' : '$name — $n ноты на каждую долю, на каждый щелчок';
  }

  /// «1 чистый такт», «4 чистых такта», «5 чистых тактов».
  static String clean(int n) => MetronomeController.plural(n, 'чистый такт', 'чистых такта', 'чистых тактов');

  static String calibrationText(PlayCheckController check) => switch (check.calibration) {
    CalibrationIdle() => 'через динамик — один раз',
    CalibrationRunning() => 'Нужна тишина… слушаю щелчки',
    CalibrationDone(:final offset) =>
      'Готово: ${offset >= 0 ? '+' : '−'}${(offset.abs() * 1000).round()} мс для этой связки входа и выхода',
    CalibrationFailed(:final reason) => reason,
  };

  /// The steps that were on this sheet before the canvas fix, now behind «Как это работает».
  static String help(AppModel app) => [
    '1. Включите проверку и нажмите ▶. Первый такт — отсчёт, слушайте.',
    '2. Играйте ${whatToPlay(app.metronome.meter, short: false)}.',
    '3. После каждого такта — оценка: точки левее — раньше щелчка, правее — позже. Зелёная — точно, белая — хорошо, синяя — неточно, оранжевая — мимо или пропуск.',
    '4. Стоп — итог: сколько точно, спешите или тянете, слабая доля.',
    'С наушниками или интерфейсом точнее: щелчок из динамика тоже попадает в микрофон. Через динамик первый такт — отсчёт, приложение запоминает щелчок.',
    'Темп по результату: ${app.playCheck.settings.cleanBars} чистых такта (≥ 90 %) — быстрее, 2 такта < 70 % — медленнее.',
  ].join('\n\n');

  /// Canvas «Проверка игры» (top 168): what to play and the legend, tempo by result, calibration, «Как это работает».
  @override
  Widget build(BuildContext context) => const _PlayCheckSheetBody();
}

class _PlayCheckSheetBody extends StatefulWidget {
  const _PlayCheckSheetBody();

  @override
  State<_PlayCheckSheetBody> createState() => _PlayCheckSheetBodyState();
}

class _PlayCheckSheetBodyState extends State<_PlayCheckSheetBody> {
  bool _help = false;

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 10, height: 10, child: ShapeBox(shape: SwiftShape.circle, fills: [SwiftFill(color)])),
      const SizedBox(width: 6),
      Text(text, style: Typo.caption.copyWith(color: TruverColors.textSecondary)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final check = app.playCheck;
    return ListenableBuilder(
      listenable: check,
      builder: (context, _) {
        final s = check.settings;
        final offset = check.routeOffset;
        final ceiling = check.ceiling;
        final tempoMode = app.metronome.state.modes.tempo;
        final calibration = check.calibration;
        Widget chevron() => const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary);
        final sheet = DesignSheet(
          title: 'Проверка игры',
          height: 676,
          close: () => app.sheet = null,
          footer: [
            Expanded(
              child: SheetButton(
                title: check.isOn ? 'Выключить проверку' : 'Включить проверку',
                icon: AppIcon.mic,
                onTap: () {
                  check.toggle();
                  app.sheet = null;
                },
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShapeBox(
                shape: const SwiftShape.rounded(16),
                fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.43), // the half-leading of line-height 1.4
                        child: SwiftText(
                          'Играйте по ноте на щелчок. После такта — точки: левее — раньше, правее — позже.',
                          lineSpacing: 21 - 18.15,
                          style: Typo.inter(15, TypoWeight.regular, TruverColors.textBody),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        children: [
                          _legend(TruverColors.inTune, 'точно'),
                          _legend(TruverColors.textPrimary, 'хорошо'),
                          _legend(TruverColors.flat, 'неточно'),
                          _legend(TruverColors.sharp, 'мимо'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              MetroCard(
                children: [
                  MetroRow(
                    title: 'Темп по результату',
                    subtitle: '${s.cleanBars} ${PlayCheckSheet.clean(s.cleanBars)} — быстрее',
                    minHeight: 58,
                    trailing: ToggleSwitch(
                      isOn: s.adaptive,
                      label: 'Темп по результату',
                      onChanged: (v) => check.updateSettings((x) => x.adaptive = v),
                    ),
                  ),
                  MetroRow(
                    title: 'Шаг',
                    subtitle: 'BPM',
                    trailing: ValueStepper(
                      value: '${s.step}',
                      canDecrement: s.step > 1,
                      canIncrement: s.step < 20,
                      decrement: () => check.updateSettings((x) => x.step -= 1),
                      increment: () => check.updateSettings((x) => x.step += 1),
                    ),
                  ),
                  MetroRow(
                    title: 'Тактов для шага',
                    trailing: ValueStepper(
                      value: '${s.cleanBars}',
                      canDecrement: s.cleanBars > 1,
                      canIncrement: s.cleanBars < 16,
                      decrement: () => check.updateSettings((x) => x.cleanBars -= 1),
                      increment: () => check.updateSettings((x) => x.cleanBars += 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MetroCard(
                children: [
                  Pressable(
                    scale: 1,
                    onTap: check.calibrate,
                    child: MetroRow(
                      title: 'Калибровка задержки',
                      subtitle: PlayCheckSheet.calibrationText(check),
                      minHeight: 58,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (calibration is CalibrationRunning)
                            SizedBox(width: 80, child: _ProgressBar(value: calibration.progress))
                          else if (offset != 0)
                            Text(
                              '${offset > 0 ? '+' : '−'}${(offset.abs() * 1000).round()} мс',
                              style: Typo.monospacedDigit(Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
                            ),
                          if (calibration is CalibrationRunning || offset != 0) const SizedBox(width: 8),
                          chevron(),
                        ],
                      ),
                    ),
                  ),
                  Pressable(
                    scale: 1,
                    onTap: () => setState(() => _help = true),
                    child: MetroRow(title: 'Как это работает', minHeight: 52, trailing: chevron()),
                  ),
                ],
              ),
              if (ceiling != null) ...[
                const SizedBox(height: 14),
                SwiftText(
                  'Потолок этого пресета: ${ceiling.toInt()} BPM · следующее занятие начнётся с ${check.nextSessionStart(ceiling).toInt()}',
                  style: Typo.caption.copyWith(color: TruverColors.textSecondary),
                ),
              ],
              if (tempoMode != ModeTempo.none) ...[
                const SizedBox(height: 14),
                SwiftText(
                  'Режим темпа «${MetronomeModes.tempoTitle(tempoMode)}» ведёт темп сам — «Темп по результату» на это время выключен',
                  style: Typo.caption.copyWith(color: TruverColors.sharp),
                ),
              ],
            ],
          ),
        );
        if (!_help) return sheet;
        return Stack(
          children: [
            sheet,
            Positioned.fill(
              child: DesignAlert(
                title: 'Как это работает',
                message: PlayCheckSheet.help(app),
                actions: [DesignAlertAction('Понятно', () => setState(() => _help = false), role: DesignAlertRole.preferred)],
                dismiss: () => setState(() => _help = false),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// SwiftUI `ProgressView(value:)` tinted ivory: a 4 pt capsule track.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Positioned.fill(
            child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.12))]),
          ),
          SizedBox(
            width: box.maxWidth * value.clamp(0.0, 1.0),
            child: const ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.textPrimary)]),
          ),
        ],
      ),
    ),
  );
}

/// PL-3 «Итог попытки»: time, tempo and the ceiling, accuracy, rushing / dragging, the weakest beat.
class PlayCheckSummarySheet extends StatelessWidget {
  const PlayCheckSummarySheet({super.key});

  static String clock(double s) => '${s.toInt() ~/ 60}:${(s.toInt() % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = app.playCheck.summary;
    TextStyle value() => Typo.monospacedDigit(Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary));
    return DesignSheet(
      title: 'Итог попытки',
      height: 560,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: SheetButton(title: 'Готово', onTap: () => app.sheet = null),
        ),
      ],
      child: a == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatCard(caption: 'Точно + хорошо', value: '${(a.accurateShare * 100).round()} %'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatCard(
                        caption: 'Темп',
                        value: a.startBPM == a.endBPM ? '${a.endBPM.toInt()}' : '${a.startBPM.toInt()}→${a.endBPM.toInt()}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Card(
                  children: [
                    CardRow(
                      title: 'Время',
                      subtitle: '${a.bars} ${MetronomeController.bars(a.bars)} засчитано',
                      trailing: Text(clock(a.seconds), style: value()),
                    ),
                    CardRow(
                      title: a.meanDeviation < 0 ? 'Спешите' : 'Тянете',
                      subtitle: 'среднее отклонение',
                      trailing: Text('${a.meanDeviation.abs().round()} мс', style: value()),
                    ),
                    CardRow(
                      title: 'Разброс',
                      subtitle: 'насколько ровно',
                      trailing: Text('${a.spread.round()} мс', style: value()),
                    ),
                    if (a.weakestBeat != null && a.weakestBeatDeviation != null)
                      CardRow(
                        title: 'Слабое место',
                        subtitle: 'доля ${a.weakestBeat! + 1}',
                        trailing: Text(
                          '${a.weakestBeatDeviation! < 0 ? 'спешите ' : 'тянете '}${a.weakestBeatDeviation!.abs().round()} мс',
                          style: value(),
                        ),
                      ),
                    if (a.silenceDrift != null)
                      CardRow(
                        title: 'Уход за тишину',
                        subtitle: 'первые ноты после возврата щелчка',
                        trailing: Text('${a.silenceDrift! < 0 ? '−' : '+'}${a.silenceDrift!.abs().round()} мс', style: value()),
                      ),
                    CardRow(
                      title: 'Потолок темпа',
                      showsDivider: false,
                      trailing: Text(a.ceiling != null ? '${a.ceiling!.toInt()} BPM' : '—', style: value()),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Port of Truver/Sources/Features/Practice/FretTrainerView.swift
///
/// FB-12 «Тренажёр грифа» (corrected canvas «Тренажёр — назови / сыграй / верно / ошибка / итог»).
/// «Назови ноту»: a scrollable neck with fret numbers, the asked cell «?», piano-like keys near the question; a wrong
/// answer says why («Это G, а не C · 8-я струна F♯ + 1 лад = G») and waits for «Дальше». «Сыграй ноту»: the note and
/// the string (highlighted on the neck, the place is to be found), «Слушаю…», «Подсказка» shows the fret; a right
/// answer shows where it was played and goes on in a second. The summary offers «Повторить ошибки».
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/audio_services.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'fret_trainer_controller.dart';
import 'play_check_charts.dart';
import 'practice_links.dart';
import 'practice_menu.dart';
import 'practice_session_controller.dart';
import 'practice_session_view.dart';
import 'trainer_neck.dart';

/// Note text (accidentals in the system font) with SwiftUI's line box of `style`.
Widget _notes(String text, TextStyle style, {int? maxLines}) =>
    SwiftText.rich(Typo.notes(text, style), style: style, maxLines: maxLines, softWrap: maxLines == null ? null : false);

/// A block at a canvas top (screen y − the 47 pt safe area).
Widget _at(double y, Widget child) => Positioned(left: 0, right: 0, top: y - 47, child: child);

class FretTrainerView extends StatelessWidget {
  const FretTrainerView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final trainer = app.trainer;
    return ListenableBuilder(
      listenable: trainer,
      builder: (context, _) {
        final padding = MediaQuery.paddingOf(context);
        final q = trainer.question;
        final info = trainer.summaryInfo;
        void close() {
          trainer.close();
          app.showTrainer = false;
        }

        return Stack(
          children: [
            const Positioned.fill(child: ScreenBackground()),
            Padding(
              padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: Stack(
                  children: [
                    if (info != null)
                      ..._summary(app, info, close)
                    else if (q != null)
                      ..._question(app, q),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PracticePageHeader(
                            icon: AppIcon.close,
                            label: 'Закрыть',
                            title: 'Тренажёр грифа',
                            subtitle: info != null ? 'серия завершена' : _progress(trainer),
                            onTap: close,
                            trailing: info == null ? _OptionsButton(trainer: trainer) : null,
                          ),
                          if (info == null)
                            Padding(
                              padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
                              child: Segments<TrainerKind>(
                                options: const [(TrainerKind.nameNote, 'Назови ноту'), (TrainerKind.playNote, 'Сыграй ноту')],
                                selection: trainer.settings.kind,
                                onChanged: (k) {
                                  trainer.updateSettings((x) => x.kind = k);
                                  trainer.newSeries();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _progress(FretTrainerController trainer) {
    final s = trainer.session;
    if (s == null) return '';
    final n = s.answered + 1 < s.count ? s.answered + 1 : s.count;
    return '$n из ${s.count} · верно ${s.correct}';
  }

  // MARK: Question

  List<Widget> _question(AppModel app, TrainerQuestion q) {
    final trainer = app.trainer;
    final f = trainer.feedback;
    if (trainer.settings.kind == TrainerKind.nameNote) {
      return [
        _at(160, Center(child: SwiftText('Какая нота?', style: Typo.inter(18, TypoWeight.medium, TruverColors.textPrimary)))),
        _at(196, Center(child: _neck(app, q, height: f.isWrong ? 300 : 340, span: f.isWrong ? 7 : 9))),
        if (f.isWrong)
          _at(
            510,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _wrongCard(app, q),
                  const SizedBox(height: 12.6),
                  _Keys(app: app, q: q),
                  const SizedBox(height: 20),
                  SheetButton(title: 'Дальше', height: 48, onTap: trainer.next),
                ],
              ),
            ),
          )
        else ...[
          _at(576, Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _Keys(app: app, q: q))),
          if (f.isNone) _at(722, Center(child: Pressable(onTap: trainer.skip, child: const Chip(text: 'Пропустить')))),
        ],
      ];
    }
    return [
      _at(
        160,
        Column(
          children: [
            _notes(trainer.name(q.pitchClass), Typo.inter(44, TypoWeight.light, TruverColors.textPrimary)),
            Transform.translate(
              offset: const Offset(0, -2),
              child: SwiftText(_playHint(app, q), maxLines: 1, softWrap: false, style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
            ),
          ],
        ),
      ),
      _at(252, Center(child: _neck(app, q, height: 330, span: 9))),
      if (f.isNone) ...[
        _at(604, Center(child: _listeningLine(app))),
        _at(
          700,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Pressable(onTap: trainer.showHint, child: const Chip(text: 'Подсказка')),
              const SizedBox(width: 8),
              Pressable(onTap: trainer.skip, child: const Chip(text: 'Пропустить')),
            ],
          ),
        ),
      ] else if (f.isCorrect)
        _at(600, Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _rightCard(app, q)))
      else ...[
        _at(600, Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _wrongCard(app, q))),
        _at(748, Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SheetButton(title: 'Дальше', height: 48, onTap: trainer.next))),
      ],
    ];
  }

  static int _stringNumber(AppModel app, TrainerQuestion q) => app.courseCount - q.course;

  static String _openName(AppModel app, int course) {
    final names = app.trainer.openNames();
    return course < names.length ? names[course] : '';
  }

  static String _playHint(AppModel app, TrainerQuestion q) => app.trainer.settings.showString
      ? 'сыграйте на ${_stringNumber(app, q)}-й струне (${_openName(app, q.course)}) · любая октава'
      : 'сыграйте в любом месте грифа · любая октава';

  /// The neck around the asked fret: 9 frets (7 while a wrong answer's card is shown), the cell's dot when it is
  /// asked («?»), answered or hinted, the asked string highlighted in «Сыграй ноту».
  Widget _neck(AppModel app, TrainerQuestion q, {required double height, required int span}) {
    final trainer = app.trainer;
    final top = (app.instrument['fretCount'] as num?)?.toInt() ?? 24;
    var lower = q.fret - (span - 1) ~/ 2;
    if (lower > top - span + 1) lower = top - span + 1;
    if (lower < 1) lower = 1;
    final label = trainer.name(q.pitchClass);
    final f = trainer.feedback;
    final play = trainer.settings.kind == TrainerKind.playNote;
    final dots = <TrainerDot>[
      if (f.isNone && !play) TrainerDot(course: q.course, fret: q.fret, label: '?', style: TrainerDotStyle.question),
      if (f.isNone && play && trainer.hintShown) TrainerDot(course: q.course, fret: q.fret, label: label, style: TrainerDotStyle.question),
      if (f.isCorrect)
        TrainerDot(course: q.course, fret: q.fret, label: label, style: play ? TrainerDotStyle.rightSmall : TrainerDotStyle.right),
      if (f.isWrong) TrainerDot(course: q.course, fret: q.fret, label: label, style: TrainerDotStyle.right),
    ];
    return Semantics(
      label: play ? 'Струна ${_stringNumber(app, q)}' : 'Струна ${_stringNumber(app, q)}, лад ${q.fret}',
      excludeSemantics: true,
      child: TrainerNeck(
        key: ValueKey('${q.course}-${q.fret}-$span-${trainer.session?.answered ?? 0}'),
        courses: app.courseCount,
        fretCount: top,
        lower: lower,
        upper: lower + span - 1,
        height: height,
        leftHanded: PracticeLinks.leftHanded(app),
        dots: dots,
        highlight: play && trainer.settings.showString ? TrainerHighlight(course: q.course, right: f.isCorrect) : null,
      ),
    );
  }

  // MARK: Feedback

  /// Canvas wrong card: danger 8 % with a 35 % border, «Это G, а не C» 16 semibold, why in 12 under it.
  Widget _wrongCard(AppModel app, TrainerQuestion q) {
    final trainer = app.trainer;
    final expected = trainer.name(q.pitchClass);
    final heard = trainer.feedback.heard;
    final title = heard != null ? 'Это $expected, а не ${trainer.name(heard)}' : 'Это $expected';
    final n = _stringNumber(app, q), open = _openName(app, q.course);
    final why = q.fret == 0
        ? '$n-я струна $open открытая = $expected'
        : '$n-я струна $open + ${q.fret} ${PracticeSessionController.plural(q.fret, 'лад', 'лада', 'ладов')} = $expected';
    return PracticeCard(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      fill: TruverColors.danger.withValues(alpha: 0.08),
      border: TruverColors.danger.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _notes(title, Typo.inter(16, TypoWeight.semibold, TruverColors.textPrimary)),
          const SizedBox(height: 3),
          _notes('$why · запомнится в «Повторить ошибки»', Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
        ],
      ),
    );
  }

  /// Canvas right card: green 10 % with a 35 % border, a check, «Верно · D3», where and how fast, when it goes on.
  Widget _rightCard(AppModel app, TrainerQuestion q) {
    final trainer = app.trainer;
    final place = q.fret == 0 ? 'открытая' : '${q.fret}-й лад';
    final seconds = trainer.answerSeconds.toStringAsFixed(1).replaceAll('.', ',');
    return PracticeCard(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      fill: TruverColors.inTune.withValues(alpha: 0.1),
      border: TruverColors.inTune.withValues(alpha: 0.35),
      child: Row(
        children: [
          const AppIconView(AppIcon.check, size: 22, lineWidth: 2.4, color: TruverColors.inTune),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _notes('Верно · ${q.fullName.isEmpty ? trainer.name(q.pitchClass) : q.fullName}', Typo.inter(16, TypoWeight.semibold, TruverColors.textPrimary)),
                const SizedBox(height: 2),
                SwiftText('${_stringNumber(app, q)}-я струна, $place · $seconds с', style: Typo.caption.copyWith(color: TruverColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SwiftText('дальше через 1 с', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
        ],
      ),
    );
  }

  /// «Слушаю…» with a green level mark; the note heard so far; the microphone hint when there is no access.
  Widget _listeningLine(AppModel app) {
    final permission = PracticeLinks.micPermission(app);
    if (permission == MicPermission.denied || permission == MicPermission.restricted) {
      return SwiftText('Нужен доступ к микрофону — откройте Настройки', style: Typo.inter(15, TypoWeight.regular, TruverColors.sharp));
    }
    final heard = app.trainer.heard;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, h) in const [6.0, 12.0, 18.0, 10.0, 5.0].indexed) ...[
                if (i > 0) const SizedBox(width: 3),
                SizedBox(
                  width: 4,
                  height: h,
                  child: const ShapeBox(shape: SwiftShape.rounded(2), fills: [SwiftFill(TruverColors.inTune)]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        _notes(heard != null ? 'Слышу ${app.trainer.name(heard)}' : 'Слушаю…', Typo.inter(15, TypoWeight.regular, TruverColors.textBody)),
      ],
    );
  }

  // MARK: Summary

  /// Series summary (canvas «Тренажёр — итог»): «1 из 20», the mode and frets, three equal cards, the hardest string
  /// and the missed notes, «Повторить ошибки», «Ещё серия» and «Готово».
  List<Widget> _summary(AppModel app, TrainerSummaryInfo info, VoidCallback close) {
    final trainer = app.trainer;
    final mode = info.kind == TrainerKind.nameNote ? 'Назови ноту' : 'Сыграй ноту';
    final percent = info.total == 0 ? 0 : (info.correct * 100 / info.total).round();
    final time = info.averageSeconds.toStringAsFixed(1).replaceAll('.', ',');
    final missed = [for (final pc in info.missedPitchClasses) trainer.name(pc)];
    return [
      _at(
        150,
        Column(
          children: [
            SwiftText(
              '${info.correct} из ${info.total}',
              style: Typo.inter(64, TypoWeight.semibold, TruverColors.textPrimary).copyWith(letterSpacing: -1.28),
            ),
            const SizedBox(height: 4),
            SwiftText('$mode · лады ${info.frets.first}–${info.frets.last}', style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
          ],
        ),
      ),
      _at(
        270,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(child: _SummaryCard('Верно', '$percent %')),
              const SizedBox(width: 8),
              Expanded(child: _SummaryCard('Среднее время', '$time с')),
              const SizedBox(width: 8),
              Expanded(child: _SummaryCard('Лучшая серия', '${info.bestStreak}')),
            ],
          ),
        ),
      ),
      if (info.weakCourses.isNotEmpty || missed.isNotEmpty)
        _at(
          386,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              children: [
                if (info.weakCourses.isNotEmpty)
                  PracticeRow(title: 'Сложнее всего', minHeight: 52, trailing: Text('струна ${app.courseCount - info.weakCourses.first}')),
                if (missed.isNotEmpty)
                  PracticeRow(
                    title: 'Ошибки на нотах',
                    minHeight: 52,
                    trailing: _notes(missed.join(' '), Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary), maxLines: 1),
                  ),
              ],
            ),
          ),
        ),
      if (missed.isNotEmpty)
        _at(
          520,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Pressable(
              onTap: trainer.repeatMistakes,
              child: Card(
                children: [
                  PracticeRow(
                    title: 'Повторить ошибки',
                    subtitle: 'серия только из этих нот',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${missed.length} ${PracticeSessionController.plural(missed.length, 'нота', 'ноты', 'нот')}'),
                        const SizedBox(width: 8),
                        const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      _at(690, Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SheetButton(title: 'Ещё серия', height: 52, onTap: trainer.newSeries))),
      _at(752, Center(child: Pressable(onTap: close, child: SwiftText('Готово', style: Typo.inter(15, TypoWeight.regular, TruverColors.textSecondary))))),
    ];
  }
}

/// Canvas: 96 high (border box), padding 12 × 14, caption 12 (line 1.25, two lines reserved), value 26 light.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.caption, this.value);
  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: PracticeCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 30),
            child: SwiftText(caption, lineSpacing: 0.47, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
          ),
          const Spacer(),
          SwiftText(value, maxLines: 1, softWrap: false, style: Typo.inter(26, TypoWeight.light, TruverColors.textPrimary)),
        ],
      ),
    ),
  );
}

/// The trainer's options menu behind the canvas «Параметры» button.
class _OptionsButton extends StatelessWidget {
  const _OptionsButton({required this.trainer});
  final FretTrainerController trainer;

  /// A setting changed: a new series (except «Подсказывать струну»).
  void _set(void Function(TrainerSettings s) change, {bool restart = true}) {
    trainer.updateSettings(change);
    if (restart) trainer.newSeries();
  }

  @override
  Widget build(BuildContext context) {
    final s = trainer.settings;
    return Builder(
      builder: (anchor) => Pressable(
        label: 'Настройки тренажёра',
        onTap: () => showPracticeMenu(anchor, [
          [
            for (final (v, t) in const [
              (TrainerStrings.all, 'Все струны'),
              (TrainerStrings.low, 'Три нижние'),
              (TrainerStrings.high, 'Три верхние'),
            ])
              MenuItem(t, () => s.strings == v ? null : _set((x) => x.strings = v), checked: s.strings == v),
          ],
          [
            for (final (v, t) in const [
              (TrainerFrets.first12, 'Лады 0–12'),
              (TrainerFrets.whole, 'Весь гриф'),
              (TrainerFrets.upper, 'От 12-го лада'),
            ])
              MenuItem(t, () => s.frets == v ? null : _set((x) => x.frets = v), checked: s.frets == v),
          ],
          [
            for (final n in const [10, 20, 40])
              MenuItem('$n вопросов', () => s.count == n ? null : _set((x) => x.count = n), checked: s.count == n),
          ],
          [
            MenuItem('Только ноты без знаков', () => _set((x) => x.naturalsOnly = !x.naturalsOnly), checked: s.naturalsOnly),
            MenuItem('Подсказывать струну', () => _set((x) => x.showString = !x.showString, restart: false), checked: s.showString),
          ],
        ]),
        child: const RoundButtonFace(size: 40, child: Center(child: CustomPaint(size: Size(18, 18), painter: _OptionsIconPainter()))),
      ),
    );
  }
}

/// The canvas «Параметры» icon: three lines, a knob on the first (filled with the background).
class _OptionsIconPainter extends CustomPainter {
  const _OptionsIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * s
      ..strokeCap = StrokeCap.round
      ..color = TruverColors.textBody;
    for (final y in const [7.0, 12.0, 17.0]) {
      canvas.drawLine(Offset(5 * s, y * s), Offset(19 * s, y * s), stroke);
    }
    canvas.drawCircle(Offset(9 * s, 7 * s), 2 * s, Paint()..color = TruverColors.background);
    canvas.drawCircle(Offset(9 * s, 7 * s), 2 * s, stroke);
  }

  @override
  bool shouldRepaint(_OptionsIconPainter old) => false;
}

// MARK: Keys

/// Canvas keys: 7 naturals (62 high, 5 apart) at the bottom of a 128 pt block, 5 sharps (48 × 58) over the gaps
/// between them; the picked wrong key red, the right one green.
class _Keys extends StatelessWidget {
  const _Keys({required this.app, required this.q});
  final AppModel app;
  final TrainerQuestion q;

  static const _naturals = [0, 2, 4, 5, 7, 9, 11];
  static const _sharps = [(1, 1), (3, 2), (6, 4), (8, 5), (10, 6)];

  @override
  Widget build(BuildContext context) {
    final trainer = app.trainer;
    final naturalsOnly = trainer.session?.naturalsOnly == true;
    return SizedBox(
      height: 128,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 66,
                height: 62,
                child: Row(
                  children: [
                    for (final (i, pc) in _naturals.indexed) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(
                        child: _key(pc, sharp: false, child: Center(child: _notes(trainer.name(pc), Typo.inter(20, TypoWeight.medium, TruverColors.textPrimary)))),
                      ),
                    ],
                  ],
                ),
              ),
              for (final (pc, boundary) in _sharps)
                Positioned(
                  left: w * boundary / 7 - 24,
                  top: 0,
                  width: 48,
                  height: 58,
                  child: Opacity(
                    opacity: naturalsOnly ? 0.3 : 1,
                    child: IgnorePointer(
                      ignoring: naturalsOnly,
                      child: _key(
                        pc,
                        sharp: true,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _notes(trainer.name(pc), Typo.inter(14, TypoWeight.semibold, TruverColors.textPrimary)),
                              const SizedBox(height: 1),
                              _notes(trainer.flatName(pc), Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _key(int pc, {required bool sharp, required Widget child}) {
    final (fill, border) = _colors(pc, sharp);
    return Pressable(
      onTap: () => app.trainer.answer(pc),
      child: ShapeBox(
        shape: const SwiftShape.rounded(12, continuous: true),
        fills: [SwiftFill(fill)],
        strokes: [SwiftStroke(border, inside: true)],
        child: child,
      ),
    );
  }

  (Color, Color) _colors(int pc, bool sharp) {
    final plain = (sharp ? const Color(0xFF0F1012) : TruverColors.white(0.06), TruverColors.white(0.1));
    final f = app.trainer.feedback;
    final right = (TruverColors.inTune.withValues(alpha: 0.18), TruverColors.inTune.withValues(alpha: 0.8));
    if (f.isCorrect && pc == q.pitchClass) return right;
    if (f.isWrong) {
      if (pc == f.expected) return right;
      if (pc == f.heard) return (TruverColors.danger.withValues(alpha: 0.16), TruverColors.danger.withValues(alpha: 0.7));
    }
    return plain;
  }
}

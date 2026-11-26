/// Port of Truver/Sources/Features/Tuner/IntonationSheet.swift
///
/// TU-11 «Проверка мензуры» (6.2.11): pick a string → «Сыграйте открытую струну» → «Сыграйте на 12-м ладу» →
/// «седло от грифа / к грифу, ~N ц, ≈ X мм» → next string. The tuner listens in chromatic mode meanwhile and
/// returns to its mode when the sheet closes.
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'tuner_controller.dart';
import 'tuner_dial.dart' show swiftNotes;

class IntonationSheet extends StatefulWidget {
  const IntonationSheet({super.key});

  @override
  State<IntonationSheet> createState() => _IntonationSheetState();
}

class _IntonationSheetState extends State<IntonationSheet> {
  late final AppModel _app = AppScope.read(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tuner = _app.tuner;
      if (_app.args.has('-intonationDemo')) {
        tuner.injectIntonationDemo('Слышу F♯3');
        return;
      }
      if (tuner.intonationCourse == null) tuner.beginIntonation(0);
      if (!tuner.isListening) tuner.start(confirmedGap: true);
    });
  }

  @override
  void dispose() {
    // Closed by the dim or a swipe: the tuner still returns to its mode.
    final tuner = _app.tuner;
    if (tuner.intonationCourse != null && _app.sheet?.kind != 'intonation') {
      WidgetsBinding.instance.addPostFrameCallback((_) => tuner.endIntonation());
    }
    super.dispose();
  }

  TunerController get tuner => _app.tuner;
  int get courses => tuner.courses.length;

  /// Strings go from the low one — the usual setup order.
  int get course => tuner.intonationCourse ?? 0;

  void _close() {
    tuner.endIntonation();
    _app.sheet = null;
  }

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final step = tuner.intonationStep;
    final Widget button;
    if (step.isResult && course + 1 < courses) {
      button = SheetButton(title: 'Следующая струна', onTap: () => tuner.beginIntonation(course + 1));
    } else if (step.isResult) {
      button = SheetButton(title: 'Готово', onTap: _close);
    } else {
      // Canvas: a quiet card-coloured button, 50 pt.
      button = Pressable(
        label: 'Начать заново',
        onTap: tuner.repeatIntonationStep,
        child: SizedBox(
          height: 50,
          child: ShapeBox(
            shape: SwiftShape.capsule,
            fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
            strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
            child: Center(child: Text('Начать заново', style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody))),
          ),
        ),
      );
    }
    // Canvas «Проверка мензуры» (FixTunerIntonation): the sheet from 356 — 488 pt.
    return DesignSheet(
      title: 'Проверка мензуры',
      height: 488,
      close: _close,
      footer: [Expanded(child: button)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stringPicker(),
          const SizedBox(height: 14),
          _stepCard(),
          if (tuner.intonationResults.isNotEmpty) ...[const SizedBox(height: 14), _results()],
          const SizedBox(height: 14),
          Padding(
            // line-height 1.4 on 13 pt: 18.2 pt lines (Inter's own 15.7).
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.23),
            child: SwiftText(_note, lineSpacing: 2.47, style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary)),
          ),
        ],
      ),
    );
  }

  String get _note => switch (tuner.intonationStep.kind) {
    0 => 'Дальше — 12-й лад обычным нажатием. Седло двигают на ослабленной струне.',
    1 => 'Нажимайте обычно, не флажолетом. Седло двигают на ослабленной струне.',
    _ => 'Седло двигают на ослабленной струне, потом снова настраивают и проверяют.',
  };

  /// Canvas: all strings in one row (gap 6), 48 pt keys, radius 12, 15 pt — semibold ivory with a ring when chosen.
  Widget _stringPicker() => Row(
    children: [
      for (var c = 0; c < courses; c++) ...[if (c > 0) const SizedBox(width: 6), Expanded(child: _stringButton(c))],
    ],
  );

  Widget _stringButton(int c) {
    final selected = c == course;
    final name = tuner.stringName(StringRef(c));
    final measured = tuner.intonationResults[c] != null;
    return Pressable(
      label: 'Струна ${courses - c}, $name',
      selected: selected,
      onTap: () => tuner.beginIntonation(c),
      child: SizedBox(
        height: 48,
        child: ShapeBox(
          shape: const SwiftShape.rounded(12, continuous: true),
          fills: [SwiftFill(TruverColors.white(selected ? 0.09 : 0.04))],
          strokes: [SwiftStroke(selected ? TruverColors.selectedBorder : TruverColors.hairline, inside: true)],
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: swiftNotes(
                name,
                Typo.inter(
                  15,
                  selected ? TypoWeight.semibold : TypoWeight.medium,
                  selected ? TruverColors.textPrimary : (measured ? _resultColor(c) : TruverColors.textMuted),
                ),
                maxLines: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _resultColor(int c) {
    final cents = tuner.intonationResults[c];
    if (cents == null) return TruverColors.textTertiary;
    return _verdict(cents) == 'ok' ? TruverColors.inTune : (cents > 0 ? TruverColors.sharp : TruverColors.flat);
  }

  Widget _stepCard() {
    final name = tuner.stringName(StringRef(course));
    final step = tuner.intonationStep;
    final hint = tuner.intonationHint;
    return ShapeBox(
      shape: const SwiftShape.rounded(16, continuous: true),
      fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
      strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
      // Canvas card: padding 14 / 16, rows 10 apart — the step, a 4 pt progress line, the hint 13 pt.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (step == IntonationStep.open)
              _step(1, 'Сыграйте открытую струну', 'шаг 1 из 3 · струна ${courses - course} · $name')
            else if (step == IntonationStep.twelfth)
              _step(2, 'Сыграйте на 12-м ладу', 'шаг 2 из 3 · струна ${courses - course} · октава $name')
            else
              _result(step.cents),
            if (!step.isResult) ...[
              const SizedBox(height: 10),
              _ProgressBar(value: tuner.intonationProgress),
              const SizedBox(height: 10),
              swiftNotes(
                hint != null
                    ? '$hint — нужна ${step == IntonationStep.open ? 'открытая ${courses - course}-я струна' : 'октава на 12-м ладу'}'
                    : (tuner.intonationProgress > 0 ? 'Держите ноту…' : 'Слушаю…'),
                Typo.inter(13, TypoWeight.regular, hint == null ? TruverColors.textTertiary : TruverColors.sharp),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _step(int number, String title, String detail) => Row(
    children: [
      // A 28 pt ivory disc with the step number (14 semibold).
      SizedBox(
        width: 28,
        height: 28,
        child: ShapeBox(
          shape: SwiftShape.circle,
          fills: const [SwiftFill(TruverColors.beat)],
          child: Center(child: Text('$number', style: Typo.inter(14, TypoWeight.semibold, TruverColors.background))),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SwiftText(title, style: Typo.inter(16, TypoWeight.medium, TruverColors.textPrimary)),
            const SizedBox(height: 2),
            swiftNotes(detail, Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
          ],
        ),
      ),
    ],
  );

  Widget _result(double cents) {
    final r = _intonation(cents);
    final verdict = r.$1;
    final mm = r.$2.abs();
    final color = verdict == 'ok' ? TruverColors.inTune : (cents > 0 ? TruverColors.sharp : TruverColors.flat);
    final title = Typo.inter(17, TypoWeight.medium, TruverColors.textPrimary);
    final caption = Typo.caption.copyWith(color: TruverColors.textSecondary);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwiftText('${_signed(cents)} ц', style: Typo.monospacedDigit(Typo.inter(40, TypoWeight.semibold, color))),
          const SizedBox(height: 6),
          if (verdict == 'ok')
            SwiftText('В порядке — 12-й лад совпадает с октавой', style: title)
          else if (verdict == 'awayFromNeck') ...[
            SwiftText('Седло от грифа · ≈ ${_millimetres(mm)}', style: title),
            const SizedBox(height: 6),
            SwiftText('12-й лад выше октавы: струна коротковата', style: caption),
          ] else ...[
            SwiftText('Седло к грифу · ≈ ${_millimetres(mm)}', style: title),
            const SizedBox(height: 6),
            SwiftText('12-й лад ниже октавы: струна длинновата', style: caption),
          ],
          const SizedBox(height: 6 + 4),
          Pressable(
            onTap: tuner.repeatIntonationStep,
            child: const Chip(text: 'Измерить ещё раз', style: ChipStyle.muted),
          ),
        ],
      ),
    );
  }

  Widget _results() {
    final done = tuner.intonationResults.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(text: 'Измерено'),
        Card(children: [for (var i = 0; i < done.length; i++) _resultRow(done[i], i < done.length - 1)]),
      ],
    );
  }

  Widget _resultRow(int c, bool divider) {
    final cents = tuner.intonationResults[c] ?? 0;
    final (verdict, shift) = _intonation(cents, course: c);
    final mm = shift.abs();
    return CardRow(
      title: 'Струна ${courses - c} · ${tuner.stringName(StringRef(c))}',
      subtitle: verdict == 'ok' ? 'в порядке' : '${verdict == 'awayFromNeck' ? 'от грифа' : 'к грифу'} ≈ ${_millimetres(mm)}',
      showsDivider: divider,
      trailing: Text('${_signed(cents)} ц', style: Typo.monospacedDigit(TextStyle(color: _resultColor(c)))),
    );
  }

  /// Verdict and saddle move of the core's `Intonation` for the string's own scale (fanned frets — PR-7).
  (String, double) _intonation(double cents, {int? course}) {
    final c = course ?? this.course;
    try {
      final r = _app.core?.call('tuner.intonation', {'cents': cents, 'course': c});
      if (r is Map) return (r['verdict'] as String, (r['saddleShift'] as num).toDouble());
    } catch (_) {}
    final scale = c < tuner.courses.length ? tuner.courses[c].scaleLength : 648.0;
    return (_verdict(cents), cents * scale * 0.6931471805599453 / 1200);
  }

  static String _verdict(double cents) => cents.abs() <= 2 ? 'ok' : (cents > 0 ? 'awayFromNeck' : 'towardsNeck');

  static String _millimetres(double mm) => '${mm.toStringAsFixed(1).replaceAll('.', ',')} мм';

  static String _signed(double v) {
    final r = (v * 10).round() / 10;
    final text = r.abs().toStringAsFixed(1).replaceAll('.', ',');
    return '${r > 0 ? '+' : (r < 0 ? '−' : '')}$text';
  }
}

/// iOS `ProgressView(value:)` tinted with the primary text colour: a 4 pt capsule track.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Semantics(
    value: '${(value * 100).round()} %',
    child: SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.1))]),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: constraints.maxWidth * value.clamp(0, 1),
              child: const ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.beat)]),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Port of Truver/Sources/Features/Practice/PlayCheckCharts.swift
///
/// PL-4 (corrected canvas «Занятия — графики»): the ceiling and the spread of the last day as numbers, the ceiling
/// over days (weeks once there is a month of data) as a line with three gridlines, and the heat map of the beats
/// below — where you rush, where you drag. No badges or points (PL-6).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../metronome/play_check_controller.dart';
import 'practice_session_controller.dart';

class ChartPoint {
  ChartPoint(this.date, this.ceiling, this.spread);
  final DateTime date;
  final double ceiling;
  final double spread;
}

class PlayCheckCharts extends StatelessWidget {
  const PlayCheckCharts({super.key, required this.history});
  final List<PlayAttempt> history;

  bool get byWeeks {
    if (history.isEmpty) return false;
    return history.last.date.difference(history.first.date).inSeconds > 21 * 86400;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Start of the week (Monday, the Russian calendar).
  static DateTime _week(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  List<ChartPoint> get points {
    final weeks = byWeeks;
    final groups = <DateTime, List<PlayAttempt>>{};
    for (final a in history) {
      groups.putIfAbsent(weeks ? _week(a.date) : _day(a.date), () => []).add(a);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final day in keys)
        ChartPoint(
          day,
          groups[day]!.map((a) => a.ceiling ?? a.endBPM).fold(0.0, math.max),
          groups[day]!.fold(0.0, (s, a) => s + a.spread) / groups[day]!.length,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pts = points;
    final last = pts.isEmpty ? null : pts.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (last != null)
          Row(
            children: [
              Expanded(child: PracticeStat(caption: 'Потолок темпа', value: '${last.ceiling.round()}')),
              const SizedBox(width: 10),
              Expanded(child: PracticeStat(caption: 'Разброс', value: '${last.spread.round()} мс')),
            ],
          ),
        if (pts.length < 2)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, top: 12),
            child: SwiftText(
              'График появится со второго дня занятий с проверкой игры',
              style: Typo.caption.copyWith(color: TruverColors.textTertiary),
            ),
          )
        else
          Padding(padding: const EdgeInsets.only(top: 18.5), child: CeilingChart(points: pts, byWeeks: byWeeks)),
        Padding(padding: const EdgeInsets.only(top: 20), child: _HeatMap(history: history)),
      ],
    );
  }
}

/// Canvas stat card of the practice tab: padding 12 × 14 inside a 1 pt border (CSS content box), caption 12,
/// value 26 light 2 pt below.
class PracticeStat extends StatelessWidget {
  const PracticeStat({super.key, required this.caption, required this.value});
  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) => PracticeCard(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwiftText(caption, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
        const SizedBox(height: 2),
        SwiftText(value, maxLines: 1, softWrap: false, style: Typo.inter(26, TypoWeight.light, TruverColors.textPrimary)),
      ],
    ),
  );
}

/// The canvas card: radius 16 (continuous), card fill, hairline inside.
class PracticeCard extends StatelessWidget {
  const PracticeCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.fill, this.border, this.clip = false});
  final Widget child;
  final EdgeInsets padding;
  final Color? fill;
  final Color? border;
  final bool clip;

  @override
  Widget build(BuildContext context) => ShapeBox(
    shape: const SwiftShape.rounded(16, continuous: true),
    fills: [fill == null ? const SwiftFill.gradient(TruverGradients.cardFill) : SwiftFill(fill!)],
    strokes: [SwiftStroke(border ?? TruverColors.hairline, inside: true)],
    clip: clip,
    child: Padding(padding: padding, child: child),
  );
}

/// The canvas chart card: caption, a 310 × 140 plot (the canvas SVG's `viewBox="-4 -6 330 150"` scaled by 0.9333:
/// 300 units of plot, three gridlines 60 units apart labelled on the right), first date and «сегодня» under it.
class CeilingChart extends StatelessWidget {
  const CeilingChart({super.key, required this.points, required this.byWeeks});
  final List<ChartPoint> points;
  final bool byWeeks;

  /// Three gridlines: the smallest step (5, 10, 15, 20, 25, 50…) whose range from a multiple of it covers the data.
  static (double, double) grid(List<double> values) {
    final lo = values.fold(double.infinity, math.min), hi = values.fold(-double.infinity, math.max);
    for (final step in const <double>[5, 10, 15, 20, 25, 30, 40, 50, 75, 100]) {
      final low = (lo / step).floorToDouble() * step;
      if (low + 2 * step >= hi) return (low, step);
    }
    return ((lo / 100).floorToDouble() * 100, math.max(100.0, ((hi - lo) / 200).ceilToDouble() * 100));
  }

  static const _months = ['янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.', 'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'];

  /// `.dateTime.day().month(.abbreviated)` in Russian: «10 нояб.».
  static String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  String get _title {
    final n = points.length;
    return byWeeks
        ? 'Потолок темпа, BPM · $n ${PracticeSessionController.plural(n, 'неделя', 'недели', 'недель')}'
        : 'Потолок темпа, BPM · $n ${PracticeSessionController.plural(n, 'день', 'дня', 'дней')}';
  }

  String get _lastLabel {
    final last = points.last.date, now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (DateTime(last.year, last.month, last.day) == today || (byWeeks && now.difference(last).inDays < 7)) return 'сегодня';
    return shortDate(last);
  }

  @override
  Widget build(BuildContext context) {
    final label = Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary);
    return Semantics(
      label: 'Потолок темпа: от ${points.first.ceiling.toInt()} до ${points.last.ceiling.toInt()}',
      excludeSemantics: true,
      child: PracticeCard(
        padding: const EdgeInsets.only(left: 15, right: 15, top: 13, bottom: 14.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwiftText(_title, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 310, height: 140, child: CustomPaint(painter: _CeilingPainter(points))),
            ),
            // margin-top 2 + the descender room the inline SVG leaves in its line box (≈ 3.7).
            const SizedBox(height: 5.7),
            Row(
              children: [
                SwiftText(shortDate(points.first.date), style: label),
                const Spacer(),
                SwiftText(_lastLabel, style: label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CeilingPainter extends CustomPainter {
  _CeilingPainter(this.points);
  final List<ChartPoint> points;

  static const k = 140.0 / 150.0;
  static double _x(double x) => 1 + (x + 4) * k;
  static double _y(double y) => (y + 6) * k;

  @override
  void paint(Canvas canvas, Size size) {
    final (low, step) = CeilingChart.grid([for (final p in points) p.ceiling]);
    final gridPaint = Paint()
      ..color = TruverColors.white(0.07)
      ..strokeWidth = k;
    for (var i = 0; i < 3; i++) {
      final y = i * 60.0;
      canvas.drawLine(Offset(_x(0), _y(y)), Offset(_x(300), _y(y)), gridPaint);
      final value = low + step * (2 - i);
      final tp = TextPainter(
        text: TextSpan(text: '${value.toInt()}', style: Typo.inter(10 * k, TypoWeight.regular, TruverColors.textTertiary)),
        textDirection: TextDirection.ltr,
      )..layout();
      // SVG text sits on its baseline.
      final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(_x(306), _y(y + 3) - baseline));
    }
    final n = points.length;
    final pts = [
      for (var i = 0; i < n; i++)
        Offset(_x(n > 1 ? i * 300 / (n - 1) : 0), _y((low + 2 * step - points[i].ceiling) / step * 60)),
    ];
    final path = Path()..addPolygon(pts, false);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * k
        ..strokeJoin = StrokeJoin.miter
        ..color = TruverColors.textPrimary,
    );
    final dot = Paint()..color = TruverColors.textPrimary;
    for (final p in pts) {
      canvas.drawCircle(p, 2.5 * k, dot);
    }
  }

  @override
  bool shouldRepaint(_CeilingPainter old) => old.points != points;
}

class _HeatMap extends StatelessWidget {
  const _HeatMap({required this.history});
  final List<PlayAttempt> history;

  @override
  Widget build(BuildContext context) {
    final recent = history.length > 20 ? history.sublist(history.length - 20) : history;
    final sums = <int, (double, int)>{};
    for (final a in recent) {
      a.perBeat.forEach((beat, d) {
        final s = sums[beat] ?? (0.0, 0);
        sums[beat] = (s.$1 + d, s.$2 + 1);
      });
    }
    final beats = sums.keys.toList()..sort();
    final caption = Typo.caption.copyWith(color: TruverColors.textTertiary);
    return PracticeCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwiftText('Доли: где спешите и где тянете · последние ${recent.length}', style: caption),
          const SizedBox(height: 8),
          if (beats.isEmpty)
            SwiftText('Появится после попыток с проверкой игры', style: caption)
          else ...[
            Row(
              children: [
                for (var i = 0; i < beats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: _cell(beats[i], sums[beats[i]]!)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SwiftText('мс от доли: «−» — раньше, «+» — позже', style: Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _cell(int beat, (double, int) sum) {
    final v = sum.$1 / sum.$2;
    final k = math.min(1.0, v.abs() / 25);
    final ms = v.abs().round();
    return Semantics(
      label: 'Доля ${beat + 1}: ${v < 0 ? 'спешите' : 'тянете'} $ms мс',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: ShapeBox(
          shape: const SwiftShape.rounded(8),
          fills: [SwiftFill((v < 0 ? TruverColors.sharp : TruverColors.flat).withValues(alpha: 0.12 + 0.6 * k))],
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwiftText(
                  '${v < 0 ? '−' : '+'}$ms',
                  style: Typo.monospacedDigit(Typo.inter(12, TypoWeight.semibold, TruverColors.textPrimary)),
                ),
                const SizedBox(height: 2),
                SwiftText('${beat + 1}', style: Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

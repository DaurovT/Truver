/// Port of Truver/Sources/Features/Practice/TrainerNeck.swift
///
/// The trainer's neck (corrected canvas, «Тренажёр грифа»): flat and dark like Guitar Pro — graphite board, metal
/// fret wires, blue-grey strings, round inlays — fret numbers on the left and a scroll bar on the right. A 350 pt
/// block: numbers 0–18, the 310 pt board from 22, the bar at 346. The window shows `lower…upper` frets (the wire
/// before `lower` at the top edge, the centre of wire `upper` at the bottom edge); the whole neck scrolls.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';

enum TrainerDotStyle { question, right, rightSmall }

class TrainerDot {
  const TrainerDot({required this.course, required this.fret, required this.label, required this.style});
  final int course;
  final int fret;
  final String label;
  final TrainerDotStyle style;
}

class TrainerHighlight {
  const TrainerHighlight({required this.course, required this.right});
  final int course;
  final bool right;
}

/// Geometry of the canvas board: wire n's centre at `L·(1 − 2^(−n/12)) − 0.8` along the neck.
class TrainerNeckGeometry {
  const TrainerNeckGeometry({
    required this.courses,
    required this.fretCount,
    required this.lower,
    required this.upper,
    required this.height,
    required this.leftHanded,
  });

  final int courses;
  final int fretCount;
  final int lower;
  final int upper;
  final double height;
  final bool leftHanded;

  static const inner = 302.0;

  static double d(num n) => 1 - math.pow(2, -n / 12).toDouble();
  double get scale => (height + 0.8) / (d(upper) - d(lower - 1));
  double get initialScroll => scale * d(lower - 1);
  double get maxScroll => math.max(initialScroll, scale * d(fretCount) + 12 - height);

  /// Centre of wire n in content coordinates (wire 0 is the nut's place).
  double wire(int n) => scale * d(n) - 0.8;
  double cell(int fret) => fret == 0 ? 5 : (wire(fret - 1) + wire(fret)) / 2;

  /// Fractional fret at a content y.
  double fretAt(double y) => -12 * math.log(math.max(1e-6, 1 - y / scale)) / math.ln2;

  /// String centre in board coordinates (the inner board starts at 4, strings 26 in from its sides).
  double x(int course) {
    final spacing = courses > 1 ? (inner - 52) / (courses - 1) : 0.0;
    final index = leftHanded ? courses - 1 - course : course;
    return 4 + 26 + index * spacing;
  }
}

class TrainerNeck extends StatefulWidget {
  const TrainerNeck({
    super.key,
    required this.courses,
    required this.fretCount,
    required this.lower,
    required this.upper,
    required this.height,
    this.leftHanded = false,
    this.dots = const [],
    this.highlight,
  });

  final int courses;
  final int fretCount;
  final int lower;
  final int upper;
  final double height;
  final bool leftHanded;
  final List<TrainerDot> dots;
  final TrainerHighlight? highlight;

  static const width = 350.0;
  static const boardX = 22.0;
  static const boardWidth = 310.0;
  static const stringWidths = [4.4, 4.0, 3.6, 3.1, 2.7, 2.3, 1.9, 1.6, 1.25, 1.0];

  @override
  State<TrainerNeck> createState() => _TrainerNeckState();
}

class _TrainerNeckState extends State<TrainerNeck> {
  double? _scroll;

  TrainerNeckGeometry get _g => TrainerNeckGeometry(
    courses: widget.courses,
    fretCount: widget.fretCount,
    lower: widget.lower,
    upper: widget.upper,
    height: widget.height,
    leftHanded: widget.leftHanded,
  );

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final s = _scroll ?? g.initialScroll;
    final h = widget.height;
    const bx = TrainerNeck.boardX, bw = TrainerNeck.boardWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => setState(() {
        _scroll = ((_scroll ?? g.initialScroll) - d.delta.dy).clamp(0.0, g.maxScroll);
      }),
      child: SizedBox(
        width: TrainerNeck.width,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var fret = 1; fret <= math.max(1, widget.fretCount); fret++)
              if (g.cell(fret) - s > 2 && g.cell(fret) - s < h - 2) _label(fret, g.cell(fret) - s),
            Positioned(left: bx, top: 0, width: bw, height: h, child: _board(g, s)),
            for (final dot in widget.dots)
              Positioned(
                left: bx + g.x(dot.course) - 30,
                top: g.cell(dot.fret) - s - 30,
                width: 60,
                height: 60,
                child: Center(child: _NoteDot(dot)),
              ),
            if (s > 0.5)
              const Positioned(
                left: bx,
                top: 0,
                width: bw,
                height: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0D0E10), Color(0x000D0E10)],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: bx,
              top: h - 30,
              width: bw,
              height: 30,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000D0E10), Color(0xFF0D0E10)],
                  ),
                ),
              ),
            ),
            if (widget.highlight != null)
              Positioned(
                // Canvas: 30 × height with a 1 pt border outside (content box), left at the string − 15.
                left: bx + g.x(widget.highlight!.course) - 15,
                top: 0,
                width: 32,
                height: h + 2,
                child: ShapeBox(
                  shape: const SwiftShape.rounded(16),
                  fills: [SwiftFill(widget.highlight!.right ? TruverColors.inTune.withValues(alpha: 0.08) : const Color(0x1A8FC4FF))],
                  strokes: const [SwiftStroke(Color(0x598FC4FF), inside: true)],
                ),
              ),
            _scrollBar(g, s),
          ],
        ),
      ),
    );
  }

  Widget _label(int fret, double y) {
    const inlays = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24];
    final style = Typo.inter(
      11,
      const [5, 12, 17, 24].contains(fret) ? TypoWeight.semibold : TypoWeight.regular,
      inlays.contains(fret) ? TruverColors.textSecondary : TruverColors.white(0.22),
    );
    return Positioned(
      left: 0,
      top: y - 15,
      width: 18,
      height: 30,
      child: Align(
        alignment: Alignment.centerRight,
        child: SwiftText('$fret', maxLines: 1, softWrap: false, style: style),
      ),
    );
  }

  Widget _board(TrainerNeckGeometry g, double s) => CustomPaint(
    painter: _BoardPainter(g, s),
    size: Size(TrainerNeck.boardWidth, widget.height),
  );

  Widget _scrollBar(TrainerNeckGeometry g, double s) {
    final h = widget.height;
    final top = math.max(0.0, g.fretAt(s)), bottom = g.fretAt(s + h);
    final total = math.max(1, widget.fretCount).toDouble();
    final thumbTop = top / total * h;
    final thumbHeight = math.min(h - thumbTop, math.max(12.0, (bottom - top) / total * h));
    return Positioned(
      left: TrainerNeck.width - 4,
      top: 0,
      width: 4,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: ShapeBox(shape: const SwiftShape.rounded(2), fills: [SwiftFill(TruverColors.white(0.08))]),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: thumbTop,
            height: thumbHeight,
            child: const ShapeBox(shape: SwiftShape.rounded(2), fills: [SwiftFill(Color(0x99F6F3EC))]),
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.g, this.s);
  final TrainerNeckGeometry g;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    const inner = TrainerNeckGeometry.inner;
    final box = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    // 0 30px 60px rgba(0,0,0,0.8) under the board; 0 0 0 1px rgba(0,0,0,0.6) — a ring just outside it.
    canvas.drawRRect(
      box.shift(const Offset(0, 30)),
      Paint()
        ..color = const Color(0xCC000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawRRect(
      box.inflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x99000000),
    );
    canvas.drawRRect(box, Paint()..color = const Color(0xFF3A404A));
    final innerRect = Rect.fromLTWH(4, 0, inner, size.height);
    canvas.save();
    canvas.clipRect(innerRect);
    canvas.drawRect(innerRect, Paint()..color = const Color(0xFF2B2F36));
    final inlay = Paint()..color = const Color(0x66AAB3C0);
    for (final fret in const [3, 5, 7, 9, 12, 15, 17, 19, 21, 24]) {
      if (fret > g.fretCount) continue;
      final y = g.cell(fret) - s;
      if (y < -10 || y > size.height + 10) continue;
      final xs = fret % 12 == 0 ? const [4 + 90.0, 4 + 211.0] : const [4 + 151.0];
      for (final x in xs) {
        canvas.drawCircle(Offset(x, y), 5, inlay);
      }
    }
    for (var n = 1; n <= math.max(1, g.fretCount); n++) {
      final y = g.wire(n) - 2 - s;
      if (y < -6 || y > size.height + 2) continue;
      final rect = Rect.fromLTWH(4, y, inner, 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6B7380), Color(0xFFE3E8EF), Color(0xFF6B7380)],
          ).createShader(rect),
      );
    }
    const widths = TrainerNeck.stringWidths;
    final own = widths.sublist(math.max(0, widths.length - g.courses));
    for (var course = 0; course < g.courses; course++) {
      final w = course < own.length ? own[course] : 1.0;
      final plain = course >= g.courses - 2;
      final x = g.x(course);
      canvas.drawRect(Rect.fromLTWH(x - w / 2, 0, w, size.height), Paint()..color = Color(plain ? 0xFFB8C5D6 : 0xFF9FB0C6));
    }
    // Nut over the strings (0 4px 6px rgba(0,0,0,0.6)).
    if (s < 12) {
      final nut = Rect.fromLTWH(4, -s, inner, 10);
      canvas.drawRect(
        nut.shift(const Offset(0, 4)),
        Paint()
          ..color = const Color(0x99000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRect(nut, Paint()..color = const Color(0xFFDFE5EC));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.s != s || old.g.lower != g.lower || old.g.upper != g.upper || old.g.height != g.height || old.g.courses != g.courses;
}

class _NoteDot extends StatelessWidget {
  const _NoteDot(this.dot);
  final TrainerDot dot;

  @override
  Widget build(BuildContext context) {
    final size = dot.style == TrainerDotStyle.rightSmall ? 36.0 : 38.0;
    final right = dot.style != TrainerDotStyle.question;
    final style = Typo.inter(12, TypoWeight.bold, const Color(0xFF0C0D0F));
    return SizedBox(
      width: size,
      height: size,
      child: ShapeBox(
        shape: SwiftShape.circle,
        fills: [SwiftFill(right ? TruverColors.inTune.withValues(alpha: 0.95) : const Color(0xFAF6F3EC))],
        strokes: [SwiftStroke(right ? const Color(0xFFB8F5D2) : const Color(0xFFFFFFFF), width: 1.5, inside: true)],
        shadows: const [SwiftShadow(Color(0x8C000000), 7, y: 6)],
        child: Center(child: SwiftText.rich(Typo.notes(dot.label, style), style: style)),
      ),
    );
  }
}

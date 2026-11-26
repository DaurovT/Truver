/// Port of Truver/Sources/DesignSystem/Brand.swift
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'shapes.dart';
import 'theme.dart';
import 'typo.dart';

/// The Truver mark (canvas «Бренд»): a needle standing on the green mark — the moment «в строю». Rim, 24 ticks,
/// 22 green segments (9° every 15°) with a 36° gap at the top where the needle stands. No needle hub on purpose:
/// otherwise it reads as a clock.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.tint});

  /// One colour for the whole mark (empty states); null = ivory and green.
  final Color? tint;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Знак Truver',
        child: CustomPaint(painter: _BrandMarkPainter(tint), size: Size.infinite),
      );
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter(this.tint);
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = tint ?? TruverColors.textPrimary;
    final green = tint ?? TruverColors.inTune;
    final k = math.min(size.width, size.height) / 100;
    final c = Offset(size.width / 2, size.height / 2);
    const rad = math.pi / 180;
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    void arc(double radius, double from, double to, Paint paint) =>
        canvas.drawArc(Rect.fromCircle(center: c, radius: radius * k), from * rad, (to - from) * rad, false, paint);

    canvas.drawCircle(c, 45 * k, stroke(ink, 3.2 * k));
    final tick = stroke(ink.withValues(alpha: ink.a * (tint == null ? 0.5 : 1)), 4 * k);
    for (var i = 0; i < 24; i++) {
      final mid = -90.0 + i * 15;
      arc(40, mid - 0.45, mid + 0.45, tick);
    }
    final segment = stroke(green.withValues(alpha: green.a * 0.95), 5.5 * k);
    for (var i = 0; i < 22; i++) {
      final start = -72.0 + i * 15;
      arc(29, start, start + 9, segment);
    }
    final fill = Paint()..color = green;
    final marker = Path()
      ..moveTo(c.dx, c.dy + (13.5 - 50) * k)
      ..lineTo(c.dx - 5.5 * k, c.dy + (3.5 - 50) * k)
      ..lineTo(c.dx + 5.5 * k, c.dy + (3.5 - 50) * k)
      ..close();
    canvas.drawPath(marker, fill);
    canvas.drawRSuperellipse(
        RSuperellipse.fromRectAndRadius(Rect.fromLTWH(c.dx - 2.4 * k, c.dy + (13 - 50) * k, 4.8 * k, 16 * k), Radius.circular(2.4 * k)),
        fill);
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.tint != tint;
}

/// Word mark: "truver" in Inter Light with a small green triangle above the "v".
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = Typo.inter(size, TypoWeight.light, TruverColors.textPrimary).copyWith(letterSpacing: -0.035 * size);
    return Semantics(
      label: 'Truver',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flutter's word box ends one kerning (−0.035 em) short of SwiftUI's: measured against iOS, the word sat
          // 1 pt left of centre. The leading pad puts it back.
          Padding(padding: EdgeInsets.only(left: 0.035 * size), child: Text('tru', style: style)),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Text('v', style: style),
              // CSS: top −0.06 em of the inline «v» box, whose top is the text frame top (measured on the corrected canvas).
              Positioned(
                top: size * -0.06,
                child: CustomPaint(size: Size(size * 0.17, size * 0.13), painter: const TrianglePainter(TruverColors.inTune)),
              ),
            ],
          ),
          Text('er', style: style),
        ],
      ),
    );
  }
}

/// Port of `Triangle`: pointing down, filling its box.
class TrianglePainter extends CustomPainter {
  const TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(TrianglePainter old) => old.color != color;
}

/// Small metal bezel with a dark face (onboarding microphone step).
class MiniBezel extends StatelessWidget {
  const MiniBezel({super.key, this.size = 200, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inner = size * 0.8;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ShapeBox(
              shape: SwiftShape.circle,
              shadows: [SwiftShadow(TruverColors.black(0.8), 30, y: 30)],
              fills: const [SwiftFill.gradient(TruverGradients.metal)],
            ),
          ),
          SizedBox(
            width: inner,
            height: inner,
            child: ShapeBox(
              shape: SwiftShape.circle,
              fills: [
                SwiftFill.gradient(RadialGradient(
                  center: const Alignment(0, 0.38 * 2 - 1),
                  radius: size * 0.45 / inner,
                  colors: const [TruverColors.faceTop, Color(0xFF0B0B0C)],
                )),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

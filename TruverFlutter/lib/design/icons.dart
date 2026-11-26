/// Port of Truver/Sources/DesignSystem/Icons.swift
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Stroke icons drawn on the canvas's 24 × 24 grid (same outlines as the design).
enum AppIcon {
  tuner, fretboard, metronome, practice, gear, mic, micOff, waveform,
  chevronDown, chevronRight, chevronLeft, plus, minus, play, stop, check, list, sliders,
  close, timer, arrowUp, warning, refresh, trash, rename, search, pause, lock, music, repeatArrows, bluetooth, route, expand, strobe,
  /// Audio interface (canvas «Вход переключён»): a box with a jack.
  audioInterface;

  bool get filled => this == AppIcon.play || this == AppIcon.stop || this == AppIcon.pause;
}

/// The outline of an icon in `rect` (port of `IconShape.path(in:)`).
Path appIconPath(AppIcon icon, Rect rect) {
  final s = math.min(rect.width, rect.height) / 24;
  final ox = rect.center.dx - 12 * s, oy = rect.center.dy - 12 * s;
  Offset p(double x, double y) => Offset(ox + x * s, oy + y * s);
  final path = Path();

  void line(List<(double, double)> points, {bool close = false}) {
    if (points.isEmpty) return;
    path.moveTo(p(points[0].$1, points[0].$2).dx, p(points[0].$1, points[0].$2).dy);
    for (final pt in points.skip(1)) {
      final o = p(pt.$1, pt.$2);
      path.lineTo(o.dx, o.dy);
    }
    if (close) path.close();
  }

  void moveTo(double x, double y) {
    final o = p(x, y);
    path.moveTo(o.dx, o.dy);
  }

  void lineTo(double x, double y) {
    final o = p(x, y);
    path.lineTo(o.dx, o.dy);
  }

  // SwiftUI `addArc(…, clockwise:)` in y-down coordinates: `clockwise: false` sweeps towards increasing angles.
  void arc(double cx, double cy, double r, double from, double to, {required bool clockwise}) {
    final rad = math.pi / 180;
    double sweep;
    if (!clockwise) {
      sweep = (to - from) % 360;
      if (sweep == 0 && to != from) sweep = 360;
    } else {
      sweep = -((from - to) % 360);
      if (sweep == 0 && to != from) sweep = -360;
    }
    path.arcTo(Rect.fromCircle(center: p(cx, cy), radius: r * s), from * rad, sweep * rad, false);
  }

  void roundedRect(double x, double y, double w, double h, double r) {
    // SwiftUI `Path.addRoundedRect` defaults to the continuous (squircle) corner style.
    path.addRSuperellipse(RSuperellipse.fromRectAndRadius(Rect.fromLTWH(ox + x * s, oy + y * s, w * s, h * s), Radius.circular(r * s)));
  }

  void ellipse(double x, double y, double w, double h) {
    path.addOval(Rect.fromLTWH(ox + x * s, oy + y * s, w * s, h * s));
  }

  switch (icon) {
    case AppIcon.tuner:
      moveTo(4, 16);
      arc(12, 16, 8, 180, 0, clockwise: false);
      line([(12, 16), (15, 10)]);
    case AppIcon.fretboard:
      roundedRect(7, 3, 10, 18, 2);
      for (final double y in [8, 13, 18]) {
        line([(7, y), (17, y)]);
      }
    case AppIcon.metronome:
      line([(8, 21), (16, 21), (13.5, 4), (10.5, 4)], close: true);
      line([(12, 15), (17, 8)]);
    case AppIcon.practice:
      line([(4, 19), (4, 9)]);
      line([(10, 19), (10, 5)]);
      line([(16, 19), (16, 12)]);
      line([(21, 19), (3, 19)]);
    case AppIcon.gear:
      // The corrected canvas draws a toothed gear too (the user's decision over the old «sun» icon): its exact
      // polygon — 8 teeth, root radius 7.4, tip radius 9.6 — and a hole of radius 3.
      const pts = <(double, double)>[
        (12.00, 4.60), (13.87, 2.58), (15.67, 3.13), (16.11, 5.85), (17.23, 6.77), (19.98, 6.67), (20.87, 8.33), (19.26, 10.56),
        (19.40, 12.00), (21.42, 13.87), (20.87, 15.67), (18.15, 16.11), (17.23, 17.23), (17.33, 19.98), (15.67, 20.87), (13.44, 19.26),
        (12.00, 19.40), (10.13, 21.42), (8.33, 20.87), (7.89, 18.15), (6.77, 17.23), (4.02, 17.33), (3.13, 15.67), (4.74, 13.44),
        (4.60, 12.00), (2.58, 10.13), (3.13, 8.33), (5.85, 7.89), (6.77, 6.77), (6.67, 4.02), (8.33, 3.13), (10.56, 4.74),
      ];
      line(pts, close: true);
      ellipse(9, 9, 6, 6);
    case AppIcon.mic:
    case AppIcon.micOff:
      roundedRect(9, 3, 6, 11, 3);
      moveTo(6, 11);
      arc(12, 11, 6, 180, 0, clockwise: true);
      line([(12, 17), (12, 21)]);
      if (icon == AppIcon.micOff) line([(4, 4), (20, 20)]);
    case AppIcon.waveform:
      line([(3, 12), (6, 12), (8.5, 6), (12.5, 18), (15, 10), (16.5, 12), (21, 12)]);
    case AppIcon.chevronDown:
      line([(7, 9.5), (12, 14.5), (17, 9.5)]);
    case AppIcon.chevronRight:
      line([(9.5, 6), (15.5, 12), (9.5, 18)]);
    case AppIcon.chevronLeft:
      line([(14.5, 6), (8.5, 12), (14.5, 18)]);
    case AppIcon.plus:
      line([(12, 5), (12, 19)]);
      line([(5, 12), (19, 12)]);
    case AppIcon.minus:
      line([(5, 12), (19, 12)]);
    case AppIcon.play:
      line([(8, 5.5), (8, 18.5), (18.5, 12)], close: true);
    case AppIcon.stop:
      roundedRect(6.5, 6.5, 11, 11, 2.5);
    case AppIcon.repeatArrows:
      line([(4, 11), (4, 9), (7, 6), (18, 6)]);
      line([(15, 3), (18, 6), (15, 9)]);
      line([(20, 13), (20, 15), (17, 18), (6, 18)]);
      line([(9, 21), (6, 18), (9, 15)]);
    case AppIcon.lock:
      roundedRect(5.5, 11, 13, 9, 2);
      moveTo(8.5, 11);
      lineTo(8.5, 8);
      arc(12, 8, 3.5, 180, 360, clockwise: false);
      lineTo(15.5, 11);
    case AppIcon.route:
      line([(5, 18), (12, 12), (12, 12), (19, 6)]);
      ellipse(3, 16, 4, 4);
      ellipse(10, 10, 4, 4);
      ellipse(17, 4, 4, 4);
    case AppIcon.bluetooth:
      line([(7, 7.5), (17, 16.5), (12, 21), (12, 3), (17, 7.5), (7, 16.5)]);
    case AppIcon.music:
      line([(9, 18), (9, 6), (19, 4), (19, 16)]);
      ellipse(4.8, 15.8, 4.4, 4.4);
      ellipse(14.8, 13.8, 4.4, 4.4);
    case AppIcon.search:
      ellipse(4.5, 4.5, 13, 13);
      line([(16, 16), (20.5, 20.5)]);
    case AppIcon.pause:
      roundedRect(7, 5.5, 3.5, 13, 1);
      roundedRect(13.5, 5.5, 3.5, 13, 1);
    case AppIcon.close:
      line([(6.5, 6.5), (17.5, 17.5)]);
      line([(17.5, 6.5), (6.5, 17.5)]);
    case AppIcon.strobe:
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        line([(12 + 6 * math.cos(a), 12 + 6 * math.sin(a)), (12 + 9.5 * math.cos(a), 12 + 9.5 * math.sin(a))]);
      }
      ellipse(10.5, 10.5, 3, 3);
    case AppIcon.expand:
      line([(4, 9), (4, 4), (9, 4)]);
      line([(15, 4), (20, 4), (20, 9)]);
      line([(20, 15), (20, 20), (15, 20)]);
      line([(9, 20), (4, 20), (4, 15)]);
    case AppIcon.timer:
      ellipse(4.5, 5.5, 15, 15);
      line([(12, 9), (12, 13), (14.5, 15)]);
      line([(10, 3), (14, 3)]);
    case AppIcon.arrowUp:
      line([(12, 19), (12, 5)]);
      line([(6, 11), (12, 5), (18, 11)]);
    case AppIcon.warning:
      line([(12, 4), (21, 20), (3, 20)], close: true);
      line([(12, 10), (12, 14.5)]);
      line([(12, 17.2), (12, 17.5)]);
    case AppIcon.refresh:
      moveTo(19, 12);
      arc(12, 12, 7, 0, 314.4, clockwise: false);
      line([(19, 4.5), (19, 8.5), (15, 8.5)]);
    case AppIcon.trash:
      line([(5, 7), (19, 7)]);
      line([(10, 7), (10, 5), (14, 5), (14, 7)]);
      line([(7, 7), (8, 19), (16, 19), (17, 7)]);
    case AppIcon.rename:
      for (final double y in [7, 12, 17]) {
        line([(5, y), (19, y)]);
      }
      ellipse(7, 5, 4, 4);
    case AppIcon.check:
      line([(5, 12.5), (9.5, 17), (19, 7.5)]);
    case AppIcon.list:
      for (final double y in [7, 12, 17]) {
        line([(5, y), (19, y)]);
      }
    case AppIcon.audioInterface:
      roundedRect(3.5, 7, 17, 10, 2);
      ellipse(6, 10, 4, 4);
    case AppIcon.sliders:
      line([(4, 8), (20, 8)]);
      line([(4, 16), (20, 16)]);
      ellipse(7, 6, 4, 4);
      ellipse(13, 14, 4, 4);
  }
  return path;
}

/// Port of `Icon`: a stroked (or filled: play, stop, pause) icon in a `size` × `size` box.
class AppIconView extends StatelessWidget {
  const AppIconView(this.icon, {super.key, this.size = 24, this.lineWidth = 1.6, this.color = TruverColors.textBody});

  final AppIcon icon;
  final double size;
  final double lineWidth;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: AppIconPainter(icon, color: color, lineWidth: lineWidth * size / 24)),
        ),
      );
}

/// Paints an icon into its whole canvas; `lineWidth` is in points (already scaled to the size).
class AppIconPainter extends CustomPainter {
  AppIconPainter(this.icon, {required this.color, required this.lineWidth});

  final AppIcon icon;
  final Color color;
  final double lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = appIconPath(icon, Offset.zero & size);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (icon.filled) {
      paint.style = PaintingStyle.fill;
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(AppIconPainter old) => old.icon != icon || old.color != color || old.lineWidth != lineWidth;
}

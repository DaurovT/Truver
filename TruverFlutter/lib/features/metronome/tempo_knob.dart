/// Port of Truver/Sources/Features/Metronome/TempoKnob.swift
///
/// Tempo knob of the canvas (290 pt): a 270° scale with minor ticks every 3° and majors every 27°, the progress arc
/// from 20 to 400 BPM, a knurled ring, a brushed-metal ring with a pointer, and a dark face with the tempo.
/// Every size is the canvas size × `size / 290`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../design/theme.dart';
import '../../design/typo.dart';

class TempoKnob extends StatefulWidget {
  const TempoKnob({
    super.key,
    required this.bpm,
    this.size = 290,
    this.dimmed = false,
    this.caption = 'BPM · свайп по ручке',
    required this.onDrag,
    required this.onDoubleTap,
    this.onLongPress,
  });

  final double bpm;
  final double size;
  final bool dimmed;
  final String caption;
  final ValueChanged<double> onDrag;
  final VoidCallback onDoubleTap;

  /// `.onLongPressGesture(minimumDuration: 0.5)` of the screen (opens «Режимы»).
  final VoidCallback? onLongPress;

  @override
  State<TempoKnob> createState() => _TempoKnobState();
}

class _TempoKnobState extends State<TempoKnob> {
  Offset? _down;
  Offset? _lastPoint;
  bool _dragging = false;
  double _accumulated = 0;
  Timer? _longPress;
  bool _moved = false;

  double get _fraction => ((widget.bpm - 20) / 380).clamp(0.0, 1.0);

  bool _inside(Offset p) => (p - Offset(widget.size / 2, widget.size / 2)).distance <= widget.size / 2;

  // «Свайп по ручке» (canvas, PRD 6.2.6): up or right is faster, down or left is slower, 4 pt per BPM, anywhere on
  // the knob. Fast swipes go further (20 → 400 took five swipes); slow ones stay precise.
  void _pointerDown(PointerDownEvent e) {
    if (!_inside(e.localPosition)) return;
    _down = e.localPosition;
    _lastPoint = null;
    _dragging = false;
    _moved = false;
    _longPress?.cancel();
    if (widget.onLongPress != null) {
      _longPress = Timer(const Duration(milliseconds: 500), () {
        if (!_moved) widget.onLongPress!();
      });
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    final down = _down;
    if (down == null) return;
    // DragGesture(minimumDistance: 8): a light touch no longer moves the tempo.
    if (!_dragging && (e.localPosition - down).distance < 8) return;
    if ((e.localPosition - down).distance >= 10) {
      _moved = true;
      _longPress?.cancel();
    }
    _dragging = true;
    final last = _lastPoint;
    if (last != null) {
      final move = (e.localPosition.dx - last.dx) - (e.localPosition.dy - last.dy);
      _accumulated += move / 4 * (move.abs() > 12 ? 2 : 1);
      final whole = _accumulated.truncateToDouble();
      if (whole != 0) {
        _accumulated -= whole;
        widget.onDrag(whole);
      }
    }
    _lastPoint = e.localPosition;
  }

  void _pointerEnd() {
    _longPress?.cancel();
    _down = null;
    _lastPoint = null;
    _dragging = false;
    _accumulated = 0;
  }

  @override
  void dispose() {
    _longPress?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.size / 290;
    final bpm = widget.bpm.toInt();
    return Semantics(
      label: 'Темп',
      value: '$bpm ударов в минуту',
      increasedValue: '${bpm + 1} ударов в минуту',
      decreasedValue: '${bpm - 1} ударов в минуту',
      onIncrease: () => widget.onDrag(1),
      onDecrease: () => widget.onDrag(-1),
      // A11Y-3: big steps too.
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Быстрее на 10'): () => widget.onDrag(10),
        const CustomSemanticsAction(label: 'Медленнее на 10'): () => widget.onDrag(-10),
      },
      excludeSemantics: true,
      child: Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: (_) => _pointerEnd(),
        onPointerCancel: (_) => _pointerEnd(),
        child: GestureDetector(
          onDoubleTap: widget.onDoubleTap,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _KnobPainter(fraction: _fraction, dimmed: widget.dimmed, k: k),
                  ),
                ),
                // Face: 164 at 63; tempo 70 extra-light in a 63 pt frame, caption 12 six points below.
                Positioned(
                  left: 63 * k,
                  top: 63 * k,
                  width: 164 * k,
                  height: 164 * k,
                  // Measured on the iOS screenshots (100, 142): SwiftUI sets the tempo and the caption 1.4 pt right of
                  // the face's centre and 0.8 pt higher than a centred column.
                  child: Transform.translate(
                    offset: Offset(1.4 * k, -0.8 * k),
                    child: Center(
                      child: MediaQuery.withNoTextScaling(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 63 * k,
                              child: OverflowBox(
                                maxHeight: double.infinity,
                                maxWidth: double.infinity,
                                child: Opacity(
                                  opacity: widget.dimmed ? 0.45 : 1,
                                  child: Text(
                                    '$bpm',
                                    softWrap: false,
                                    style: Typo.monospacedDigit(
                                      Typo.fixed(
                                        70 * k,
                                        TypoWeight.extraLight,
                                        TruverColors.textPrimary,
                                      ).copyWith(letterSpacing: -0.04 * 70 * k),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 6 * k),
                            Text(widget.caption, softWrap: false, style: Typo.fixed(12 * k, TypoWeight.regular, TruverColors.textTertiary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({required this.fraction, required this.dimmed, required this.k});

  final double fraction;
  final bool dimmed;
  final double k;

  static const _deg = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(145 * k, 145 * k);
    _scale(canvas, c);
    _knob(canvas, c);
  }

  // MARK: Scale (svg 290 × 290, arc r 138, pathLength 270 — one dash unit is one degree of the arc)

  void _scale(Canvas canvas, Offset c) {
    final rect = Rect.fromCircle(center: c, radius: 138 * k);
    void ticks(double every, double length, double width, Color color) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color;
      for (var a = 0.0; a < 270; a += every) {
        final len = math.min(length, 270 - a);
        if (len <= 0) continue;
        canvas.drawArc(rect, (135 + a) * _deg, len * _deg, false, paint);
      }
    }

    ticks(3, 0.5, 8 * k, const Color(0xFFE9E6DF).withValues(alpha: 0.22));
    ticks(27, 0.8, 12 * k, const Color(0xFFE9E6DF).withValues(alpha: 0.6));
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        135 * _deg,
        270 * fraction * _deg,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * k
          ..strokeCap = StrokeCap.round
          ..color = TruverColors.beat.withValues(alpha: dimmed ? 0.45 : 1),
      );
    }
  }

  // MARK: Knob (240 at 25; metal 222 at 34; face 164 at 63)

  /// The knurl's AngularGradient: 72 pairs of hard stops. CoreGraphics renders a conic gradient through a 256-entry
  /// colour table (sampled at entry centres, linearly interpolated) — measured on the iOS screenshot to ±3 levels —
  /// so the stripes come out soft, every other one a little lighter. The same table here.
  static Color _knurlAt(double location) => (location * 360) % 5 < 2.5 ? const Color(0xFF33363B) : const Color(0xFF4F5359);
  static final List<double> _knurlStops = [0, for (var i = 0; i < 256; i++) (i + 0.5) / 256, 1];
  static final List<Color> _knurlColors = () {
    final table = [for (var i = 0; i < 256; i++) _knurlAt((i + 0.5) / 256)];
    final wrap = Color.lerp(table.last, table.first, 0.5)!;
    return [wrap, ...table, wrap];
  }();

  void _knob(Canvas canvas, Offset c) {
    // Knurl with its shadow (black 0.9, radius 35, y 34) and the outer 1 pt black ring.
    canvas.drawCircle(
      c.translate(0, 34 * k),
      121 * k,
      Paint()
        ..color = TruverColors.black(0.9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 35 * k),
    );
    final knurlRect = Rect.fromCircle(center: c, radius: 120 * k);
    canvas.drawCircle(
      c,
      120 * k,
      Paint()
        ..shader = SweepGradient(
          colors: _knurlColors,
          stops: _knurlStops,
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(knurlRect),
    );
    canvas.drawCircle(
      c,
      120.5 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * k
        ..color = TruverColors.black(0.8),
    );

    // Metal ring with a soft light edge one point down, masked to the ring.
    final metalRect = Rect.fromCircle(center: c, radius: 111 * k);
    canvas.drawCircle(c, 111 * k, Paint()..shader = TruverGradients.metal.createShader(metalRect));
    canvas.save();
    canvas.clipPath(Path()..addOval(metalRect));
    canvas.drawCircle(
      c.translate(0, 1 * k),
      110.5 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * k
        ..color = TruverColors.white(0.75)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 * k),
    );
    canvas.restore();

    // Face rings: 0 0 0 3px rgba(255,255,255,.35) under 0 0 0 2px #2a2c30.
    canvas.drawCircle(c, 85 * k, Paint()..color = TruverColors.white(0.35));
    canvas.drawCircle(c, 84 * k, Paint()..color = const Color(0xFF2A2C30));

    // Face: radial gradient from (0.5, 0.38), end radius 91.4, and an inner shadow from the bottom.
    final faceRect = Rect.fromCircle(center: c, radius: 82 * k);
    final faceCenter = Offset(faceRect.left + faceRect.width * 0.5, faceRect.top + faceRect.height * 0.38);
    canvas.drawCircle(
      c,
      82 * k,
      Paint()
        ..shader = const RadialGradient(
          colors: [TruverColors.faceTop, Color(0xFF0B0B0C)],
        ).createShader(Rect.fromCircle(center: faceCenter, radius: 91.4 * k)),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(faceRect));
    canvas.drawCircle(
      c.translate(0, 5 * k),
      82 * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12 * k
        ..color = TruverColors.black(0.95)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * k),
    );
    canvas.restore();

    // Pointer: 4 × 18, r 2, 13 pt from the knurl's top, turning about the knob centre.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate((-135 + 270 * fraction) * _deg);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -98 * k), width: 4 * k, height: 18 * k), Radius.circular(2 * k)),
      Paint()..color = const Color(0xFF1A1B1E),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.fraction != fraction || old.dimmed != dimmed || old.k != k;
}

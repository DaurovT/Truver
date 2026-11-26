/// Port of Truver/Sources/Features/Tuner/TunerDial.swift
///
/// The tuner instrument (canvas «Тюнер», 2026-11 «Fix» boards): brushed-metal bezel, knurled ring, dark face with
/// the scale and the green top marker, the deviation needle on the scale (1.2° per cent, ±50 c = ±60°), and an
/// inner strobe band in the deviation colour that turns with the deviation (6 °/s per cent, still within ±1 c).
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';

/// What the centre of the dial shows (one per tuner state of the canvas).
@immutable
sealed class DialCenter {
  const DialCenter();
}

/// `dimmed`: the waiting state keeps the target note at 25 % (canvas «Ожидание»).
class DialNote extends DialCenter {
  const DialNote({required this.name, required this.octave, required this.cents, required this.centsColor, required this.detail, this.dimmed = false});
  final String name;
  final String octave;
  final String cents;
  final Color centsColor;
  final String detail;
  final bool dimmed;

  @override
  bool operator ==(Object other) =>
      other is DialNote &&
      other.name == name &&
      other.octave == octave &&
      other.cents == cents &&
      other.centsColor == centsColor &&
      other.detail == detail &&
      other.dimmed == dimmed;

  @override
  int get hashCode => Object.hash(name, octave, cents, centsColor, detail, dimmed);
}

class DialMessage extends DialCenter {
  const DialMessage({this.icon, required this.iconColor, required this.title, this.detail});
  final AppIcon? icon;
  final Color iconColor;
  final String title;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is DialMessage && other.icon == icon && other.iconColor == iconColor && other.title == title && other.detail == detail;

  @override
  int get hashCode => Object.hash(icon, iconColor, title, detail);
}

class DialListening extends DialCenter {
  const DialListening();

  @override
  bool operator ==(Object other) => other is DialListening;

  @override
  int get hashCode => 1;
}

class DialDone extends DialCenter {
  const DialDone({required this.detail});
  final String detail;

  @override
  bool operator ==(Object other) => other is DialDone && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;
}

class DialReference extends DialCenter {
  const DialReference({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  bool operator ==(Object other) => other is DialReference && other.title == title && other.detail == detail;

  @override
  int get hashCode => Object.hash(title, detail);
}

/// TU-10 strobe view (canvas «Тюнер — строб»): a lighter 64 pt note with the octave inline and one line.
class DialStrobeNote extends DialCenter {
  const DialStrobeNote({required this.name, required this.octave, required this.line, required this.color});
  final String name;
  final String octave;
  final String line;
  final Color color;

  @override
  bool operator ==(Object other) => other is DialStrobeNote && other.name == name && other.octave == octave && other.line == line && other.color == color;

  @override
  int get hashCode => Object.hash(name, octave, line, color);
}

/// Note text (system ♯ ♭) with SwiftUI's line box (`SwiftText`), for texts stacked in columns.
Widget swiftNotes(String text, TextStyle style, {int? maxLines, TextAlign? textAlign}) =>
    SwiftText.rich(Typo.notes(text, style), style: style, maxLines: maxLines, textAlign: textAlign);

/// Point size of the note in the tuner's centre (5.1.4, core `NoteFormatter.dialSize`): 96 for 1–2 characters,
/// 72 for 3–4, 60 for 5+.
double dialNoteSize(String text) {
  final n = text.characters.length;
  return n <= 2 ? 96 : (n <= 4 ? 72 : 60);
}

/// Rotation of the strobe band (core `TruverDSP.StrobeRotation`, a display accumulator): degrees per second =
/// deviation in cents × 6, at most 300 °/s; within ±1 cent the band stands still. The angle accumulates, so the
/// band never jumps.
class StrobeRotation {
  double angle = 0;
  Duration? _last;

  static double speed(double cents) => cents.abs() <= 1 ? 0 : (cents * 6).clamp(-300, 300).toDouble();

  /// Advances to the frame time `time` at the speed for `cents`; returns the angle in degrees (0..<360).
  double advance(double cents, Duration time) {
    final last = _last;
    _last = time;
    final dt = last == null ? 0.0 : math.min(0.1, (time - last).inMicroseconds / 1e6);
    angle = (angle + speed(cents) * dt) % 360;
    if (angle < 0) angle += 360;
    return angle;
  }
}

/// Runs `builder` every display frame with the frame's elapsed time (SwiftUI `TimelineView(.animation)`).
class FrameTicker extends StatefulWidget {
  const FrameTicker({super.key, required this.builder, this.enabled = true});
  final Widget Function(BuildContext context, Duration elapsed) builder;
  final bool enabled;

  @override
  State<FrameTicker> createState() => _FrameTickerState();
}

class _FrameTickerState extends State<FrameTicker> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => setState(() => _elapsed = elapsed));
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(FrameTicker old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_ticker.isActive) _ticker.start();
    if (!widget.enabled && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _elapsed);
}

/// Seconds since the app started — the shared clock of the looping animations (SwiftUI uses the wall clock).
double _clock(Duration elapsed) => elapsed.inMicroseconds / 1e6;

class TunerDial extends StatefulWidget {
  const TunerDial({
    super.key,
    required this.center,
    this.needle,
    this.color,
    this.bandCents,
    this.glow = false,
    this.phase,
    this.strobeView = false,
    this.progress,
    this.countdownUntil,
    this.frozen = false,
    this.bandAngle = 0,
  });

  final DialCenter center;

  /// Needle deviation in cents; null = no needle.
  final double? needle;

  /// Deviation colour of the needle and the band; null = the idle band (white 8 %).
  final Color? color;

  /// Deviation that turns the band; null = still.
  final double? bandCents;
  final bool glow;

  /// TU-10 strobe view: the band stands at the signal phase (turns as the string drifts).
  final double? phase;
  final bool strobeView;

  /// «Эталон»: the remaining part of the 3 s countdown as a light ring over the band.
  final double? progress;

  /// Live countdown: the ring shrinks until this moment (3 s of the reference tone).
  final DateTime? countdownUntil;

  /// Screenshots (`-tunerDemo`): every animation stands at its first frame, as on the canvas render.
  final bool frozen;

  /// Band angle of a frozen screenshot (the canvas render catches the band 0.05 s into its spin).
  final double bandAngle;

  @override
  State<TunerDial> createState() => _TunerDialState();
}

class _TunerDialState extends State<TunerDial> {
  final _strobe = StrobeRotation();
  final _follower = SpringFollower();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = math.min(constraints.maxWidth, constraints.maxHeight);
      final s = size / 320;
      final reduce = Motion.reduced(context);
      final needle = widget.needle, color = widget.color;
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _DialBodyPainter(s: s)),
              ),
              if (widget.glow) _faceGlow(s, reduce),
              if (needle != null && color != null) _needle(needle, color, s, reduce),
              _strobeBand(s, reduce),
              if (widget.progress != null) _ring(widget.progress!, s),
              if (widget.countdownUntil != null)
                FrameTicker(builder: (context, _) => _ring(widget.countdownUntil!.difference(DateTime.now()).inMicroseconds / 3e6, s)),
              SizedBox(
                width: 188 * s,
                height: 188 * s,
                child: ShapeBox(shape: SwiftShape.circle, strokes: [SwiftStroke(TruverColors.white(0.07))]),
              ),
              SizedBox(
                width: 184 * s,
                height: 184 * s,
                child: Center(child: _content(s)),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// Canvas `progress`: a full ivory ring over the band (r 105, 8 pt) whose dash runs out from the top.
  Widget _ring(double value, double s) => SizedBox(
    width: 210 * s,
    height: 210 * s,
    child: CustomPaint(
      painter: _ProgressRingPainter(value: value.clamp(0.0, 1.0).toDouble(), width: 8 * s),
    ),
  );

  /// Canvas `glowpulse`: 0 0 28px 4px green 35 % at the middle of a 2.4 s breath (first frame — none).
  Widget _faceGlow(double s, bool reduce) {
    Widget halo(double a) => CustomPaint(
      painter: _GlowPainter(alpha: a, s: s),
    );
    if (widget.frozen || reduce) return Positioned.fill(child: halo(widget.frozen ? 0 : 0.35));
    return Positioned.fill(
      child: FrameTicker(
        builder: (context, elapsed) {
          final p = (_clock(elapsed) % 2.4) / 2.4;
          return halo(0.35 * (1 - math.cos(2 * math.pi * p)) / 2);
        },
      ),
    );
  }

  /// Canvas: a 4 × 15 bar (radius 2) at the top of the face, 7 pt from its edge, glowing 5 pt in its colour;
  /// 1.2° per cent (±50 c = ±60°), following the reading with the needle spring.
  Widget _needle(double cents, Color color, double s, bool reduce) {
    Widget bar(double value) => Positioned.fill(
      child: Transform.rotate(
        angle: 1.2 * value.clamp(-50.0, 50.0) * math.pi / 180,
        child: CustomPaint(
          painter: _NeedlePainter(color: color, s: s),
        ),
      ),
    );
    if (widget.frozen) return bar(cents);
    return Positioned.fill(
      child: FrameTicker(
        builder: (context, elapsed) {
          final v = _follower.step(cents.clamp(-50.0, 50.0).toDouble(), elapsed, reduceMotion: reduce);
          return Stack(children: [bar(v)]);
        },
      ),
    );
  }

  Widget _strobeBand(double s, bool reduce) {
    final color = widget.color;
    Widget band(double angle) => SizedBox(
      width: 210 * s,
      height: 210 * s,
      child: CustomPaint(
        painter: _StrobeBandPainter(
          s: s,
          color: color?.withValues(alpha: color.a * 0.9) ?? TruverColors.white(0.08),
          angle: angle,
        ),
      ),
    );
    if (widget.frozen) return band(widget.bandAngle);
    if (reduce) return band(0);
    if (widget.strobeView) return band(widget.phase ?? 0);
    final cents = widget.bandCents;
    if (cents != null) {
      return FrameTicker(builder: (context, elapsed) => band(_strobe.advance(cents, elapsed)));
    }
    return band(0);
  }

  /// Centre column of the canvas (184 × 184, flex column centred). Instrument text: fixed sizes (the large-text
  /// canvas keeps the dial at 96 / 22 / 12), Inter with system ♯ ♭.
  Widget _content(double s) {
    final center = widget.center;
    return MediaQuery.withNoTextScaling(
      child: switch (center) {
        DialNote() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: center.dimmed ? 0.25 : 1,
              child: NoteWithOctave(name: center.name, octave: center.octave, s: s),
            ),
            SizedBox(height: 6 * s),
            // Empty lines keep their min-height (26 / 15), so the waiting note sits where the reading's does.
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: 26 * s),
              child: Center(
                heightFactor: 1,
                child: center.cents.isEmpty
                    ? const SizedBox.shrink()
                    : swiftNotes(center.cents, Typo.fixed(22 * s, TypoWeight.medium, center.centsColor), maxLines: 1),
              ),
            ),
            SizedBox(height: 4 * s),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: 15 * s),
              child: Center(
                heightFactor: 1,
                child: center.detail.isEmpty
                    ? const SizedBox.shrink()
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: swiftNotes(center.detail, Typo.fixed(12 * s, TypoWeight.regular, TruverColors.textTertiary), maxLines: 1),
                      ),
              ),
            ),
          ],
        ),
        DialStrobeNote() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // line-height 1: a 64 pt box; the octave is an inline 20 pt span on the same baseline.
            SizedBox(
              height: 64 * s,
              child: OverflowBox(
                maxHeight: double.infinity,
                child: Text.rich(
                  TextSpan(
                    children: [
                      Typo.notes(center.name, Typo.fixed(64 * s, TypoWeight.extraLight, TruverColors.textPrimary)),
                      TextSpan(text: center.octave, style: Typo.fixed(20 * s, TypoWeight.regular, TruverColors.textSecondary)),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
            SizedBox(height: 6 * s),
            FittedBox(fit: BoxFit.scaleDown, child: swiftNotes(center.line, Typo.fixed(13 * s, TypoWeight.regular, center.color), maxLines: 1)),
          ],
        ),
        DialMessage() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (center.icon != null) ...[
              _badge(TruverColors.white(0.12), s, AppIconView(center.icon!, size: 24 * s, color: center.iconColor)),
              SizedBox(height: 12 * s),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 168 * s),
              child: SwiftText(center.title, textAlign: TextAlign.center, style: Typo.fixed(17 * s, TypoWeight.semibold, TruverColors.textPrimary)),
            ),
            if (center.detail != null) _explanation(center.detail!, s),
          ],
        ),
        DialListening() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SoundBars(heights: const [10, 18, 28, 20, 12, 8], color: TruverColors.textSecondary.withValues(alpha: 0.7), animated: false, scale: s),
            SizedBox(height: 12 * s),
            SwiftText('Слушаю…', style: Typo.fixed(17 * s, TypoWeight.semibold, TruverColors.textPrimary)),
            SizedBox(height: 4 * s),
            SwiftText('звук есть, нота ещё не ясна', style: Typo.fixed(12 * s, TypoWeight.regular, TruverColors.textSecondary)),
          ],
        ),
        DialDone() => _DoneContent(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _badge(TruverColors.inTune.withValues(alpha: 0.6), s, AppIconView(AppIcon.check, size: 26 * s, lineWidth: 2.2, color: TruverColors.inTune)),
              SizedBox(height: 12 * s),
              SwiftText('Готово', style: Typo.fixed(17 * s, TypoWeight.semibold, TruverColors.textPrimary)),
              _explanation(center.detail, s),
            ],
          ),
        ),
        DialReference() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SoundBars(heights: const [18, 30, 40, 34, 24, 14], color: TruverColors.textPrimary, animated: !widget.frozen, scale: s),
            SizedBox(height: 12 * s),
            swiftNotes(center.title, Typo.fixed(17 * s, TypoWeight.semibold, TruverColors.textPrimary)),
            SizedBox(height: 4 * s),
            swiftNotes(center.detail, Typo.fixed(12 * s, TypoWeight.regular, TruverColors.textSecondary)),
          ],
        ),
      },
    );
  }

  /// Canvas: a 54 pt disc (white 4 %) with a 1 pt border outside it — 56 pt in all.
  Widget _badge(Color border, double s, Widget icon) => SizedBox(
    width: 56 * s,
    height: 56 * s,
    child: ShapeBox(
      shape: SwiftShape.circle,
      fills: [SwiftFill(TruverColors.white(0.04))],
      strokes: [SwiftStroke(border, inside: true)],
      child: Center(child: icon),
    ),
  );

  /// 12 pt, line-height 1.35 (1.67 pt between lines, half of it above the first and below the last), 160 wide.
  Widget _explanation(String text, double s) => Padding(
    padding: EdgeInsets.only(top: 4 * s + 0.83 * s, bottom: 0.83 * s),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 160 * s),
      child: SwiftText(text, textAlign: TextAlign.center, lineSpacing: 1.67 * s, style: Typo.fixed(12 * s, TypoWeight.regular, TruverColors.textSecondary)),
    ),
  );
}

/// «Готово»: appears with `.transition(.scale(0.6).combined(with: .opacity))` and the reward spring.
class _DoneContent extends StatelessWidget {
  const _DoneContent({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.popDuration,
      curve: Motion.pop,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1).toDouble(),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: child,
    );
  }
}

/// The needle in the face's coordinates (294 pt, 13 pt inside the bezel): x 145, y 7, 4 × 15, radius 2, with a
/// 5 pt glow (CSS drop-shadow blur 5 = σ 2.5) in its colour.
class _NeedlePainter extends CustomPainter {
  _NeedlePainter({required this.color, required this.s});
  final Color color;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final face = Rect.fromCircle(center: size.center(Offset.zero), radius: 147 * s);
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(face.left + 145 * s, face.top + 7 * s, 4 * s, 15 * s), Radius.circular(2 * s));
    SwiftShadow(color, 2.5 * s).paint(canvas, Path()..addRRect(rect));
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.color != color || old.s != s;
}

/// The face glow outside the face only (the face covers it in SwiftUI's layering).
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.alpha, required this.s});
  final double alpha;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final c = size.center(Offset.zero);
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(Rect.fromCircle(center: c, radius: 147 * s)),
    );
    canvas.drawCircle(
      c,
      151 * s,
      Paint()
        ..color = TruverColors.inTune.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * s),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.alpha != alpha || old.s != s;
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.value, required this.width});
  final double value;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = TruverColors.beat,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) => old.value != value || old.width != width;
}

/// Canvas: the note 96 Light, letter-spacing −0.02 em, line-height 1 (a 96 pt box); the octave 22 Regular hangs
/// off the note's right edge (+3 pt), its baseline 1.9 pt above the note's. Only the letter is centred; the octave
/// does not push it left.
class NoteWithOctave extends StatelessWidget {
  const NoteWithOctave({super.key, required this.name, required this.octave, required this.s});
  final String name;
  final String octave;
  final double s;

  @override
  Widget build(BuildContext context) {
    // 5.1.4: 96 pt for 1–2 characters, 72 for 3–4, 60 for «соль♯» (canvas «Обозначения — сольфеджио»).
    final size = dialNoteSize(name) * s;
    final noteStyle = Typo.fixed(size, TypoWeight.light, TruverColors.textPrimary).copyWith(letterSpacing: -0.02 * size);
    final octaveStyle = Typo.fixed(22 * s, TypoWeight.regular, TruverColors.textSecondary);
    final note = TextPainter(text: Typo.notes(name, noteStyle), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling, maxLines: 1)..layout();
    final oct = TextPainter(
      text: TextSpan(text: octave, style: octaveStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final noteBaseline = note.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final octBaseline = oct.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final width = note.width, height = note.height;
    note.dispose();
    oct.dispose();
    return SizedBox(
      height: 96 * s,
      child: OverflowBox(
        maxHeight: double.infinity,
        maxWidth: double.infinity,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text.rich(Typo.notes(name, noteStyle), maxLines: 1, softWrap: false, textScaler: TextScaler.noScaling),
              Positioned(
                left: width + 3 * s,
                top: noteBaseline - 1.9 * s - octBaseline,
                child: Text(octave, style: octaveStyle, maxLines: 1, softWrap: false, textScaler: TextScaler.noScaling),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bezel, knurl, face and scale — everything of the dial that does not move.
class _DialBodyPainter extends CustomPainter {
  _DialBodyPainter({required this.s});
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final bezel = Rect.fromCircle(center: c, radius: r);
    final bezelPath = Path()..addOval(bezel);

    // Bezel: brushed metal with a soft highlight rim, the big drop shadow.
    SwiftShadow(TruverColors.black(0.85), 40 * s, y: 40 * s).paint(canvas, bezelPath);
    canvas.drawOval(bezel, Paint()..shader = TruverGradients.metal.createShader(bezel));
    canvas.save();
    canvas.clipPath(bezelPath);
    canvas.drawOval(
      bezel.shift(const Offset(0, 0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = TruverColors.white(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3),
    );
    canvas.restore();

    // Knurl: alternating 1° dark and light wedges at 60 %.
    final knurl = bezel.deflate(8 * s);
    canvas.saveLayer(knurl.inflate(1), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.6));
    final kr = knurl.width / 2;
    for (var i = 0; i < 360; i++) {
      final a0 = i * math.pi / 180, a1 = (i + 1.05) * math.pi / 180;
      final wedge = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: kr), a0, a1 - a0, false)
        ..close();
      canvas.drawPath(wedge, Paint()..color = i.isEven ? TruverColors.black(0.18) : TruverColors.white(0.08));
    }
    canvas.restore();

    // Face.
    final face = bezel.deflate(13 * s);
    final facePath = Path()..addOval(face);
    canvas.drawOval(
      face,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 150 * s / face.width,
          colors: const [TruverColors.faceTop, Color(0xFF0B0B0C), TruverColors.faceBottom],
        ).createShader(face),
    );
    canvas.drawOval(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..color = const Color(0xFF2A2C30),
    );
    // Inner shadow: a blurred black ring shifted down, masked by the face.
    canvas.save();
    canvas.clipPath(facePath);
    canvas.drawOval(
      face.shift(Offset(0, 6 * s)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 * s
        ..color = TruverColors.black(0.95)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * s),
    );
    canvas.restore();

    // Scale: 120 fine ticks, 12 major ticks and the green top marker.
    final ss = face.width / 294;
    void tick(double degrees, double length, double width, Color color) {
      final start = (degrees - 90 - length / 2) * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 134 * ss),
        start,
        length * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color,
      );
    }

    for (var i = 0; i < 120; i++) {
      tick(i * 3.0, 0.5, 8 * ss, const Color(0xFFE9E6DF).withValues(alpha: 0.24));
    }
    for (var i = 0; i < 12; i++) {
      tick(i * 30.0, 0.8, 12 * ss, const Color(0xFFE9E6DF).withValues(alpha: 0.65));
    }
    final o = face.topLeft;
    final marker = Path()
      ..moveTo(o.dx + 147 * ss, o.dy + 7 * ss)
      ..lineTo(o.dx + 142.5 * ss, o.dy + 1 * ss)
      ..lineTo(o.dx + 151.5 * ss, o.dy + 1 * ss)
      ..close();
    canvas.drawPath(marker, Paint()..color = TruverColors.inTune);
  }

  @override
  bool shouldRepaint(_DialBodyPainter old) => old.s != s;
}

/// The strobe band: a dashed ring (2.5 / 5.5 pt) from 3 o'clock clockwise, as SwiftUI dashes `Circle()`.
class _StrobeBandPainter extends CustomPainter {
  _StrobeBandPainter({required this.s, required this.color, required this.angle});
  final double s;
  final Color color;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * s
      ..color = color;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle * math.pi / 180);
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    final circumference = 2 * math.pi * r;
    final dash = 2.5 * s, gap = 5.5 * s;
    var d = 0.0;
    while (d < circumference) {
      final len = math.min(dash, circumference - d);
      canvas.drawArc(rect, d / r, len / r, false, paint);
      d += dash + gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrobeBandPainter old) => old.s != s || old.color != color || old.angle != angle;
}

/// «Слушаю» / «Эталон» (canvas): six 5 pt bars (radius 3), 4 apart, centred in a 40 pt row. The reference bars
/// breathe (`wave`: scaleY 0.35 ↔ 1 in 0.9 s, 0.1 s apart); still bars — at the first frame (0.35) for the
/// reference, at full height for «Слушаю».
class SoundBars extends StatelessWidget {
  const SoundBars({super.key, required this.heights, required this.color, required this.animated, required this.scale});
  final List<double> heights;
  final Color color;
  final bool animated;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final reduce = Motion.reduced(context);
    Widget bars(double? t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < heights.length; i++) ...[if (i > 0) SizedBox(width: 4 * scale), _bar(i, t)],
      ],
    );
    return ExcludeSemantics(
      child: SizedBox(
        height: 40 * scale,
        child: animated && !reduce ? FrameTicker(builder: (context, elapsed) => bars(_clock(elapsed))) : bars(null),
      ),
    );
  }

  Widget _bar(int i, double? t) {
    double y = 1;
    if (animated) {
      if (t == null) {
        y = 0.35;
      } else {
        final phase = ((t - i * 0.1) / 0.9) % 1;
        y = 0.35 + 0.65 * (1 - math.cos(2 * math.pi * phase)) / 2;
      }
    }
    return SizedBox(
      width: 5 * scale,
      height: heights[i] * scale,
      child: Transform.scale(
        scaleX: 1,
        scaleY: y,
        child: ShapeBox(shape: SwiftShape.rounded(3 * scale), fills: [SwiftFill(color)]),
      ),
    );
  }
}

/// TU-10 strobe strips (canvas «Тюнер — строб»): three 10 pt bars, 4 apart — stripes of 10 / 20 / 40 pt at
/// 85 / 60 / 40 % with equal gaps; they run with the signal phase (one full stripe period per turn) and stand
/// still in tune.
class StrobeStrips extends StatelessWidget {
  const StrobeStrips({super.key, required this.phase});
  final double phase;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [_strip(10, 0.85), const SizedBox(height: 4), _strip(20, 0.6), const SizedBox(height: 4), _strip(40, 0.4)],
    ),
  );

  Widget _strip(double width, double opacity) => SizedBox(
    height: 10,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: CustomPaint(
        size: const Size(double.infinity, 10),
        painter: _StripPainter(width: width, opacity: opacity, phase: phase),
      ),
    ),
  );
}

class _StripPainter extends CustomPainter {
  _StripPainter({required this.width, required this.opacity, required this.phase});
  final double width;
  final double opacity;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final period = width * 2;
    var shift = ((phase / 360) % 1) * period;
    if (shift > 0) shift -= period;
    final on = Paint()..color = TruverColors.textPrimary.withValues(alpha: opacity);
    final off = Paint()..color = TruverColors.white(0.03);
    for (var x = shift; x < size.width; x += period) {
      canvas.drawRect(Rect.fromLTWH(x, 0, width, size.height), on);
      canvas.drawRect(Rect.fromLTWH(x + width, 0, width, size.height), off);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.phase != phase || old.width != width || old.opacity != opacity;
}

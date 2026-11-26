/// Port of Truver/Sources/Features/Fretboard/NeckPortrait.swift
///
/// The vertical neck of the canvas («Гриф — позиция», 346 × 396): ivory binding, dark wood with grain and side
/// shading, chrome frets spaced like a real neck, pearl inlays, wound and plain strings with shadows, 32 pt notes.
/// Strings run top to bottom, low string on the left (mirrored for left-handers); frets grow downwards.
///
/// Reusable: the fret trainer can draw its neck with [NeckPortrait] (cells, taps) or only the board with
/// [NeckBoardPainter] + [NeckGeometry].
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../tour/coach_marks.dart';

/// Scale role of a note (core `DegreeRole`).
enum DegreeRole {
  tonic,
  chordTone,
  characteristic,
  other;

  static DegreeRole parse(Object? raw) => values.where((r) => r.name == raw).firstOrNull ?? other;
}

enum NeckEmphasis { full, faint }

/// One dot on the neck.
class NeckCell {
  NeckCell({
    required this.course,
    required this.fret,
    required this.cents,
    required this.label,
    required this.role,
    this.emphasis = NeckEmphasis.full,
    this.isAdded = false,
    this.isPlaying = false,
    this.isMarked = false,
    this.hasRing = false,
    this.isWrong = false,
  });

  final int course;
  final int fret;

  /// Pitch in cents from A4.
  final double cents;
  String label;
  final DegreeRole role;
  NeckEmphasis emphasis;
  final bool isAdded;
  final bool isPlaying;

  /// «Поиск»: a note marked by the user (purple).
  final bool isMarked;

  /// The note a menu or a «from this note» sheet refers to (ring).
  final bool hasRing;

  /// FB-14 / SM-5: played wrong in training (red).
  final bool isWrong;

  String get id => '$course:$fret';
}

/// A note of a path (FB-20) in playing order.
class NeckPathNote {
  const NeckPathNote(this.course, this.fret);
  final int course;
  final int fret;
}

/// PR-7 for drawing: scale ratio of each string to the mean scale (low string first) and the neutral fret.
class NeckFan {
  const NeckFan({required this.ratios, required this.neutralFret});
  final List<double> ratios;
  final int neutralFret;

  /// From the core's `{ratios, neutralFret}` (null when the frets are not fanned).
  static NeckFan? fromJson(Object? json) {
    if (json is! Map) return null;
    final ratios = (json['ratios'] as List).map((e) => (e as num).toDouble()).toList();
    return NeckFan(ratios: ratios, neutralFret: (json['neutralFret'] as num).toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is NeckFan && other.neutralFret == neutralFret && other.ratios.length == ratios.length &&
      Iterable.generate(ratios.length).every((i) => other.ratios[i] == ratios[i]);

  @override
  int get hashCode => Object.hash(neutralFret, Object.hashAll(ratios));
}

/// `NeckPortrait.Geometry`.
class NeckGeometry {
  NeckGeometry({required this.size, required this.courses, required this.lo, required this.hi, this.leftHanded = false, this.fan, this.overview = false, this.band = true});

  final Size size;
  final int courses;

  /// First and last fret shown (cells); fret 0 = open strings above the nut.
  final int lo;
  final int hi;
  final bool leftHanded;
  final NeckFan? fan;
  final bool overview;
  final bool band;

  /// Open-string band above the nut when fret 0 is shown (canvas: 30 pt).
  double get openBand => band && lo <= 1 ? 30 : 0;

  /// Unit distance of wire n from the nut: 12-TET up to the 12th fret, then even steps of the 12th fret's width
  /// (`NeckPortrait.unit`).
  static double unit(int n) {
    double real(int k) => 1 - math.pow(2, -k / 12).toDouble();
    if (n <= 12) return real(n);
    return real(12) + (n - 12) * (real(12) - real(11));
  }
  double get inner => size.width - 8;
  double get margin => 26;

  /// Centre of a string, in the outer box (binding 4 pt on each side).
  double x(int course) {
    final spacing = courses > 1 ? (inner - 2 * margin) / (courses - 1) : 0.0;
    final index = leftHanded ? courses - 1 - course : course;
    return 4 + margin + index * spacing;
  }

  /// Distance of fret wire n from the nut on a unit scale (12-TET).
  double _d(int n) {
    final real = 1 - math.pow(2, -n / 12).toDouble();
    if (!overview) return unit(n);
    // Overview: 65 % even spacing + 35 % real — high frets stay readable, the neck still looks like a neck.
    final top = math.max(1, hi).toDouble();
    final even = n / top * (1 - math.pow(2, -top / 12).toDouble());
    return 0.65 * even + 0.35 * real;
  }

  int get _firstWire => math.max(0, lo - 1);

  /// Scale ratio at a fractional string index (0 = lowest); 1 without fanned frets.
  double _ratio(double t) {
    final f = fan;
    if (f == null || f.ratios.isEmpty || courses <= 1) return 1;
    return f.ratios.first + (f.ratios.last - f.ratios.first) * t / (courses - 1);
  }

  /// Along-neck position of wire n on a unit scale for a string with this ratio: the neutral fret stays put.
  double _u(int n, double r) {
    final f = fan;
    if (f == null) return _d(n);
    final dn = _d(f.neutralFret);
    return r * (_d(n) - dn) + dn;
  }

  (double, double) get _ratioRange {
    final a = _ratio(0), b = _ratio(math.max(0, courses - 1).toDouble());
    return (math.min(a, b), math.max(a, b));
  }

  double get _unitTop {
    final (a, b) = _ratioRange;
    return math.min(_u(_firstWire, a), _u(_firstWire, b));
  }

  double get _unitBottom {
    final (a, b) = _ratioRange;
    return math.max(_u(hi, a), _u(hi, b));
  }

  /// Canvas (2026-11-25): wire lo−1 sits 3 pt above the top, the last wire 2 pt above the bottom.
  double _map(double unit) {
    final span = size.height - openBand + 1;
    return openBand - 3 + (unit - _unitTop) / math.max(0.0001, _unitBottom - _unitTop) * span;
  }

  /// y of fret wire n (top edge of the 4 pt wire) along the middle of the neck.
  double wire(int n) => _map(_u(n, 1));

  /// y of fret wire n under a string (fanned frets slant).
  double wireUnder(int n, int course) => _map(_u(n, _ratio(course.toDouble())));

  /// y of fret wire n at a horizontal position of the outer box (for drawing the slanted wire).
  double wireAtX(int n, double px) {
    final spacing = courses > 1 ? (inner - 2 * margin) / (courses - 1) : 1.0;
    var t = (px - 4 - margin) / spacing;
    if (leftHanded) t = (courses - 1) - t;
    return _map(_u(n, _ratio(t)));
  }

  /// Slope of wire n across the box (radians; 0 without fanned frets).
  double wireAngle(int n) {
    if (fan == null) return 0;
    final l = wireAtX(n, 4), r = wireAtX(n, size.width - 4);
    return math.atan2(r - l, size.width - 8);
  }

  /// Centre of a fret's cell; with `course`, under that string (fanned frets).
  double y(int fret, [int? course]) {
    double w(int n) => course == null ? wire(n) : wireUnder(n, course);
    if (fret == 0) return fan == null ? openBand / 2 : w(0) - openBand / 2;
    return (w(fret - 1) + 4 + w(fret)) / 2;
  }

  Offset center(int course, int fret) => Offset(x(course), y(fret, course));

  /// Nearest cell to a touch (by string, then the fret whose wire is below).
  (int, int)? cell(Offset p) {
    var course = 0;
    for (var c = 1; c < courses; c++) {
      if ((x(c) - p.dx).abs() < (x(course) - p.dx).abs()) course = c;
    }
    if (openBand > 0 && p.dy < wireUnder(0, course) + 3) return (course, 0);
    for (var fret = math.max(1, lo); fret <= hi; fret++) {
      if (p.dy <= wireUnder(fret, course) + 2) return (course, fret);
    }
    return null;
  }

  /// y of a fret's cell centre — for scrolling to the current path note.
  static double cellY({required int fret, required int lo, required int hi, required int courses, required Size size, NeckFan? fan, bool overview = false}) =>
      NeckGeometry(size: size, courses: courses, lo: lo, hi: hi, fan: fan, overview: overview).y(fret);
}

/// Note colours (`NeckPortrait.NoteStyle`).
class NoteStyle {
  const NoteStyle(this.fill, this.border, this.text);
  final Color fill;
  final Color border;
  final Color text;

  static const _dark = Color.fromRGBO(24, 26, 30, 0.74);
  static const _light = Color(0xFFEEF0F3);
  static const _ink = Color(0xFF0C0D0F);
  static const _white = Color(0xFFFFFFFF);
  static const gold = Color(0xFFE8B54A);

  /// «Аккорд», «Поиск»: ivory notes; dimmed (muted / not in the shape) — white .08 with a .18 ring.
  static const ivory = NoteStyle(TruverColors.textPrimary, _white, _ink);
  static const dim = NoteStyle(Color.fromRGBO(255, 255, 255, 0.08), Color.fromRGBO(255, 255, 255, 0.18), Color.fromRGBO(255, 255, 255, 0.55));

  factory NoteStyle.of(DegreeRole role, {bool added = false}) {
    if (added) return const NoteStyle(_dark, _white, _light);
    return switch (role) {
      DegreeRole.tonic => const NoteStyle(gold, _white, _ink),
      DegreeRole.chordTone => const NoteStyle(Color.fromRGBO(143, 196, 255, 0.95), Color(0xFFCFE5FF), _ink),
      DegreeRole.characteristic => const NoteStyle(Color.fromRGBO(195, 166, 255, 0.95), Color(0xFFE6DBFF), _ink),
      DegreeRole.other => const NoteStyle(Color(0xFF2B2F36), Color.fromRGBO(150, 156, 166, 0.7), _light),
    };
  }

  /// FB-14 / SM-5: the note was played wrong (red, as the PRD asks).
  static const wrong = NoteStyle(TruverColors.danger, Color(0xFFFFB4A8), _ink);

  /// «Поиск»: marked notes (canvas rgba(195,166,255,.95), ring #e6dbff).
  static const marked = NoteStyle(Color.fromRGBO(195, 166, 255, 0.95), Color(0xFFE6DBFF), _ink);
}

typedef NeckTap = void Function(int course, int fret);

/// Course, fret and the note's centre in global coordinates (for the note menu).
typedef NeckLongPress = void Function(int course, int fret, Offset globalCenter);

class NeckPortrait extends StatelessWidget {
  const NeckPortrait({
    super.key,
    required this.courses,
    required this.lo,
    required this.hi,
    required this.cells,
    this.leftHanded = false,
    this.capo,
    this.strumming = const {},
    this.strumOrder = const [],
    this.strumToken = 0,
    this.chordMode = false,
    this.path = const [],
    this.pathLabels = const [],
    this.pathCurrent,
    this.playingMode = false,
    this.mutedCourses = const {},
    this.labelRotation = 0,
    this.fan,
    this.overview = false,
    this.sizing = NoteSizing.large,
    this.openBand = true,
    this.onTap,
    this.onLongPress,
    this.onScrub,
    this.scrubs = false,
    this.coachCell,
  });

  final int courses;
  final int lo;
  final int hi;
  final List<NeckCell> cells;
  final bool leftHanded;

  /// Courses under the capo are dimmed above it (canvas «капо на 2-м ладу»).
  final int? capo;

  /// Strings that ring after a chord tap (canvas FB-23): a soft light runs along them.
  final Set<int> strumming;

  /// The same strings in stroke order (low to high): each lights 12 ms after the previous.
  final List<int> strumOrder;

  /// Changes with every stroke, so the glow runs again.
  final int strumToken;
  final bool chordMode;

  /// FB-20: the path in playing order; `pathCurrent` — the sounding note.
  final List<NeckPathNote> path;

  /// Note names (or degrees) inside the path notes; the order number is a small badge.
  final List<String> pathLabels;
  final int? pathCurrent;
  final bool playingMode;

  /// «Аккорд»: strings that do not sound get «×» at the nut.
  final Set<int> mutedCourses;

  /// Landscape draws this neck rotated by ±90°: labels turn back by this angle (degrees) to stay upright.
  final double labelRotation;

  /// PR-7: fanned frets.
  final NeckFan? fan;

  /// The whole neck on one screen: frets spaced closer to even, smaller notes.
  final bool overview;

  /// Note sizes of the canvas (2026-11-25): «Гамма» 26 / 13 / 10, «Аккорд» and «Поиск» 34, «Прогрессия» 30 / 28,
  /// all notes after a tap 12 with the picked note 38.
  final NoteSizing sizing;

  /// The open strings are drawn by the screen in a fixed row above a scrolling neck: no open band here.
  final bool openBand;
  final NeckTap? onTap;

  /// Canvas S8Loupe: hold and drag — the cell under the finger and its centre in global coordinates, null on
  /// release. When `scrubs`, it replaces the long-press menu.
  final void Function((int, int)? cell, Offset globalCenter)? onScrub;
  final bool scrubs;
  final NeckLongPress? onLongPress;

  /// Coach mark «Нажмите на ноту» (features/tour): this note (course, fret) reports its frame.
  final (int, int)? coachCell;

  void _scrub(BuildContext context, NeckGeometry g, Offset p) {
    final hit = g.cell(p);
    if (hit == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final center = g.center(hit.$1, hit.$2);
    onScrub!(hit, box?.localToGlobal(center) ?? center);
  }

  bool _shown(int fret) => (fret >= lo && fret <= hi) || (fret == 0 && lo <= 1 && openBand);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final g = NeckGeometry(size: size, courses: courses, lo: lo, hi: hi, leftHanded: leftHanded, fan: fan, overview: overview, band: openBand);
        final reduce = Motion.reduced(context);
        final children = <Widget>[
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: NeckBoardPainter(g, capo: capo))),
          ),
        ];
        if (path.isEmpty) {
          for (final cell in cells) {
            if (_shown(cell.fret)) children.add(_NoteDot(key: ValueKey('note-${cell.course}:${cell.fret}'), cell: cell, g: g, sizing: sizing, chordMode: chordMode, rotation: labelRotation));
            if (coachCell == (cell.course, cell.fret) && _shown(cell.fret)) {
              final c = g.center(cell.course, cell.fret);
              final d = noteMetrics(cell, sizing).$1;
              children.add(Positioned(left: c.dx - d / 2, top: c.dy - d / 2, width: d, height: d,
                  child: const IgnorePointer(child: CoachAnchor(id: CoachAnchors.firstTonic, child: SizedBox.expand()))));
            }
          }
        } else {
          // All scale notes as small dots, the path on top (canvas «Гриф — путь»).
          children.add(Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _PathPainter(g, cells.where((c) => _shown(c.fret)).toList(), path, pathCurrent)),
            ),
          ));
          for (var i = 0; i < path.length; i++) {
            children.add(_PathDot(
              index: i,
              note: path[i],
              label: i < pathLabels.length ? pathLabels[i] : '',
              current: pathCurrent ?? 0,
              g: g,
              overview: overview,
              rotation: labelRotation,
            ));
          }
        }
        for (final course in mutedCourses.toList()..sort()) {
          final c = Offset(g.x(course), lo <= 1 ? g.y(0, course) : 12);
          children.add(Positioned(
            left: c.dx - 20,
            top: c.dy - 20,
            width: 40,
            height: 40,
            child: IgnorePointer(
              child: Center(
                child: Transform.rotate(
                  angle: labelRotation * math.pi / 180,
                  child: Text('×',
                      textScaler: TextScaler.noScaling,
                      style: Typo.fixed(16, TypoWeight.medium, TruverColors.textSecondary)),
                ),
              ),
            ),
          ));
        }
        if (strumming.isNotEmpty && !reduce) {
          for (var i = 0; i < strumOrder.length; i++) {
            final course = strumOrder[i];
            if (!strumming.contains(course)) continue;
            children.add(Positioned(
              left: g.x(course) - 3,
              top: 0,
              width: 6,
              height: size.height,
              child: IgnorePointer(child: _StrumGlow(key: ValueKey('glow-$strumToken-$course'), delay: Duration(milliseconds: i * 12))),
            ));
          }
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onTap == null
              ? null
              : (d) {
                  final hit = g.cell(d.localPosition);
                  if (hit != null) onTap!(hit.$1, hit.$2);
                },
          onLongPressStart: scrubs && onScrub != null ? (d) => _scrub(context, g, d.localPosition) : null,
          onLongPressMoveUpdate: scrubs && onScrub != null ? (d) => _scrub(context, g, d.localPosition) : null,
          onLongPressEnd: scrubs
              ? (_) => onScrub?.call(null, Offset.zero)
              : onLongPress == null
              ? null
              : (d) {
                  final hit = g.cell(d.localPosition);
                  if (hit == null) return;
                  final box = context.findRenderObject() as RenderBox?;
                  final center = g.center(hit.$1, hit.$2);
                  onLongPress!(hit.$1, hit.$2, box?.localToGlobal(center) ?? center);
                },
          child: SizedBox.fromSize(size: size, child: Stack(clipBehavior: Clip.none, children: children)),
        );
      });
}

// MARK: Board

/// Canvas 2026-11-25 steel neck: board #3a404a with #2b2f36 inside, inlays, frets, flat strings, nut and capo.
class NeckBoardPainter extends CustomPainter {
  NeckBoardPainter(this.g, {this.capo});
  final NeckGeometry g;
  final int? capo;

  static const stringWidths = [4.4, 4.0, 3.6, 3.1, 2.7, 2.3, 1.9, 1.6, 1.25, 1.0];
  static const woundString = Color(0xFF9FB0C6);
  static const plainString = Color(0xFFB8C5D6);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Outer board #3a404a, r 4, shadow 0 30 60 .8 and a 1 pt dark outline.
    final outline = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(
      outline.shift(const Offset(0, 30)),
      Paint()
        ..color = TruverColors.black(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawRRect(outline, Paint()..color = const Color(0xFF3A404A));
    canvas.drawRRect(
      outline.inflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = TruverColors.black(0.6),
    );

    canvas.save();
    canvas.translate(4, 0);
    _inner(canvas, Size(w - 8, h));
    canvas.restore();

    if (g.lo <= 1) {
      // Nut: 10 pt #dfe5ec, shadow 0 4 6 .6.
      canvas.save();
      canvas.translate(4, g.fan == null ? g.openBand : g.wireAtX(0, 4) + 3);
      canvas.rotate(g.wireAngle(0));
      final nut = Rect.fromLTWH(0, 0, w - 8, 10);
      canvas.drawRect(
        nut.shift(const Offset(0, 4)),
        Paint()
          ..color = TruverColors.black(0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRect(nut, Paint()..color = const Color(0xFFDFE5EC));
      canvas.restore();
    }
    final c = capo;
    if (c != null && c >= g.lo && c <= g.hi) {
      // Canvas «капо»: a 10 pt bar r 5 across the board, #e8e2d4 → #a9a296, shadow 0 2 6 .6.
      canvas.save();
      canvas.translate(0, g.y(c) - 10);
      canvas.rotate(g.wireAngle(c));
      final bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, 10), const Radius.circular(5));
      canvas.drawRRect(
        bar.shift(const Offset(0, 2)),
        Paint()
          ..color = TruverColors.black(0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRRect(
        bar,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8E2D4), Color(0xFFA9A296)],
          ).createShader(bar.outerRect),
      );
      canvas.restore();
    }
  }

  void _inner(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = const Color(0xFF2B2F36));
    // Inlays: 10 pt #aab3c0 at .4 in the cell centres; double at 12 and 24 (30 % and 70 % across).
    for (var fret = math.max(1, g.lo); fret <= g.hi; fret++) {
      if (!const [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fret)) continue;
      final xs = fret % 12 == 0 ? [(w * 0.3).roundToDouble(), (w * 0.7).roundToDouble()] : [(w * 0.5).roundToDouble()];
      for (final x in xs) {
        final y = g.fan == null ? g.y(fret) : (g.wireAtX(fret - 1, x + 4) + 4 + g.wireAtX(fret, x + 4)) / 2;
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = const Color(0xFFAAB3C0).withValues(alpha: 0.4));
      }
    }
    // Frets: 4 pt, r 2, #6b7380 → #e3e8ef → #6b7380.
    for (var fret = math.max(1, g.lo); fret <= g.hi; fret++) {
      canvas.save();
      var y = g.wire(fret);
      var len = w;
      if (g.fan != null) {
        y = 0;
        canvas.translate(0, g.wireAtX(fret, 4));
        canvas.rotate(g.wireAngle(fret));
        len = w / math.cos(g.wireAngle(fret));
      }
      final wireRect = Rect.fromLTWH(0, y, len, 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(wireRect, const Radius.circular(2)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6B7380), Color(0xFFE3E8EF), Color(0xFF6B7380)],
          ).createShader(wireRect),
      );
      canvas.restore();
    }
    // Strings: flat, wound #9fb0c6, the two thinnest plain #b8c5d6.
    final widths = stringWidths.sublist(math.max(0, stringWidths.length - g.courses));
    for (var course = 0; course < g.courses; course++) {
      final x = g.x(course) - 4;
      final width = course < widths.length ? widths[course] : 1.0;
      canvas.drawRect(Rect.fromLTWH(x - width / 2, 0, width, h), Paint()..color = course >= g.courses - 2 ? plainString : woundString);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NeckBoardPainter old) =>
      old.capo != capo ||
      old.g.size != g.size ||
      old.g.courses != g.courses ||
      old.g.lo != g.lo ||
      old.g.hi != g.hi ||
      old.g.leftHanded != g.leftHanded ||
      old.g.overview != g.overview ||
      old.g.fan != g.fan;
}

// MARK: Notes

/// Paints a note label centred in `size`, shrinking to 60 % when it does not fit (`minimumScaleFactor(0.6)`).
void _paintLabel(Canvas canvas, Offset center, String text, double fontSize, Color color, double maxWidth, double rotation) {
  if (text.isEmpty) return;
  TextPainter layout(double s) => TextPainter(
        text: Typo.notes(text, Typo.fixed(s, TypoWeight.bold, color)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textScaler: TextScaler.noScaling,
      )..layout();
  var tp = layout(fontSize);
  if (tp.width > maxWidth) {
    final scale = math.max(0.6, maxWidth / tp.width);
    tp = layout(fontSize * scale);
  }
  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (rotation != 0) canvas.rotate(rotation * math.pi / 180);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

/// Note sizes of the canvas (2026-11-25), `NeckPortrait.NoteSizing`.
enum NoteSizing { scale, large, progression, allNotes }

/// Size, label size and whether the label shows (`NeckPortrait.metrics`).
(double, double, bool) noteMetrics(NeckCell cell, NoteSizing sizing) {
  if (cell.isPlaying) return (40, 14, true);
  switch (sizing) {
    case NoteSizing.scale:
      if (cell.isMarked || cell.isWrong) return (34, 12, true);
      return switch (cell.role) {
        DegreeRole.tonic => (26, 10, true),
        DegreeRole.chordTone || DegreeRole.characteristic => cell.isAdded ? (26, 10, true) : (13, 10, false),
        DegreeRole.other => cell.isAdded ? (26, 10, true) : (10, 10, false),
      };
    case NoteSizing.large:
      return cell.emphasis == NeckEmphasis.faint ? (30, 12, true) : (34, 12, true);
    case NoteSizing.progression:
      return cell.role == DegreeRole.tonic ? (30, 12, true) : (28, 12, true);
    case NoteSizing.allNotes:
      return cell.hasRing ? (38, 12, true) : (12, 10, false);
  }
}

NoteStyle noteStyle(NeckCell cell, NoteSizing sizing) {
  if (cell.isWrong) return NoteStyle.wrong;
  if (cell.isMarked) return NoteStyle.ivory;
  return switch (sizing) {
    NoteSizing.large => cell.emphasis == NeckEmphasis.faint ? NoteStyle.dim : NoteStyle.ivory,
    NoteSizing.allNotes => cell.hasRing ? NoteStyle.ivory : NoteStyle.dim,
    _ => NoteStyle.of(cell.role, added: cell.isAdded),
  };
}

class _NoteDot extends StatelessWidget {
  const _NoteDot({super.key, required this.cell, required this.g, required this.sizing, required this.chordMode, required this.rotation});

  final NeckCell cell;
  final NeckGeometry g;
  final NoteSizing sizing;
  final bool chordMode;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    final size = noteMetrics(cell, sizing).$1;
    final c = g.center(cell.course, cell.fret);
    const box = 72.0;
    return Positioned(
      left: c.dx - box / 2,
      top: c.dy - box / 2,
      width: box,
      height: box,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: size),
          duration: Motion.quick,
          curve: Motion.out,
          builder: (context, s, _) => CustomPaint(
            painter: _NotePainter(cell: cell, size: s, sizing: sizing, chordMode: chordMode, rotation: rotation),
          ),
        ),
      ),
    );
  }
}

class _NotePainter extends CustomPainter {
  _NotePainter({required this.cell, required this.size, required this.sizing, required this.chordMode, required this.rotation});

  final NeckCell cell;
  final double size;
  final NoteSizing sizing;
  final bool chordMode;
  final double rotation;

  @override
  void paint(Canvas canvas, Size box) {
    final style = noteStyle(cell, sizing);
    final m = noteMetrics(cell, sizing);
    final center = box.center(Offset.zero);
    final faded = cell.emphasis == NeckEmphasis.faint && sizing != NoteSizing.large;
    final opacity = faded ? (chordMode ? 0.28 : 0.55) : 1.0;
    if (opacity < 1) canvas.saveLayer(Offset.zero & box, Paint()..color = const Color(0xFF000000).withValues(alpha: opacity));
    final r = size / 2;
    // Shadow of the whole dot (black .55, radius 7, y 6) — SwiftUI shades by the content's alpha.
    if (!(sizing == NoteSizing.allNotes && !cell.hasRing)) {
      canvas.drawCircle(
        center.translate(0, 6),
        r,
        Paint()
          ..color = TruverColors.black(0.55 * math.max(style.fill.a, 0.85))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    if (cell.hasRing && sizing != NoteSizing.allNotes) {
      canvas.drawCircle(center, (size + 10) / 2, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = TruverColors.white(0.45));
    }
    if (cell.isPlaying) {
      canvas.drawCircle(center, (size + 3) / 2, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = TruverColors.white(0.18));
    }
    canvas.drawCircle(center, r, Paint()..color = style.fill);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = style.border;
    if (cell.isAdded) {
      // Dashed border [3, 2.5].
      final ring = Path()..addOval(Rect.fromCircle(center: center, radius: r - 0.75));
      for (final metric in ring.computeMetrics()) {
        var d = 0.0;
        while (d < metric.length) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 3, metric.length)), border);
          d += 5.5;
        }
      }
    } else {
      canvas.drawCircle(center, r - 0.75, border);
    }
    if (m.$3) {
      // 5.1.4: «соль» → «сол» on dots; three or more characters (solfège) smaller, the dot does not grow.
      final label = cell.label.replaceAll('соль', 'сол');
      final len = label.characters.length;
      _paintLabel(canvas, center, label, len >= 3 ? m.$2 - 3 : m.$2, style.text, size - 4, rotation);
    }
    if (opacity < 1) canvas.restore();
  }

  @override
  bool shouldRepaint(_NotePainter old) =>
      old.size != size ||
      old.sizing != sizing ||
      old.cell.label != cell.label ||
      old.cell.role != cell.role ||
      old.cell.emphasis != cell.emphasis ||
      old.cell.isAdded != cell.isAdded ||
      old.cell.isPlaying != cell.isPlaying ||
      old.cell.isMarked != cell.isMarked ||
      old.cell.hasRing != cell.hasRing ||
      old.cell.isWrong != cell.isWrong ||
      old.chordMode != chordMode ||
      old.rotation != rotation;
}

// MARK: Path

/// Scale notes as small dots and the path lines: along a string a thick line, solid where already played, dashed
/// ahead; to another string a thin dotted line.
class _PathPainter extends CustomPainter {
  _PathPainter(this.g, this.cells, this.path, this.current);
  final NeckGeometry g;
  final List<NeckCell> cells;
  final List<NeckPathNote> path;
  final int? current;

  @override
  void paint(Canvas canvas, Size size) {
    for (final cell in cells) {
      final c = g.center(cell.course, cell.fret);
      canvas.drawCircle(c, 5, Paint()..color = const Color(0xFF3A3C41));
      canvas.drawCircle(c, 4.5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = TruverColors.white(0.18));
    }
    final cur = current ?? 0;
    for (var i = 0; i + 1 < path.length; i++) {
      final a = g.center(path[i].course, path[i].fret), b = g.center(path[i + 1].course, path[i + 1].fret);
      final played = i < cur;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // Canvas «путь»: along a string 7 pt at .92 played, 4 pt dashed 4/6 at .55 ahead;
      // to another string 1.2 pt dotted 1/4 at .75 played, .35 ahead.
      if (path[i].course == path[i + 1].course) {
        paint
          ..strokeWidth = played ? 7 : 4
          ..color = TruverColors.textPrimary.withValues(alpha: played ? 0.92 : 0.55);
        if (played) {
          canvas.drawLine(a, b, paint);
        } else {
          _dashed(canvas, a, b, 4, 6, paint);
        }
      } else {
        paint
          ..strokeWidth = 1.2
          ..color = TruverColors.textPrimary.withValues(alpha: played ? 0.75 : 0.35);
        _dashed(canvas, a, b, 1, 4, paint);
      }
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, double on, double off, Paint paint) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final e = math.min(total, d + on);
      canvas.drawLine(a + dir * d, a + dir * e, paint);
      d += on + off;
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) => true;
}

/// Path note: 26 pt with the note name (or degree), the order number as a badge; the current note — ivory 40 pt.
class _PathDot extends StatelessWidget {
  const _PathDot({required this.index, required this.note, required this.label, required this.current, required this.g, required this.overview, required this.rotation});

  final int index;
  final NeckPathNote note;
  final String label;
  final int current;
  final NeckGeometry g;
  final bool overview;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    final isCurrent = current == index;
    final played = index < current;
    final size = overview ? (isCurrent ? 30.0 : 20.0) : (isCurrent ? 40.0 : 26.0);
    final style = isCurrent
        ? NoteStyle.of(DegreeRole.tonic)
        : (played ? NoteStyle.of(DegreeRole.chordTone) : NoteStyle.of(DegreeRole.other));
    final c = g.center(note.course, note.fret);
    final text = label.isEmpty ? '${index + 1}' : label;
    final fontSize = isCurrent ? (overview ? 12.0 : 14.0) : (overview ? 8.0 : (label.characters.length >= 3 ? 8.0 : 10.0));
    const box = 64.0;
    return Positioned(
      left: c.dx - box / 2,
      top: c.dy - box / 2,
      width: box,
      height: box,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: size),
          duration: Motion.quick,
          curve: Motion.out,
          builder: (context, s, _) => Transform.rotate(
            angle: rotation * math.pi / 180,
            child: CustomPaint(
              painter: _PathDotPainter(size: s, style: style, text: text, fontSize: fontSize, badge: label.isEmpty ? null : '${index + 1}', current: isCurrent),
            ),
          ),
        ),
      ),
    );
  }
}

class _PathDotPainter extends CustomPainter {
  _PathDotPainter({required this.size, required this.style, required this.text, required this.fontSize, required this.badge, required this.current});
  final double size;
  final NoteStyle style;
  final String text;
  final double fontSize;
  final String? badge;
  final bool current;

  @override
  void paint(Canvas canvas, Size box) {
    final center = box.center(Offset.zero);
    final r = size / 2;
    canvas.drawCircle(center.translate(0, 5), r, Paint()
      ..color = TruverColors.black(0.55 * math.max(style.fill.a, 0.85))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    if (current) {
      canvas.drawCircle(center, (size + 3) / 2, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = TruverColors.white(0.18));
    }
    canvas.drawCircle(center, r, Paint()..color = style.fill);
    canvas.drawCircle(center, r - 0.75, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = style.border);
    _paintLabel(canvas, center, text, fontSize, style.text, size - 4, 0);
    final b = badge;
    if (b != null) {
      final tp = TextPainter(
        text: TextSpan(text: b, style: Typo.fixed(8, TypoWeight.bold, TruverColors.background)),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      final w = math.max(13.0, tp.width + 6), h = math.max(13.0, tp.height);
      // `.overlay(alignment: .topTrailing)` + `.offset(x: 5, y: -5)`.
      final rect = Rect.fromLTWH(center.dx + r - w + 5, center.dy - r - 5, w, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(h / 2)), Paint()..color = TruverColors.textSecondary);
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PathDotPainter old) =>
      old.size != size || old.text != text || old.badge != badge || old.current != current || old.style.fill != style.fill;
}

// MARK: Strum

/// Light running along a string after a chord tap (canvas «тап по аккорду»).
class _StrumGlow extends StatefulWidget {
  const _StrumGlow({super.key, required this.delay});
  final Duration delay;

  @override
  State<_StrumGlow> createState() => _StrumGlowState();
}

class _StrumGlowState extends State<_StrumGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  bool _lit = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() => _lit = true);
      _fade.forward();
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_lit) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) => Opacity(
        opacity: 1 - Curves.easeOut.transform(_fade.value),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  TruverColors.textPrimary.withValues(alpha: 0),
                  TruverColors.textPrimary.withValues(alpha: 0.85),
                  TruverColors.textPrimary.withValues(alpha: 0.85),
                  TruverColors.textPrimary.withValues(alpha: 0),
                ],
                stops: const [0, 0.2, 0.8, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// MARK: Scrolling neck (canvas 2026-11-25: «листайте вверх-вниз»)

/// `ScrollingNeck`: the whole neck in a vertical scroll view, zoomed so that `window` fills the viewport; fret
/// numbers scroll with it, a 4 pt scroll bar counted in frets, fades 26 / 30 pt at the edges of the board.
class ScrollingNeck extends StatefulWidget {
  const ScrollingNeck({
    super.key,
    required this.courses,
    required this.fretCount,
    required this.window,
    required this.height,
    this.openRowOutside = false,
    this.leftHanded = false,
    this.capoShift = 0,
    this.onVisible,
    required this.neck,
  });

  final int courses;
  final int fretCount;

  /// Frets (lo, hi) that fill the viewport when it appears or the window changes.
  final (int, int) window;
  final double height;
  final bool openRowOutside;
  final bool leftHanded;

  /// «Лады от капо»: the capo fret is 0, numbers above count from it (0 = off).
  final int capoShift;
  final void Function(int lo, int hi)? onVisible;

  /// The neck for frets lo…hi (the content is the whole neck).
  final NeckPortrait Function(int lo, int hi) neck;

  static const boardWidth = 310.0;

  @override
  State<ScrollingNeck> createState() => _ScrollingNeckState();
}

class _ScrollingNeckState extends State<ScrollingNeck> {
  late final ScrollController _controller = ScrollController(initialScrollOffset: _offsetFor(widget.window.$1));
  double _offset = 0;

  double get _band => widget.openRowOutside ? 0 : 30;
  int get _first => widget.openRowOutside ? 1 : 0;

  double get _scale {
    final (lo, hi) = widget.window;
    final usable = lo == 0 ? widget.height - _band + 1 : widget.height + 1;
    return usable / math.max(0.0001, NeckGeometry.unit(hi) - NeckGeometry.unit(math.max(0, lo - 1)));
  }

  double get _contentHeight => _band - 1 + _scale * NeckGeometry.unit(widget.fretCount);

  double _offsetFor(int lo) => lo == 0 ? 0 : _band + _scale * NeckGeometry.unit(lo - 1);

  double _fretAt(double y) {
    final u = math.max(0.0, (y - _band) / _scale);
    final u12 = NeckGeometry.unit(12), step = u12 - NeckGeometry.unit(11);
    if (u <= u12) return -12 * math.log(math.max(0.0001, 1 - u)) / math.ln2;
    return 12 + (u - u12) / step;
  }

  double _center(int n) => n == 0 ? _band / 2 : _band + _scale * (NeckGeometry.unit(n - 1) + NeckGeometry.unit(n)) / 2 - 1;

  @override
  void initState() {
    super.initState();
    _offset = _offsetFor(widget.window.$1);
    _controller.addListener(_scrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(ScrollingNeck old) {
    super.didUpdateWidget(old);
    if (old.window != widget.window || old.height != widget.height || old.fretCount != widget.fretCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final target = _offsetFor(widget.window.$1).clamp(0.0, _controller.position.maxScrollExtent);
        _controller.animateTo(target, duration: Motion.move, curve: Motion.out);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrolled() {
    setState(() => _offset = _controller.offset);
    _report();
  }

  void _report() {
    final lo = math.min(_fretAt(_offset).round() + 1, widget.fretCount);
    final hi = math.max(lo, math.min(_fretAt(_offset + widget.height + 1).round(), widget.fretCount));
    widget.onVisible?.call(lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final lh = widget.leftHanded;
    final boardX = lh ? 18.0 : 22.0;
    final h = widget.height;
    final top = _fretAt(_offset), bottom = _fretAt(_offset + h + 1);
    final count = math.max(1, widget.fretCount);
    final labels = <Widget>[
      for (var n = math.max(math.max(1, _first), widget.capoShift); n <= math.max(1, widget.fretCount); n++)
        Positioned(
          left: lh ? 332 : 0,
          width: 18,
          top: _center(n) - 10,
          height: 20,
          child: Align(
            // The canvas mirrors the whole block (scaleX(−1)); the numbers stay right-aligned.
            alignment: Alignment.centerRight,
            child: Text(
              '${n - widget.capoShift}',
              style: Typo.inter(
                11,
                n % 12 == 0 || n % 12 == 5 ? TypoWeight.semibold : TypoWeight.regular,
                const [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(n) ? TruverColors.textSecondary : TruverColors.white(0.22),
              ),
            ),
          ),
        ),
    ];
    return SizedBox(
      width: 350,
      height: h,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: const ScrollBehavior().copyWith(scrollbars: false, overscroll: false),
            child: SingleChildScrollView(
              controller: _controller,
              child: SizedBox(
                width: 350,
                height: _contentHeight,
                child: Stack(clipBehavior: Clip.none, children: [
                  ...labels,
                  Positioned(
                    left: boardX,
                    top: 0,
                    width: ScrollingNeck.boardWidth,
                    height: _contentHeight,
                    child: widget.neck(_first, widget.fretCount),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (_offset > 1 || !widget.openRowOutside)
          Positioned(
            left: boardX,
            top: 0,
            width: ScrollingNeck.boardWidth,
            height: 26,
            child: const IgnorePointer(
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
          ),
        Positioned(
          left: boardX,
          top: h - 30,
          width: ScrollingNeck.boardWidth,
          height: 30,
          child: const IgnorePointer(
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
        // Scroll bar: track white .08, thumb ivory .6, counted in frets.
        Positioned(
          left: lh ? 0 : 346,
          top: 0,
          width: 4,
          height: h,
          child: IgnorePointer(
            child: DecoratedBox(decoration: BoxDecoration(color: TruverColors.white(0.08), borderRadius: BorderRadius.circular(2))),
          ),
        ),
        Positioned(
          left: lh ? 0 : 346,
          top: math.max(0.0, top) / count * h,
          width: 4,
          height: math.max(8.0, (bottom - top) / count * h),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(color: TruverColors.textPrimary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ]),
    );
  }
}

// MARK: Landscape whole neck (canvas FixLandScale)

/// `LandscapeWholeNeck`: the portrait neck turned −90° (nut on the left, low string at the bottom) in a horizontal
/// scroll view: board 746 × 268 at (66, 76) of the 844 × 390 board, frets 1–12 in view; open strings at x 49, fret
/// numbers under the cells at 348, a 34 pt fade at the right edge, a 4 pt scroll bar at 368 counted in frets.
class LandscapeWholeNeck extends StatefulWidget {
  const LandscapeWholeNeck({super.key, required this.fretCount, required this.courses, required this.openCells, this.capoShift = 0, required this.neck});
  final int capoShift;
  final int fretCount;
  final int courses;
  final List<NeckCell> openCells;
  final NeckPortrait Function(int lo, int hi) neck;

  @override
  State<LandscapeWholeNeck> createState() => _LandscapeWholeNeckState();
}

class _LandscapeWholeNeckState extends State<LandscapeWholeNeck> {
  static const _length = 746.0;
  static const _across = 268.0;
  final _controller = ScrollController();
  double _offset = 0;

  double get _scale => (_length + 1) / NeckGeometry.unit(math.min(12, widget.fretCount));
  double get _content => _scale * NeckGeometry.unit(widget.fretCount) - 1;
  double _center(int n) => _scale * (NeckGeometry.unit(n - 1) + NeckGeometry.unit(n)) / 2 - 1;

  double _fretAt(double x) {
    final u = math.max(0.0, x / _scale);
    final u12 = NeckGeometry.unit(12), step = u12 - NeckGeometry.unit(11);
    if (u <= u12) return -12 * math.log(math.max(0.0001, 1 - u)) / math.ln2;
    return 12 + (u - u12) / step;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _offset = _controller.offset));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = NeckGeometry(size: const Size(_across, 30), courses: widget.courses, lo: 0, hi: 1);
    final top = _fretAt(_offset), bottom = _fretAt(_offset + _length + 1);
    final count = math.max(1, widget.fretCount);
    return Stack(clipBehavior: Clip.none, children: [
      for (final cell in widget.openCells)
        () {
          final tonic = cell.role == DegreeRole.tonic, chord = cell.role == DegreeRole.chordTone;
          final size = tonic ? 24.0 : (chord ? 14.0 : 10.0);
          final color = tonic ? NoteStyle.gold : (chord ? const Color(0xFF8FC4FF) : const Color.fromRGBO(150, 156, 166, 0.8));
          final y = 76 + _across - g.x(cell.course);
          return Positioned(
            left: 49 - size / 2,
            top: y - size / 2,
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0D0E10), border: Border.all(color: color, width: 2)),
              child: Center(
                child: tonic || chord ? Text.rich(Typo.notes(cell.label, Typo.fixed(10, TypoWeight.bold, color)), textScaler: TextScaler.noScaling) : null,
              ),
            ),
          );
        }(),
      Positioned(
        left: 39,
        top: 345,
        width: 20,
        height: 20,
        child: Center(child: Text('0', style: Typo.inter(11, TypoWeight.semibold, TruverColors.textSecondary))),
      ),
      Positioned(
        left: 66,
        top: 76,
        width: _length,
        height: _across + 30,
        child: ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(scrollbars: false, overscroll: false),
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _content,
              height: _across + 30,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: _content,
                  height: _across,
                  child: RotatedBox(quarterTurns: 3, child: widget.neck(1, widget.fretCount)),
                ),
                for (var n = math.max(1, widget.capoShift); n <= widget.fretCount; n++)
                  Positioned(
                    left: _center(n) - 10,
                    top: 269,
                    width: 20,
                    height: 20,
                    child: Center(
                      child: Text('${n - widget.capoShift}',
                          style: Typo.inter(11, TypoWeight.regular,
                              const [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(n) ? TruverColors.textSecondary : TruverColors.white(0.25))),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
      const Positioned(
        left: 778,
        top: 76,
        width: 34,
        height: _across,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x000D0E10), Color(0xFF0D0E10)])),
          ),
        ),
      ),
      Positioned(
        left: 66,
        top: 368,
        width: _length,
        height: 4,
        child: DecoratedBox(decoration: BoxDecoration(color: TruverColors.white(0.08), borderRadius: BorderRadius.circular(2))),
      ),
      Positioned(
        left: 66 + math.max(0.0, top) / count * _length,
        top: 368,
        width: math.max(8.0, (bottom - top) / count * _length),
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(color: TruverColors.textPrimary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
        ),
      ),
    ]);
  }
}

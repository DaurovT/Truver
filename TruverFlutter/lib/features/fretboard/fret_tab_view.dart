/// Port of Truver/Sources/Features/Fretboard/FretTabView.swift — «Таб»: the path as a tablature (canvas S6Tab,
/// S7Tab, S8Tab, TabLargeText, TabLandRuler, FlowNote3Tab; line rules of TabOtherInstruments).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/landscape.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'fretboard_controller.dart';
import 'progression_controller.dart';
import '../tour/coach_marks.dart';

/// One note of the tablature.
class TabNote {
  const TabNote({required this.course, required this.fret, required this.name, required this.isTonic});
  final int course;
  final int fret;
  final String name;
  final bool isTonic;
}

enum TabRule { perString, tab }

/// Geometry of one tablature system (one SVG of the canvas).
class TabLayout {
  TabLayout({
    this.rule = TabRule.perString,
    required this.courses,
    required this.labels,
    this.width = 350,
    required this.spacing,
    required this.fontSize,
    this.step = 37.5,
    this.firstX = 40,
    this.circleRadius = 10,
    this.notesPerBar = 4,
  });

  final TabRule rule;
  final int courses;
  final List<String> labels;
  double width;
  final double spacing;
  final double fontSize;
  double step;
  final double firstX;
  final double circleRadius;
  final int notesPerBar;

  TabLayout copy() => TabLayout(
    rule: rule,
    courses: courses,
    labels: labels,
    width: width,
    spacing: spacing,
    fontSize: fontSize,
    step: step,
    firstX: firstX,
    circleRadius: circleRadius,
    notesPerBar: notesPerBar,
  );

  double get topY => 24;
  double get lastY => topY + math.max(0, courses - 1) * spacing;
  double get namesY => lastY + (rule == TabRule.perString ? 22 : 24);
  double get height => lastY + (rule == TabRule.perString ? 30 : 34);
  double y(int course) => lastY - course * spacing;
  double x(int i) => firstX + i * step;

  /// Canvas line spacing: 18 up to 6 strings, 14 for 7, 13 for 8, 12 beyond.
  static double spacingFor(int courses) => courses <= 6 ? 18 : (courses == 7 ? 14 : (courses == 8 ? 13 : 12));

  /// Digits 15 pt up to 6 strings, 13 pt from 7.
  static double fontSizeFor(int courses) => courses <= 6 ? 15 : 13;

  Size plate(int digits) => Size(
    digits <= 1 ? 0.55 * fontSize + 3.85 : fontSize + 4 + (digits - 2) * 0.55 * fontSize,
    (fontSize * 1.1 * 10).roundToDouble() / 10,
  );

  Size tonicBox(int digits) {
    final p = plate(digits);
    return Size(p.width + 4, (fontSize * 1.4 * 10).roundToDouble() / 10);
  }
}

abstract final class TabColors {
  static const gold = Color(0xFFE8B54A);
  static const goldPlate = Color(0xFF3D3320);
  static const plate = Color(0xFF0D0E10);
  static const highlight = Color.fromRGBO(246, 243, 236, 0.07);
}

/// Inter's hhea ascender / descender: SVG `central` sits (0.96875 − 0.2421875) / 2 em above the baseline.
const _central = (0.96875 - 0.2421875) / 2;

/// Draws text like the SVG: `baseline` — the alphabetic baseline at `p.dy`, otherwise `dominant-baseline: central`.
/// `ax` — 0 start, 0.5 middle.
void _text(Canvas canvas, InlineSpan span, Offset p, {double ax = 0, bool baseline = false, required double size}) {
  final tp = TextPainter(text: span, textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)..layout();
  final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final baselineY = baseline ? p.dy : p.dy + _central * size;
  tp.paint(canvas, Offset(p.dx - ax * tp.width, baselineY - base));
}

TextSpan _span(String text, double size, TypoWeight weight, Color color) => Typo.notes(text, Typo.fixed(size, weight, color));

void _line(Canvas c, double x1, double y1, double x2, double y2, Color color) => c.drawLine(
  Offset(x1, y1),
  Offset(x2, y2),
  Paint()
    ..color = color
    ..strokeWidth = 1,
);

/// One system: lines with names, bar lines and numbers, the current column, digits and names under them.
class TabSystemView extends StatelessWidget {
  const TabSystemView({super.key, required this.layout, required this.notes, this.current, this.firstBar = 1});
  final TabLayout layout;
  final List<TabNote> notes;
  final int? current;
  final int firstBar;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Табулатура: ${layout.courses} струн',
    child: CustomPaint(size: Size(layout.width, layout.height), painter: _SystemPainter(layout, notes, current, firstBar)),
  );
}

class _SystemPainter extends CustomPainter {
  _SystemPainter(this.l, this.notes, this.current, this.firstBar);
  final TabLayout l;
  final List<TabNote> notes;
  final int? current;
  final int firstBar;

  @override
  void paint(Canvas canvas, Size size) {
    const tertiary = TruverColors.textTertiary;
    for (var course = 0; course < l.courses; course++) {
      final y = l.y(course);
      _text(canvas, _span(course < l.labels.length ? l.labels[course] : '', 11, TypoWeight.regular, tertiary), Offset(4, y), size: 11);
      _line(canvas, 22, y, l.width - 4, y, TruverColors.white(0.22));
    }
    if (notes.isEmpty) return;
    final bars = math.max(1, (notes.length / l.notesPerBar).ceil());
    final start = l.firstX - 6;
    final end = l.x(notes.length - 1) + l.step / 2;
    _line(canvas, start, l.topY, start, l.lastY, TruverColors.white(0.35));
    for (var bar = 0; bar < bars; bar++) {
      final left = bar == 0 ? start : l.x(bar * l.notesPerBar) - l.step / 2;
      if (bar > 0) _line(canvas, left, l.topY, left, l.lastY, TruverColors.white(0.18));
      final numberX = l.rule == TabRule.perString ? left + 3 : (l.x(bar * l.notesPerBar) - l.step / 2) + 4;
      _text(canvas, _span('${firstBar + bar}', 9, TypoWeight.regular, tertiary), Offset(numberX, 9), baseline: true, size: 9);
    }
    _line(canvas, end, l.topY, end, l.lastY, TruverColors.white(0.35));
    final cur = current;
    if (cur != null && cur < notes.length) {
      final w = l.step - 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(l.x(cur) - w / 2, 14, w, l.lastY + 10 - 14), const Radius.circular(6)),
        Paint()..color = TabColors.highlight,
      );
    }
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final x = l.x(i), y = l.y(n.course);
      final played = cur != null && i < cur;
      final alpha = played ? 0.35 : 1.0;
      final digits = '${n.fret}'.length;
      final isCurrent = cur == i;
      if (isCurrent) {
        canvas.drawCircle(Offset(x, y), l.circleRadius, Paint()..color = TruverColors.textPrimary);
      } else if (n.isTonic) {
        final b = l.tonicBox(digits);
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: b.width, height: b.height),
          const Radius.circular(5),
        );
        canvas.drawRRect(rect, Paint()..color = TabColors.goldPlate);
        canvas.drawRRect(
          rect.deflate(0),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = TabColors.gold.withValues(alpha: 0.6 * alpha),
        );
      } else {
        final p = l.plate(digits);
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: p.width, height: p.height), Paint()..color = TabColors.plate);
      }
      final color = isCurrent ? TruverColors.background : (n.isTonic ? TabColors.gold : TruverColors.textPrimary);
      final weight = isCurrent || n.isTonic ? TypoWeight.bold : TypoWeight.medium;
      _text(
        canvas,
        _span('${n.fret}', l.fontSize, weight, isCurrent ? color : color.withValues(alpha: alpha)),
        Offset(x, y),
        ax: 0.5,
        size: l.fontSize,
      );
      _text(
        canvas,
        _span(n.name, 10, TypoWeight.regular, (n.isTonic ? TabColors.gold : tertiary).withValues(alpha: alpha)),
        Offset(x, l.namesY),
        ax: 0.5,
        baseline: true,
        size: 10,
      );
    }
  }

  @override
  bool shouldRepaint(_SystemPainter old) => true;
}

/// Position ruler (canvas SVG × 48, viewBox from −6): ticks for every fret, the path's stretch as a track, the current
/// bar as an ivory thumb with «лады 4–9 · струна D» above.
class TabRuler extends StatelessWidget {
  const TabRuler({
    super.key,
    this.width = 350,
    required this.fretCount,
    required this.pathMaxFret,
    required this.lo,
    required this.hi,
    required this.title,
  });
  final double width;
  final int fretCount;
  final int pathMaxFret;
  final int lo;
  final int hi;
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Позиция: $title',
    child: CustomPaint(size: Size(width, 48), painter: _RulerPainter(this)),
  );
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.r);
  final TabRuler r;

  @override
  void paint(Canvas canvas, Size size) {
    final k = (r.width - 20) / math.max(1, r.fretCount);
    double x(int f) => 10 + f * k;
    const dy = 6.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(10, 12 + dy, r.pathMaxFret * k, 6), const Radius.circular(3)),
      Paint()..color = TruverColors.white(0.08),
    );
    const marks = {0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24, 27};
    for (var f = 0; f <= r.fretCount; f++) {
      final major = marks.contains(f);
      _line(canvas, x(f), 22 + dy, x(f), (major ? 26 : 24) + dy, TruverColors.white(major ? 0.4 : 0.18));
      if (major) {
        _text(
          canvas,
          _span('$f', 10, TypoWeight.regular, TruverColors.textTertiary),
          Offset(x(f), 38 + dy),
          ax: 0.5,
          baseline: true,
          size: 10,
        );
      }
    }
    final thumb = Rect.fromLTWH(x(r.lo) - 3, 9 + dy, (r.hi - r.lo) * k + 6, 12);
    canvas.drawRRect(RRect.fromRectAndRadius(thumb, const Radius.circular(6)), Paint()..color = const Color.fromRGBO(246, 243, 236, 0.55));
    _text(
      canvas,
      _span(r.title, 10.5, TypoWeight.semibold, TruverColors.textPrimary),
      Offset(thumb.center.dx, 5 + dy),
      ax: 0.5,
      baseline: true,
      size: 10.5,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) => true;
}

// MARK: Data from the controller

int _pitchClassOf(Map<String, dynamic> name) {
  const steps = [0, 2, 4, 5, 7, 9, 11];
  final letter = (name['letter'] as num?)?.toInt() ?? 0;
  final acc = (name['accidental'] as num?)?.toInt() ?? 0;
  return ((steps[letter % 7] + acc) % 12 + 12) % 12;
}

extension FretTabData on FretboardController {
  /// The tab replaces the neck and the tab bar (canvas S6Tab: full screen, back arrow in the header).
  bool get showsTabScreen => tabView && mode == FretMode.scale;

  List<TabNote> get tabNotes => [
    for (final n in pathNotes)
      TabNote(course: n.course, fret: n.fret, name: n.degree < spelled.length ? spelled[n.degree] : n.plain, isTonic: n.degree == 0),
  ];

  /// Line names, lowest course first; the top line is in lower case when its letter repeats lower down («e»).
  List<String> get tabLineLabels {
    final names = [for (var c = 0; c < app.courseCount; c++) app.stringName(c).replaceAll(RegExp(r'[-0-9]'), '')];
    if (names.isNotEmpty && names.sublist(0, names.length - 1).contains(names.last)) names[names.length - 1] = names.last.toLowerCase();
    return names;
  }

  /// «G · Мажор · путь»: the scale's short name (the canvas drops «(ионийский)»).
  String get tabTitle {
    var title = scaleTitle;
    final open = title.indexOf(' (');
    if (open >= 0 && title.endsWith(')')) title = title.substring(0, open);
    return '$title · путь';
  }

  String get pathKindTitle => switch (pathKind) {
    PathKind.threePerString => '3 ноты на струну',
    PathKind.oneString => 'По одной струне',
    _ => '4 ноты наискосок',
  };

  String get pathKindShortTitle => switch (pathKind) {
    PathKind.threePerString => '3 на струну',
    PathKind.oneString => 'по одной струне',
    _ => '4 наискосок',
  };

  /// Name of a course's open string without the octave («D»).
  String tabStringName(int course) => app.stringName(course).replaceAll(RegExp(r'[-0-9]'), '');

  /// Screenshot state of the tab boards: «4 ноты наискосок», the 10th note sounding (shown only — no sound).
  void tabDemo({required bool lowest}) {
    mode = FretMode.scale;
    if (lowest) {
      final starts = (data?.cells ?? const <CoreCell>[]).where((c) => c.course == 0 && c.degree != null && c.fret <= 4).toList()
        ..sort((a, b) => a.fret.compareTo(b.fret));
      if (starts.isNotEmpty) pathStart = NeckSpot(0, starts.first.fret);
    }
    pathKind = PathKind.fourDiagonal;
    tabView = true;
    if (pathNotes.length > 9) {
      playingNote = NeckSpot(pathNotes[9].course, pathNotes[9].fret);
      isPlaying = true;
    }
    changed();
  }

  /// Screenshot state of FlowNote3Tab: «A · I–V–vi–IV», the first chord, quarters.
  void progressionTabDemo() {
    mode = FretMode.progression; // takes the scale's key — the board's key is set after
    progression.templateId = 'pop';
    // FlowNote1 → «Прогрессия от A»: from A on the 6th string, 5th fret (course 2 of 8), the hand at frets 5–9.
    progression.start(NeckSpot(math.max(0, app.courseCount - 6), 5));
    progression.rhythm = StrumRhythm.perBeat;
    progression.loop = true;
    tabView = true;
  }
}

({int lo, int hi, String title}) _barWindow(FretboardController f, List<TabNote> notes, int? current) {
  final bar = (current ?? 0) ~/ 4;
  final slice = notes.skip(bar * 4).take(4).toList();
  if (slice.isEmpty) return (lo: 0, hi: 0, title: '');
  final lo = slice.map((n) => n.fret).reduce(math.min), hi = slice.map((n) => n.fret).reduce(math.max);
  final course = (current != null && current < notes.length) ? notes[current].course : slice.first.course;
  return (lo: lo, hi: hi, title: 'лады $lo–$hi · струна ${f.tabStringName(course)}');
}

/// System's current note: index inside it, `notes.length` when all of it is played, null before it.
int? _localCurrent(int? current, int start, int count) {
  if (current == null || current < start) return null;
  return math.min(current - start, count);
}

// MARK: Portrait screen (S6Tab, S7Tab, S8Tab, TabLargeText)

/// Full screen over the tab bar. Canvas coordinates minus the safe area (47 on the reference phone): header 50,
/// path row 104, ruler 150, systems from 204, legend 30 pt above the bottom edge.
class FretTabScreen extends StatefulWidget {
  const FretTabScreen({super.key});

  @override
  State<FretTabScreen> createState() => _FretTabScreenState();
}

class _FretTabScreenState extends State<FretTabScreen> {
  final _scroll = ScrollController();
  int? _scrolledFor;

  bool _large(BuildContext context, AppModel app) => app.args.has('-fretTabLarge') || MediaQuery.textScalerOf(context).scale(10) >= 13.5;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = app.fretboard;
    final large = _large(context, app);
    final notes = f.tabNotes;
    final current = f.pathIndex;
    final perSystem = large ? 4 : 8;
    final systems = <List<TabNote>>[
      for (var s = 0; s < notes.length; s += perSystem) notes.sublist(s, math.min(notes.length, s + perSystem)),
    ];
    final courses = app.courseCount;
    final layout = TabLayout(
      rule: large ? TabRule.tab : TabRule.perString,
      courses: courses,
      labels: f.tabLineLabels,
      spacing: large ? 21 : TabLayout.spacingFor(courses),
      fontSize: large ? 20 : TabLayout.fontSizeFor(courses),
      step: large ? 73.5 : 37.5,
      firstX: large ? 46 : 40,
      circleRadius: large ? 11 : 10,
    );
    final gap = large ? 17.0 : (systems.length * (layout.height + 52) <= 610 ? 52.0 : math.max(3.0, 152 - layout.height));
    final window = _barWindow(f, notes, current);
    final tonic = f.data?.tonicText ?? '';

    // Keep the sounding system in view: the system before it at the top (large text — the system itself).
    if (current != null && _scrolledFor != current) {
      final first = _scrolledFor == null;
      _scrolledFor = current;
      final system = current ~/ perSystem;
      final target = large ? system : math.max(0, system - 1);
      final offset = target * (layout.height + gap);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final to = math.min(offset, _scroll.position.maxScrollExtent);
        if (first || Motion.reduced(context)) {
          _scroll.jumpTo(to);
        } else {
          _scroll.animateTo(to, duration: Motion.move, curve: Motion.out);
        }
      });
    }

    final segments = SizedBox(
      width: 120,
      child: Segments<bool>(options: const [(false, 'Гриф'), (true, 'Таб')], selection: f.tabView, onChanged: (v) => f.tabView = v),
    );
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, box) {
          final systemsTop = large ? 113.0 : 157.0;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 20, top: 3, width: 350, height: 44, child: _header(app, large)),
              if (large)
                Positioned(
                  left: 20,
                  top: 61,
                  width: 350,
                  child: Row(
                    children: [
                      Expanded(
                        child: NoteText(window.title, style: Typo.fixed(17, TypoWeight.semibold, TruverColors.textPrimary), maxLines: 1),
                      ),
                      const SizedBox(width: 8),
                      segments,
                    ],
                  ),
                )
              else ...[
                Positioned(
                  left: 20,
                  top: 57,
                  width: 350,
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Pressable(
                            onTap: () => app.sheet = const AppSheet('fretPath'),
                            label: 'Путь: ${f.pathKindTitle}',
                            child: HeaderChip(text: f.pathKindTitle, icon: AppIcon.chevronDown, iconSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      segments,
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 103,
                  child: TabRuler(
                    fretCount: (app.instrument['fretCount'] as num?)?.toInt() ?? 24,
                    pathMaxFret: notes.isEmpty ? 0 : notes.map((n) => n.fret).reduce(math.max),
                    lo: window.lo,
                    hi: window.hi,
                    title: window.title,
                  ),
                ),
              ],
              Positioned(
                left: 0,
                right: 0,
                top: systemsTop,
                height: math.max(100, box.maxHeight - systemsTop - (large ? 0 : 30)),
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < systems.length; i++) ...[
                        if (i > 0) SizedBox(height: gap),
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          // Coach mark «Как читать табулатуру» (features/tour): the sounding system, else the first.
                          child: CoachAnchor(
                            id: i == (current == null ? 0 : current ~/ perSystem) ? CoachAnchors.tabSystem : null,
                            child: TabSystemView(
                              layout: _systemLayout(layout, systems[i].length, perSystem, large),
                              notes: systems[i],
                              current: _localCurrent(current, i * perSystem, systems[i].length),
                              firstBar: i * perSystem ~/ 4 + 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (large)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 60,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x000D0E10), TabColors.plate],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  left: 20,
                  width: 350,
                  bottom: 0,
                  height: 30,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        notes.any((n) => n.fret == 0) ? '0 — открытая струна · черта — такт' : 'цифра — лад · черта — такт',
                        style: Typo.fixed(11, TypoWeight.regular, TruverColors.textTertiary),
                        maxLines: 1,
                      ),
                      NoteText(
                        'тоника $tonic — в рамке',
                        style: Typo.fixed(11, TypoWeight.regular, TruverColors.textTertiary),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// A short last system is narrower (canvas S7Tab: 205 pt for one bar), its notes a little wider apart.
  TabLayout _systemLayout(TabLayout layout, int count, int perSystem, bool large) {
    if (count >= perSystem || large || count == 0) return layout;
    final l = layout.copy();
    l.width = 30 + 350 * count / perSystem;
    l.step = (l.width - 29.4 - l.firstX) / (count - 0.5);
    return l;
  }

  Widget _header(AppModel app, bool large) {
    final f = app.fretboard;
    final n = f.pathNotes.length;
    final i = (f.pathIndex ?? 0) + 1;
    final first = f.pathFirstName;
    return Row(
      children: [
        RoundIconButton(icon: AppIcon.chevronLeft, size: 40, label: 'Назад', onTap: () => f.tabView = false),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NoteText(f.tabTitle, style: Typo.fixed(16, TypoWeight.medium, TruverColors.textPrimary), maxLines: 1),
              const SizedBox(height: 1),
              NoteText(
                first.isEmpty || (f.pathNotes.isNotEmpty && f.pathNotes.first.degree == 0) ? '$i / $n' : '$i / $n · от $first',
                style: Typo.fixed(12, TypoWeight.regular, TruverColors.textTertiary),
                maxLines: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        PrimaryRoundButton(
          icon: f.isPlaying ? AppIcon.pause : AppIcon.play,
          size: large ? 48 : 44,
          iconSize: 20,
          label: f.isPlaying ? 'Пауза' : 'Сыграть путь',
          onTap: f.togglePlayback,
        ),
      ],
    );
  }
}

// MARK: Landscape (TabLandRuler, 844 × 390)

/// Header (top 16, from x 40, 764 wide): back 44, title 15 medium, path chip, «Гриф | Таб» 150, «10 / 32», play 48;
/// ruler 764 at top 80; the whole path in one system (8 bars) at top 132; legend 12 pt at top 362.
class FretTabLandscape extends StatelessWidget {
  const FretTabLandscape({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = app.fretboard;
    final notes = f.tabNotes;
    final current = f.pathIndex;
    const perSystem = 32;
    final systems = <List<TabNote>>[
      for (var s = 0; s < notes.length; s += perSystem) notes.sublist(s, math.min(notes.length, s + perSystem)),
    ];
    final courses = app.courseCount;
    final layout = TabLayout(
      rule: TabRule.tab,
      courses: courses,
      labels: f.tabLineLabels,
      width: 764,
      spacing: courses <= 6 ? 28 : (courses == 7 ? 25 : 22),
      fontSize: 13,
      step: 88.75 / 4,
      firstX: 44,
    );
    final window = _barWindow(f, notes, current);
    final tonic = f.data?.tonicText ?? '';
    final open = notes.any((n) => n.fret == 0);
    return MediaQuery.withNoTextScaling(
      child: LandscapeCanvas(
        child: Stack(
          children: [
            Board(x: 40, y: 16, width: 764, child: SizedBox(height: 48, child: _header(app))),
            Board(
              x: 40,
              y: 80,
              child: TabRuler(
                width: 764,
                fretCount: (app.instrument['fretCount'] as num?)?.toInt() ?? 24,
                pathMaxFret: notes.isEmpty ? 0 : notes.map((n) => n.fret).reduce(math.max),
                lo: window.lo,
                hi: window.hi,
                title: window.title,
              ),
            ),
            Positioned(
              left: 40,
              top: 132,
              width: 764,
              height: 226,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < systems.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      TabSystemView(
                        layout: layout,
                        notes: systems[i],
                        current: _localCurrent(current, i * perSystem, systems[i].length),
                        firstBar: i * perSystem ~/ 4 + 1,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Board(
              x: 40,
              y: 362,
              width: 764,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${open ? '0 — открытая струна' : 'цифра — лад'} · черта — такт (4 ноты = такт 4/4, четвертями) · номер такта сверху',
                    style: Typo.fixed(12, TypoWeight.regular, TruverColors.textTertiary),
                    maxLines: 1,
                  ),
                  NoteText('тоника $tonic — в рамке', style: Typo.fixed(12, TypoWeight.regular, TruverColors.textTertiary), maxLines: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppModel app) {
    final f = app.fretboard;
    return Row(
      children: [
        RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Назад', onTap: () => f.tabView = false),
        const SizedBox(width: 10),
        NoteText(f.tabTitle, style: Typo.fixed(15, TypoWeight.medium, TruverColors.textPrimary), maxLines: 1),
        const SizedBox(width: 10),
        Pressable(
          onTap: () => app.sheet = const AppSheet('fretPath'),
          label: 'Путь: ${f.pathKindTitle}',
          child: HeaderChip(text: f.pathKindShortTitle, icon: AppIcon.chevronDown, iconSize: 12),
        ),
        const Spacer(),
        SizedBox(
          width: 150,
          height: 38,
          child: Segments<bool>(options: const [(false, 'Гриф'), (true, 'Таб')], selection: f.tabView, onChanged: (v) => f.tabView = v),
        ),
        const SizedBox(width: 10),
        Chip(text: '${(f.pathIndex ?? 0) + 1} / ${f.pathNotes.length}', style: ChipStyle.muted),
        const SizedBox(width: 10),
        PrimaryRoundButton(
          icon: f.isPlaying ? AppIcon.pause : AppIcon.play,
          size: 48,
          iconSize: 20,
          label: f.isPlaying ? 'Пауза' : 'Сыграть путь',
          onTap: f.togglePlayback,
        ),
      ],
    );
  }
}

// MARK: Progression as a chord tab (FlowNote3Tab)

/// Below the progression row (canvas top 210): «Где на грифе: лады 5–11 · …», the chord tab (350 × 208 at 236), the
/// «Ритм / Повторять» card at 500 and «Такт 1 из 4 · A» with «Сыграть» at 686. The widget's top is the caption's top.
class ProgressionTabBody extends StatelessWidget {
  const ProgressionTabBody({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.fretboard.progression;
    final frets = [
      for (final v in p.voiced)
        if (v.voicing != null)
          for (final n in v.voicing!.notes)
            if (n.fret > 0) n.fret,
    ];
    final lo = frets.isEmpty ? 0 : frets.reduce(math.min), hi = frets.isEmpty ? 0 : frets.reduce(math.max);
    final n = p.voiced.length;
    final word = n % 10 == 1 && n % 100 != 11
        ? 'аккорд'
        : ((n % 10 >= 2 && n % 10 <= 4) && !(n % 100 >= 12 && n % 100 <= 14) ? 'аккорда' : 'аккордов');
    final tail = hi - lo <= 7 ? ' · все $n $word рядом, без прыжков' : ' · рука переходит по грифу';
    final meter = app.settings.metronome.meter;
    final rhythm = switch (p.rhythm) {
      StrumRhythm.perBar => 'по тактам',
      StrumRhythm.perBeat => 'по четвертям',
      StrumRhythm.downUpEighths => 'восьмыми вниз-вверх',
    };
    final currentName = p.current < p.voiced.length ? Typo.compactChordName(p.voiced[p.current].name) : '';
    // Starts right under the 38 pt progression row (canvas: row 154, caption 210); centred at any parent width.
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 350,
        height: 546,
        padding: const EdgeInsets.only(top: 18),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 2,
              top: 0,
              width: 348,
              child: Text.rich(
                TextSpan(
                  style: Typo.caption.copyWith(color: TruverColors.textTertiary),
                  children: [
                    const TextSpan(text: 'Где на грифе: '),
                    TextSpan(
                      text: 'лады $lo–$hi',
                      style: const TextStyle(color: TruverColors.textPrimary),
                    ),
                    TextSpan(text: tail),
                  ],
                ),
              ),
            ),
            const Positioned(left: 0, top: 26, child: ProgressionTabTable()),
            Positioned(
              left: 0,
              top: 290,
              width: 350,
              child: CardGroup(
                children: [
                  Pressable(
                    onTap: () => app.sheet = const AppSheet('fretProgression'),
                    label: 'Ритм',
                    child: CardRow(
                      title: 'Ритм',
                      minHeight: 50,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$rhythm · ${meter['numerator']}/${meter['denominator']}'),
                          const SizedBox(width: 8),
                          const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  CardRow(
                    title: 'Повторять',
                    minHeight: 50,
                    trailing: ToggleSwitch(isOn: p.loop, onChanged: (v) => p.loop = v, label: 'Повторять'),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 476,
              width: 350,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NoteText(
                          'Такт ${p.current + 1} из $n · $currentName',
                          style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary),
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text('в рамке — тоника аккорда', style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary), maxLines: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pressable(
                    onTap: p.toggle,
                    label: p.isPlaying ? 'Пауза' : 'Сыграть прогрессию',
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.only(left: 14, right: 18),
                      decoration: const ShapeDecoration(
                        color: TruverColors.textPrimary,
                        shape: StadiumBorder(),
                        shadows: [BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 6))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIconView(p.isPlaying ? AppIcon.pause : AppIcon.play, size: 18, color: TruverColors.background),
                          const SizedBox(width: 8),
                          Text(p.isPlaying ? 'Пауза' : 'Сыграть', style: Typo.inter(16, TypoWeight.semibold, TruverColors.background)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chord tab itself: one column per chord, the chord root boxed.
class ProgressionTabTable extends StatelessWidget {
  const ProgressionTabTable({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = app.fretboard;
    final p = f.progression;
    final courses = app.courseCount;
    const spacing = 22.0, top = 40.0;
    final last = top + (courses - 1) * spacing;
    return Semantics(
      label: 'Табулатура аккордов: ${p.voiced.map((v) => Typo.compactChordName(v.name)).join(', ')}',
      child: CustomPaint(
        size: Size(350, last + 14),
        painter: _ChordTabPainter(
          labels: f.tabLineLabels,
          courses: courses,
          voiced: p.voiced,
          numerals: [for (final r in p.rows) r.numeral],
          current: p.current,
        ),
      ),
    );
  }
}

class _ChordTabPainter extends CustomPainter {
  _ChordTabPainter({required this.labels, required this.courses, required this.voiced, required this.numerals, required this.current});
  final List<String> labels;
  final int courses;
  final List<VoicedChord> voiced;
  final List<String> numerals;
  final int current;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 22.0, top = 40.0;
    final last = top + (courses - 1) * spacing;
    final count = math.max(1, voiced.length);
    final colW = 300 / count;
    for (var course = 0; course < courses; course++) {
      final y = last - course * spacing;
      _text(
        canvas,
        _span(course < labels.length ? labels[course] : '', 11, TypoWeight.regular, TruverColors.textTertiary),
        Offset(6, y),
        size: 11,
      );
      _line(canvas, 28, y, 346, y, TruverColors.white(0.2));
    }
    for (var i = 0; i <= count; i++) {
      final x = 32 + i * colW;
      _line(canvas, x, top, x, last, TruverColors.white(i == 0 || i == count ? 0.35 : 0.2));
    }
    for (var i = 0; i < voiced.length; i++) {
      final v = voiced[i];
      final cx = 32 + colW * (i + 0.5);
      final isCurrent = i == current;
      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(cx - colW / 2 + 6, 6, colW - 12, last + 8), const Radius.circular(8)),
          Paint()..color = TabColors.highlight,
        );
      }
      _text(
        canvas,
        _span(Typo.compactChordName(v.name), 15, TypoWeight.semibold, isCurrent ? TruverColors.textPrimary : TruverColors.textBody),
        Offset(cx, 22),
        ax: 0.5,
        baseline: true,
        size: 15,
      );
      _text(
        canvas,
        _span(i < numerals.length ? numerals[i] : '', 10, TypoWeight.regular, TruverColors.textTertiary),
        Offset(cx, 34),
        ax: 0.5,
        baseline: true,
        size: 10,
      );
      final voicing = v.voicing;
      if (voicing == null) continue;
      final rootPc = _pitchClassOf(v.root);
      for (final n in voicing.notes) {
        final y = last - n.course * spacing;
        final digits = '${n.fret}'.length;
        final root = n.pc == rootPc;
        if (root) {
          final w = digits == 1 ? 16.0 : 23.0;
          final rect = RRect.fromRectAndRadius(Rect.fromLTWH(cx - w / 2, y - 8.5, w, 17), const Radius.circular(5));
          canvas.drawRRect(rect, Paint()..color = TabColors.goldPlate);
          canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = TabColors.gold.withValues(alpha: 0.6),
          );
        } else {
          final w = digits == 1 ? 12.0 : 19.0;
          canvas.drawRect(Rect.fromLTWH(cx - w / 2, y - 7, w, 14), Paint()..color = TabColors.plate);
        }
        _text(
          canvas,
          _span('${n.fret}', 14, root ? TypoWeight.bold : TypoWeight.medium, root ? TabColors.gold : TruverColors.textPrimary),
          Offset(cx, y),
          ax: 0.5,
          size: 14,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ChordTabPainter old) => true;
}

/// The fretboard tab: the tab screen instead of the neck while «Таб» is on in «Гамма» (registered in
/// `fretboard_feature.dart`; iOS switches in `FretboardScreen.body`).
class FretboardTabSwitch extends StatelessWidget {
  const FretboardTabSwitch({super.key, required this.landscape, required this.neck});
  final bool landscape;
  final WidgetBuilder neck;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.fretboard.showsTabScreen) return neck(context);
    return landscape ? const FretTabLandscape() : const FretTabScreen();
  }
}

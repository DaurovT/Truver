/// Port of Truver/Sources/Features/Tour/CoachMarks.swift
///
/// Coach marks of the canvas «Знакомство и обучение» (CoachTuner1–3, CoachFret1–3, CoachTab, CoachChord,
/// CoachMetro1–2, CoachPractice). One to three hints the first time a section or a feature opens: the screen dims
/// (#030304 at 74 %) except a hole around the element, a 2 pt ivory ring 4 pt outside the hole, and an ivory bubble
/// with an arrow.
///
/// Behaviour (canvas note «Знакомство»): only when the section is opened for the first time; not while the tuner hears
/// a note or the metronome plays; «Пропустить» turns off the hints of this section; repeat: Settings → «Обучение».
/// Hints are armed by finishing the first-run onboarding (or «Показать подсказки заново»), so screenshot launches
/// (`-skipOnboarding`) never show them; `-coach tuner1…` shows one directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../fretboard/fretboard_controller.dart';
import '../fretboard/neck_portrait.dart';
import '../tuner/tuner_controller.dart';

/// Sections with hints, in the order of the canvas note.
enum CoachSection { tuner, fret, tab, chord, metro, practice }

/// One hint. The hole is the union of the anchors' frames grown by `outset` (canvas values: the boards place the hole
/// by hand, a few points off the element on some boards). The bubble sits `gap` above or below the hole.
class CoachStep {
  const CoachStep({
    required this.title,
    required this.text,
    required this.anchors,
    required this.radius,
    this.outset = EdgeInsets.zero,
    required this.below,
    required this.gap,
  });

  final String title;
  final String text;
  final List<String> anchors;

  /// Hole corner radius (CSS `border-radius`; ≥ half the side — a circle).
  final double radius;
  final EdgeInsets outset;

  /// Bubble under the hole (arrow up) or above it (arrow down).
  final bool below;
  final double gap;
}

/// Anchor ids set by the screens with [CoachAnchor].
abstract final class CoachAnchors {
  static const tunerStrings = 'tuner.strings';
  static const tunerReference = 'tuner.reference';
  static const tunerMore = 'tuner.more';
  static const tuningPill = 'shell.tuningPill';
  static const scalePill = 'fret.scalePill';
  static const firstTonic = 'fret.firstTonic';
  static const keyChords = 'fret.keyChords';
  static const tabSystem = 'fret.tabSystem';
  static const voicingPrev = 'fret.voicingPrev';
  static const voicingNext = 'fret.voicingNext';
  static const knob = 'metro.knob';
  static const chips = 'metro.chips';
  static const trainer = 'practice.trainer';
}

abstract final class CoachCatalog {
  // Gaps: the canvas bubble's edge to the hole's edge (bubble height = 16 + 20.57 + 6 + lines × 20.3 + 14 + 38 + 14).
  static List<CoachStep> steps(CoachSection section) => switch (section) {
    CoachSection.tuner => const [
      CoachStep(
        title: 'Тюнер сам узнаёт струну',
        text:
            'Просто играйте. Если мешает шум или соседние струны — нажмите нужную струну здесь, и тюнер будет слушать только её',
        anchors: [CoachAnchors.tunerStrings],
        radius: 14,
        below: false,
        gap: 12.5,
      ),
      CoachStep(
        title: 'Настроить на слух',
        text:
            'Волна — Truver сыграет ноту выбранной струны. Кнопка рядом — строб для очень точной подстройки и крупный сценический экран',
        anchors: [CoachAnchors.tunerReference, CoachAnchors.tunerMore],
        radius: 26,
        outset: EdgeInsets.fromLTRB(8, 4, 6, 4),
        below: false,
        gap: 10.2,
      ),
      // Canvas hole 210 × 48 is narrower than the pill (it cuts both ends): the hole hugs the pill instead; the bubble
      // stays where the canvas has it (gap 24.5 + 4).
      CoachStep(
        title: 'Строй и инструмент — здесь',
        text: 'Drop D, полтона ниже, свой строй или другой инструмент. Выбранный строй сразу применится к грифу',
        anchors: [CoachAnchors.tuningPill],
        radius: 24,
        outset: EdgeInsets.all(4),
        below: false,
        gap: 28.5,
      ),
    ],
    CoachSection.fret => const [
      CoachStep(
        title: 'Выберите гамму',
        text: 'Тонику и вид гаммы. Жёлтые точки — тоника, синие — ноты аккорда, кружки — остальные ноты гаммы',
        anchors: [CoachAnchors.scalePill],
        radius: 20,
        outset: EdgeInsets.fromLTRB(0, 3, 4, 1),
        below: true,
        gap: 24,
      ),
      CoachStep(
        title: 'Нажмите на ноту',
        text: 'Откроется меню: гамма, аккорды или прогрессия от этой ноты. Гриф листается вверх и вниз до 24-го лада',
        anchors: [CoachAnchors.firstTonic],
        radius: 30,
        outset: EdgeInsets.fromLTRB(19, 18, 15, 16),
        below: true,
        gap: 30,
      ),
      // Canvas hole 606…662 sits 12 pt above the chord strip (618…670) and cuts it: the hole hugs the strip.
      CoachStep(
        title: 'Аккорды этой гаммы',
        text: 'Нажмите аккорд — его ноты подсветятся на грифе. Римские цифры — ступень: I, IV и V звучат вместе лучше всего',
        anchors: [CoachAnchors.keyChords],
        radius: 14,
        outset: EdgeInsets.fromLTRB(0, 2, 0, 2),
        below: false,
        gap: 42.5,
      ),
    ],
    CoachSection.tab => const [
      CoachStep(
        title: 'Как читать табулатуру',
        text: 'Линии — струны, нижняя — самая толстая. Цифра — какой лад зажать, 0 — открытая струна. Играйте слева направо',
        anchors: [CoachAnchors.tabSystem],
        radius: 14,
        outset: EdgeInsets.fromLTRB(0, 94, 0, -22),
        below: true,
        gap: 21,
      ),
    ],
    CoachSection.chord => const [
      CoachStep(
        title: 'Этот же аккорд в другом месте',
        text: 'Стрелками — другие расположения на грифе. Сначала самые простые, дальше — с баррэ и растяжкой',
        anchors: [CoachAnchors.voicingPrev, CoachAnchors.voicingNext],
        radius: 26,
        outset: EdgeInsets.fromLTRB(0, 6, 4, 2),
        below: false,
        gap: 22.5,
      ),
    ],
    CoachSection.metro => const [
      CoachStep(
        title: 'Темп — ручкой',
        text: 'Ведите пальцем по кругу: по часовой — быстрее. Или простучите ритм на кнопке «Тап» внизу',
        anchors: [CoachAnchors.knob],
        radius: 1000,
        outset: EdgeInsets.all(-10),
        below: true,
        gap: 30,
      ),
      CoachStep(
        title: 'Размер и режимы',
        text:
            '7/8, деление доли, разгон и пропуски — здесь. «Проверка» слушает вашу игру и показывает, где вы спешите. Всё вместе сохраняется в пресет',
        anchors: [CoachAnchors.chips],
        radius: 24,
        outset: EdgeInsets.fromLTRB(0, 6, 0, 6),
        below: true,
        gap: 16,
      ),
    ],
    CoachSection.practice => const [
      CoachStep(
        title: 'Выучите ноты на грифе',
        text:
            'Тренажёр показывает место на грифе — вы называете ноту или играете её. Начните с ладов 1–5 и расширяйте, когда станет легко',
        anchors: [CoachAnchors.trainer],
        radius: 16,
        outset: EdgeInsets.only(top: 4, bottom: -2),
        below: true,
        gap: 18,
      ),
    ],
  };

  /// `-coach tuner1 | tuner2 | tuner3 | fret1…3 | tab | chord | metro1 | metro2 | practice` (canvas board names).
  static (CoachSection, int)? parse(String? value) {
    if (value == null) return null;
    for (final section in CoachSection.values) {
      if (!value.startsWith(section.name)) continue;
      final rest = value.substring(section.name.length);
      if (rest.isEmpty) return (section, 0);
      final n = int.tryParse(rest);
      if (n != null && n >= 1 && n <= steps(section).length) return (section, n - 1);
    }
    return null;
  }

  /// «Нажмите на ноту»: the tonic nearest the nut on the lowest string that has one (canvas: G on the 8th string, 1st fret).
  static NeckSpot? firstTonic(Iterable<NeckCell> cells) {
    NeckCell? best;
    for (final c in cells) {
      if (c.role != DegreeRole.tonic || c.fret < 1 || c.fret > 12) continue;
      if (best == null || c.fret < best.fret || (c.fret == best.fret && c.course < best.course)) best = c;
    }
    return best == null ? null : NeckSpot(best.course, best.fret);
  }
}

/// The running hint.
@immutable
class CoachRun {
  const CoachRun(this.section, this.steps, this.position, {this.debug = false});
  final CoachSection section;

  /// Indices of the catalog steps shown (steps whose anchor is missing on this layout are left out).
  final List<int> steps;
  final int position;

  /// Launched by `-coach`: nothing is saved.
  final bool debug;

  CoachStep get step => CoachCatalog.steps(section)[steps[position]];
  bool get isLast => position == steps.length - 1;
}

/// Hints state: anchors reported by the screens, the running hint, and what has been seen (the settings store, key
/// `coach`). One per app; `attach` binds it to the app model at launch (`registerTour`'s debug hook).
class CoachCenter extends ChangeNotifier {
  CoachCenter._();
  static final instance = CoachCenter._();

  final Map<String, BuildContext> _anchors = {};
  SettingsStore? _store;

  CoachRun? _run;
  CoachRun? get run => _run;

  bool _enabled = true;
  bool _armed = false;
  Set<String> _seen = {};

  /// `-coach <board>`: the section and step to show at launch.
  (CoachSection, int)? forced;

  /// «Подсказки на экранах».
  bool get enabled => _enabled;
  set enabled(bool v) {
    _enabled = v;
    _save();
    notifyListeners();
  }

  bool get armed => _armed;

  void attach(AppModel app) {
    _store = app.store;
    _run = null;
    final raw = app.store.getString('coach');
    final json = raw == null ? const <String, dynamic>{} : (jsonDecode(raw) as Map<String, dynamic>);
    _enabled = json['enabled'] as bool? ?? true;
    _armed = json['armed'] as bool? ?? false;
    _seen = {...(json['seen'] as List? ?? const []).cast<String>()};
    forced = CoachCatalog.parse(app.args.value('-coach'));
  }

  void _save() => _store?.setString('coach', jsonEncode({'enabled': _enabled, 'armed': _armed, 'seen': _seen.toList()}));

  bool wants(CoachSection section) => _armed && _enabled && !_seen.contains(section.name);

  /// Onboarding finished / «Показать подсказки заново»: every section shows its hints again.
  void arm() {
    _armed = true;
    _enabled = true;
    _seen = {};
    _save();
    notifyListeners();
  }

  // MARK: Anchors

  void register(String id, BuildContext context) => _anchors[id] = context;

  void unregister(String id, BuildContext context) {
    if (identical(_anchors[id], context)) _anchors.remove(id);
  }

  /// The anchor's frame in the root's (global) coordinates.
  Rect? anchorRect(String id) {
    final context = _anchors[id];
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? frame(CoachStep step) {
    Rect? r;
    for (final id in step.anchors) {
      final a = anchorRect(id);
      if (a == null || a.isEmpty) return null;
      r = r == null ? a : r.expandToInclude(a);
    }
    if (r == null) return null;
    return Rect.fromLTRB(
      r.left - step.outset.left,
      r.top - step.outset.top,
      r.right + step.outset.right,
      r.bottom + step.outset.bottom,
    );
  }

  // MARK: Run

  /// Starts the section's hints with the steps whose anchors are on screen; false when none is.
  bool start(CoachSection section, {int at = 0, bool debug = false}) {
    final all = CoachCatalog.steps(section);
    final shown = [
      for (var i = 0; i < all.length; i++)
        if (debug || frame(all[i]) != null) i,
    ];
    if (shown.isEmpty) return false;
    final position = shown.indexOf(at);
    _run = CoachRun(section, shown, position < 0 ? 0 : position, debug: debug);
    assert(() {
      if (debug) {
        for (final id in (_anchors.keys.toList()..sort())) {
          final r = anchorRect(id);
          if (r != null) debugPrint('COACH anchor $id ${r.left} ${r.top} ${r.width} ${r.height}');
        }
      }
      return true;
    }());
    notifyListeners();
    return true;
  }

  void next() {
    final r = _run;
    if (r == null) return;
    if (!r.isLast) {
      _run = CoachRun(r.section, r.steps, r.position + 1, debug: r.debug);
      notifyListeners();
    } else {
      finish();
    }
  }

  /// «Понятно» on the last step or «Пропустить»: the section is done.
  void finish() {
    final r = _run;
    if (r == null) return;
    if (!r.debug) {
      _seen.add(r.section.name);
      _save();
    }
    _run = null;
    notifyListeners();
  }
}

/// Reports its child's frame for the coach marks ([CoachAnchors]). `id: null` — no anchor.
class CoachAnchor extends StatefulWidget {
  const CoachAnchor({super.key, required this.id, required this.child});
  final String? id;
  final Widget child;

  @override
  State<CoachAnchor> createState() => _CoachAnchorState();
}

class _CoachAnchorState extends State<CoachAnchor> {
  @override
  void initState() {
    super.initState();
    if (widget.id != null) CoachCenter.instance.register(widget.id!, context);
  }

  @override
  void didUpdateWidget(CoachAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (old.id != null) CoachCenter.instance.unregister(old.id!, context);
      if (widget.id != null) CoachCenter.instance.register(widget.id!, context);
    }
  }

  @override
  void dispose() {
    if (widget.id != null) CoachCenter.instance.unregister(widget.id!, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// MARK: Host

/// Watches the app and shows the hints over everything (`FeatureRegistry.overlays`).
class CoachHost extends StatefulWidget {
  const CoachHost({super.key});

  @override
  State<CoachHost> createState() => _CoachHostState();
}

class _CoachHostState extends State<CoachHost> {
  Timer? _timer;
  CoachSection? _pending;
  bool _forcedTried = false;

  CoachCenter get center => CoachCenter.instance;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The section whose hints the current screen offers now (null — none, or not now).
  CoachSection? _candidate(AppModel app) {
    if (center.run != null || app.showOnboarding || app.showSettings || app.showSession || app.showTrainer) return null;
    if (app.sheet != null || app.notice != null) return null;
    final CoachSection? section;
    switch (app.tab) {
      case AppTab.tuner:
        // «Не показываются, пока идёт настройка»: wait until the tuner hears nothing.
        section = app.tuner.display.kind == TunerDisplayKind.reading ? null : CoachSection.tuner;
      case AppTab.fretboard:
        final f = app.fretboard;
        if (f.tabView && f.mode == FretMode.scale) {
          section = CoachSection.tab;
        } else if (f.mode == FretMode.chord) {
          section = CoachSection.chord;
        } else if (f.mode == FretMode.scale && f.noteSpot == null && f.pathKind == null && !f.isTraining) {
          section = CoachSection.fret;
        } else {
          section = null;
        }
      case AppTab.metronome:
        section = app.metronome.isPlaying ? null : CoachSection.metro;
      case AppTab.practice:
        section = CoachSection.practice;
    }
    return section != null && center.wants(section) ? section : null;
  }

  void _schedule(AppModel app, CoachSection? candidate) {
    if (candidate == _pending) return;
    _pending = candidate;
    _timer?.cancel();
    if (candidate == null) return;
    // The screen settles (tab switch, layout) and the person looks at it first.
    _timer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _candidate(app) != candidate) return;
      _pending = null;
      center.start(candidate);
    });
  }

  void _tryForced() {
    final f = center.forced;
    if (f == null) return;
    final (section, step) = f;
    final steps = CoachCatalog.steps(section);
    // Screenshot hook: shown once the board's anchor is laid out.
    if (step < steps.length && center.frame(steps[step]) == null && !_forcedTried) {
      _forcedTried = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _forcedTried = false;
        if (mounted) _tryForced();
      });
      SchedulerBinding.instance.scheduleFrame();
      return;
    }
    center.forced = null;
    center.start(section, at: step, debug: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([center, app, app.tuner, app.fretboard, app.metronome]),
      builder: (context, _) {
        final candidate = _candidate(app);
        if (center.forced != null || candidate != _pending) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (center.forced != null) _tryForced();
            _schedule(app, _candidate(app));
          });
        }
        final run = center.run;
        // `-coach` (screenshots): at once, without the fade.
        if (run != null && run.debug) return CoachOverlay(key: ValueKey(run.section), run: run);
        return AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.out,
          switchOutCurve: Motion.out,
          child: run == null ? const SizedBox.shrink() : CoachOverlay(key: ValueKey(run.section), run: run),
        );
      },
    );
  }
}

/// Canvas colours of the hints (only here).
abstract final class CoachColors {
  static const dim = Color(0xBD030304); // #030304 at 74 %
  static const ring = Color(0xB3F6F3EC); // 70 %
  static const bubble = Color(0xFFF6F3EC);
  static const ink = Color(0xFF0C0D0F);
  static const text = Color(0xFF3A3B3F);
  static const counter = Color(0xFF6B6C70);
}

/// The dim with a hole, the ring and the bubble. Follows the anchors every frame (scrolling, layout changes).
class CoachOverlay extends StatefulWidget {
  const CoachOverlay({super.key, required this.run});
  final CoachRun run;

  @override
  State<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<CoachOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    _hole = CoachCenter.instance.frame(widget.run.step);
    _ticker.start();
  }

  void _tick(Duration _) {
    final hole = CoachCenter.instance.frame(widget.run.step);
    if (hole != _hole) setState(() => _hole = hole);
  }

  @override
  void didUpdateWidget(CoachOverlay old) {
    super.didUpdateWidget(old);
    _hole = CoachCenter.instance.frame(widget.run.step);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final step = run.step;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final hole = _hole ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
        final radius = math.min(step.radius, math.min(hole.width, hole.height) / 2);
        final width = size.width - 40;
        // Canvas: the arrow's centre is 20 pt right of the hole's centre on every board.
        final arrowX = (hole.center.dx + 20 - 20).clamp(24.0, width - 24);
        final bubble = _CoachBubble(
          key: ValueKey(run.steps[run.position]),
          run: run,
          width: width,
          arrowX: arrowX,
          arrowUp: step.below,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(painter: _DimPainter(hole, radius)),
              ),
            ),
            if (step.below)
              Positioned(left: 20, width: width, top: hole.bottom + step.gap, child: _fade(bubble))
            else
              Positioned(left: 20, width: width, bottom: size.height - (hole.top - step.gap), child: _fade(bubble)),
          ],
        );
      },
    );
  }

  Widget _fade(Widget child) =>
      AnimatedSwitcher(duration: Motion.base, switchInCurve: Motion.out, switchOutCurve: Motion.out, child: child);
}

/// Everything but the hole, and the ring (CSS `outline: 2px; outline-offset: 4px` follows the radius: 4…6 pt out).
class _DimPainter extends CustomPainter {
  _DimPainter(this.hole, this.radius);
  final Rect hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    canvas.drawPath(dim, Paint()..color = CoachColors.dim);
    if (hole.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole.inflate(5), Radius.circular(radius + 5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = CoachColors.ring,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole || old.radius != radius;
}

/// Canvas bubble: 350 wide, padding 16 16 14, radius 18, #f6f3ec, shadow `0 20px 50px` black 60 %; the arrow — a
/// 14 pt square turned 45° on the edge. Title 17 semibold, text 14 / 1.45 (6 below the title), footer 14 below:
/// «1 из 3» 13, «Пропустить» underlined (14 apart, padding 8), the dark 38 pt button.
class _CoachBubble extends StatelessWidget {
  const _CoachBubble({super.key, required this.run, required this.width, required this.arrowX, required this.arrowUp});
  final CoachRun run;
  final double width;
  final double arrowX;
  final bool arrowUp;

  @override
  Widget build(BuildContext context) {
    final step = run.step;
    final center = CoachCenter.instance;
    final multi = run.steps.length > 1;
    const spacing = 14 * 1.45 - 14 * interLineHeight;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwiftText(step.title, style: Typo.inter(17, TypoWeight.semibold, CoachColors.ink)),
        // − 1: SkParagraph sets the first line of a line-spaced paragraph 1 pt lower than WebKit / SwiftUI (measured).
        const SizedBox(height: 6 + spacing / 2 - 1),
        Text(
          step.text,
          textHeightBehavior: swiftLineSpacing,
          style: lineSpaced(Typo.inter(14, TypoWeight.regular, CoachColors.text), spacing),
        ),
        const SizedBox(height: spacing / 2 + 1 + 14),
        SizedBox(
          height: 38,
          child: Row(
            children: [
              if (multi) ...[
                Text(
                  '${run.position + 1} из ${run.steps.length}',
                  style: Typo.inter(13, TypoWeight.regular, CoachColors.counter),
                ),
                const SizedBox(width: 14),
                TouchArea(
                  // CSS `padding: 12px 8px; margin: -12px 0`: a taller touch target without changing the layout.
                  child: Pressable(
                    scale: 1,
                    onTap: center.finish,
                    label: 'Пропустить',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      child: Text(
                        'Пропустить',
                        style: Typo.inter(
                          13,
                          TypoWeight.regular,
                          CoachColors.text,
                        ).copyWith(decoration: TextDecoration.underline, decorationColor: CoachColors.text),
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Pressable(
                onTap: run.isLast ? center.finish : center.next,
                child: ShapeBox(
                  shape: const SwiftShape.rounded(1000),
                  fills: const [SwiftFill(CoachColors.ink)],
                  child: SizedBox(
                    height: 38,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          run.isLast ? 'Понятно' : 'Дальше',
                          style: Typo.inter(14, TypoWeight.semibold, TruverColors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ShapeBox(
          shape: const SwiftShape.rounded(18),
          shadows: [SwiftShadow(TruverColors.black(0.6), 25, y: 20)],
          fills: const [SwiftFill(CoachColors.bubble)],
          child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 14), child: body),
        ),
        Positioned(
          left: arrowX - 7,
          top: arrowUp ? -7 : null,
          bottom: arrowUp ? null : -7,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: const SizedBox(width: 14, height: 14, child: ColoredBox(color: CoachColors.bubble)),
          ),
        ),
      ],
    );
  }
}

extension NeckSpotPair on NeckSpot {
  (int, int) get pair => (course, fret);
}

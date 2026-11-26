/// Port of Truver/Sources/Features/Metronome/MetronomeScreen.swift
///
/// Metronome by the canvas («Метроном — остановлен / играет / …», 390 × 844). Vertical rhythm under the header
/// (header top 50): beats 108 (+14), status line 162 (+10, 18), chips 186 (+6, 36), knob 222 (290), controls 532
/// (+20, 88), Tap 634 (+14, 60); toasts and the interruption banner at 702 / 698.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/landscape.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../root/root_view.dart' show isAccessibilityTextSize;
import 'metronome_controller.dart';
import 'play_check_views.dart';
import 'rhythm_library.dart';
import 'rhythm_views.dart';
import 'tempo_knob.dart';
import '../tour/coach_marks.dart';

class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key, this.landscape = false});

  /// Canvas «Метроном — альбом» (844 × 390).
  final bool landscape;

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> {
  int? _accentMenuBeat;
  OverlayEntry? _sessionAlert;

  /// «Занятие закончено» covers the whole app (the tab bar too), like the iOS full-screen cover.
  void _syncSessionAlert(AppModel app) {
    final end = app.metronome.sessionEnd;
    if (end == null) {
      _sessionAlert?.remove();
      _sessionAlert = null;
      return;
    }
    if (_sessionAlert != null) return;
    final entry = OverlayEntry(
      builder: (_) => DesignAlert(
        title: 'Занятие закончено',
        message: app.metronome.sessionEnd?.message ?? end.message,
        actions: [
          DesignAlertAction('Ещё 5 мин', () => app.metronome.extendSession()),
          DesignAlertAction('Готово', app.metronome.dismissSessionEnd, role: DesignAlertRole.preferred),
        ],
        dismiss: app.metronome.dismissSessionEnd,
      ),
    );
    _sessionAlert = entry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sessionAlert != entry) return;
      Overlay.of(context, rootOverlay: true).insert(entry);
    });
  }

  @override
  void dispose() {
    _sessionAlert?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.metronome, app.playCheck]),
      builder: (context, _) {
        _syncSessionAlert(app);
        final Widget body;
        if (widget.landscape) {
          body = _landscapeBody(app);
        } else if (isAccessibilityTextSize(context)) {
          body = _largeText(app);
        } else {
          body = _regular(app);
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: body),
            _fullScreenFlash(context, app),
          ],
        );
      },
    );
  }

  MetronomeController _m(AppModel app) => app.metronome;

  // MARK: Regular layout

  Widget _regular(AppModel app) {
    final m = _m(app);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Column(
              children: [
                ScreenHeader(title: 'Метроном', trailing: [_presetChip(app)]),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // Fixed blocks are 310 pt + the knob; the knob gives way on short screens.
                      final knob = math.min(290.0, math.max(200.0, box.maxHeight - 310 - 8));
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          maxHeight: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 14),
                              _beatStrip(app),
                              const SizedBox(height: 10),
                              _statusLine(m),
                              const SizedBox(height: 6),
                              CoachAnchor(id: CoachAnchors.chips, child: _chipsRow(app)),
                              CoachAnchor(id: CoachAnchors.knob, child: _knob(app, knob)),
                              const SizedBox(height: 20),
                              _controls(m, minus: 64, play: 88, icon: 24, playIcon: 30),
                              const SizedBox(height: 14),
                              if (app.playCheck.isOn)
                                const PlayCheckPanel(height: 60)
                              else
                                _tapButton(m, height: 60, radius: 18, font: Typo.inter(15, TypoWeight.medium)),
                              // Canvas «Прервано звонком»: the banner (698) lies over the tab bar — the root draws it.
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned.fill(child: _accentMenu(app, below: 108, width: constraints.maxWidth, landscape: false)),
            // Canvas «Цель достигнута»: the toast sits at 702, under Tap.
            Positioned(left: 0, right: 0, top: 655, child: _toast(m)),
          ],
        );
      },
    );
  }

  Widget _presetChip(AppModel app) {
    final name = _m(app).state.currentPreset?.name;
    return Pressable(
      onTap: () => app.sheet = const AppSheet('metroPresets'),
      label: 'Пресет: ${name ?? 'нет'}',
      child: HeaderChip(text: name ?? 'Пресеты', icon: AppIcon.chevronDown, iconSize: 12),
    );
  }

  Widget _knob(AppModel app, double size, {String? caption}) {
    final m = _m(app);
    return TempoKnob(
      bpm: m.displayBPM,
      size: size,
      caption: caption ?? 'BPM · свайп по ручке',
      dimmed: m.isPlaying && m.silentBar,
      onDrag: m.step,
      onDoubleTap: m.toggle,
      onLongPress: () => app.sheet = const AppSheet('metroModes'),
    );
  }

  // MARK: Landscape (canvas «Метроном — альбом», 844 × 390)

  /// Title 20 at (60, 20); the knob 290 × 0.98 at (70, 54); on the right from x 400, 384 wide, from top 36 and 16
  /// apart: beats (44), the status line, − / play / + (60 / 84), Tap 52.
  Widget _landscapeBody(AppModel app) {
    final m = _m(app);
    final status = m.statusText;
    return LandscapeCanvas(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Board(
            x: 60,
            y: 20,
            width: 300,
            child: Semantics(header: true, child: Text('Метроном', style: Typo.inter(20, TypoWeight.semibold, TruverColors.textPrimary))),
          ),
          Positioned(
            left: 70,
            top: 54,
            child: Transform.scale(
              scale: 0.98,
              alignment: Alignment.topLeft,
              child: _knob(app, 290, caption: 'BPM'),
            ),
          ),
          Board(
            x: 400,
            y: 36,
            width: 384,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _beatStrip(app, stripWidth: 384, stripLeft: 400),
                if (status != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    status,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 16),
                _controls(m, minus: 60, play: 84, icon: 22, playIcon: 28),
                const SizedBox(height: 16),
                _tapButton(m, height: 52, radius: 16, font: Typo.inter(15)),
              ],
            ),
          ),
          Positioned.fill(child: _accentMenu(app, below: 80, width: 844, landscape: true)),
          Positioned(left: 0, right: 0, top: 20, child: _toast(m)),
        ],
      ),
    );
  }

  // MARK: Beat strip (34 × 44 buttons; bars 28 strong, 18 normal; groups 14 apart, beats 5)

  List<List<int>> _groups(Map<String, dynamic> m) {
    final g = m.grouping;
    final sizes = (g != null && g.fold<int>(0, (a, b) => a + b) == m.numerator) ? g : [m.numerator];
    final result = <List<int>>[];
    var index = 0;
    for (final size in sizes) {
      result.add([for (var i = index; i < index + size; i++) i]);
      index += size;
    }
    return result;
  }

  double _barWidth(Map<String, dynamic> m, double width) {
    final groups = _groups(m);
    final n = m.numerator;
    final gaps = (groups.length - 1) * 14 + (n - groups.length) * 5;
    return math.min(34, (width - gaps) / math.max(1, n));
  }

  /// Centre x of each beat in the screen's coordinates (`beatCenters` of the «metronome» space).
  List<double> _beatCenters(Map<String, dynamic> m, double stripLeft, double stripWidth) {
    final groups = _groups(m);
    final w = _barWidth(m, stripWidth);
    final gaps = (groups.length - 1) * 14 + (m.numerator - groups.length) * 5;
    var x = stripLeft + (stripWidth - (w * m.numerator + gaps)) / 2;
    final centers = <double>[];
    for (var gi = 0; gi < groups.length; gi++) {
      if (gi > 0) x += 14;
      for (var bi = 0; bi < groups[gi].length; bi++) {
        if (bi > 0) x += 5;
        centers.add(x + w / 2);
        x += w;
      }
    }
    return centers;
  }

  double _stripWidth = 350, _stripLeft = 20;

  Widget _beatStrip(AppModel app, {double? stripWidth, double stripLeft = 20}) {
    final m = _m(app);
    final meter = m.meter;
    return Semantics(
      container: true,
      label: 'Доли ${meter.numerator}/${meter.denominator}',
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => app.sheet = const AppSheet('metroMeter'),
        child: SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (context, box) {
              final width = stripWidth ?? box.maxWidth;
              _stripWidth = width;
              _stripLeft = stripLeft;
              final w = _barWidth(meter, width);
              final groups = _groups(meter);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var gi = 0; gi < groups.length; gi++) ...[
                    if (gi > 0) const SizedBox(width: 14),
                    for (var bi = 0; bi < groups[gi].length; bi++) ...[
                      if (bi > 0) const SizedBox(width: 5),
                      _beatBar(app, groups[gi][bi], w),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static double barHeight(int level) => switch (level) {
    Accent.strong => 28,
    Accent.normal => 18,
    Accent.soft => 11,
    _ => 4,
  };

  static Color barFill(int level) => switch (level) {
    Accent.strong => TruverColors.beat.withValues(alpha: 0.38),
    Accent.normal => TruverColors.white(0.16),
    Accent.soft => TruverColors.white(0.11),
    _ => TruverColors.white(0.06),
  };

  Widget _beatBar(AppModel app, int beat, double width) {
    final m = _m(app);
    final accents = m.meter.accents;
    final level = beat < accents.length ? accents[beat] : Accent.normal;
    final silent = m.isPlaying && m.silentBar;
    final lit = m.litBeat == beat;
    final own = m.beatRhythm(beat);
    // A tap only opens the level menu: changing the accent at once broke the strong beat on every attempt
    // to reach the meter (iPhone UX check).
    return Semantics(
      button: true,
      label: 'Доля ${beat + 1}, ${accentName(level)}${own != null ? ', ${own.spokenName}' : ''}',
      hint: 'Тап — выбрать уровень',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showAccentMenu(beat),
        child: SizedBox(
          width: width,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: barHeight(level)),
                duration: Motion.quick,
                curve: Motion.out,
                builder: (context, h, _) => SizedBox(
                  width: width,
                  height: h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ShapeBox(shape: const SwiftShape.rounded(3), fills: [SwiftFill(silent ? TruverColors.white(0.06) : barFill(level))]),
                      AnimatedOpacity(
                        opacity: lit ? 1 : 0,
                        duration: lit ? Duration.zero : const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: ShapeBox(
                          shape: const SwiftShape.rounded(3),
                          shadows: [
                            SwiftShadow(TruverColors.beat.withValues(alpha: 0.9), 6),
                            SwiftShadow(TruverColors.beat.withValues(alpha: 0.45), 3),
                          ],
                          fills: const [SwiftFill(TruverColors.beat)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (own != null)
                Positioned(
                  top: -6,
                  left: (width - math.max(18, width + 4)) / 2,
                  width: math.max(18, width + 4),
                  height: 20,
                  child: RhythmGlyph(rhythm: own, color: TruverColors.textSecondary, denominator: m.meter.denominator),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String accentName(int level) => switch (level) {
    Accent.strong => 'сильная',
    Accent.normal => 'обычная',
    Accent.soft => 'тихая',
    _ => 'выключена',
  };

  // The menu stays until a choice or a tap outside (6 rows did not fit in 2.5 s — UX check).
  void _showAccentMenu(int beat) => setState(() => _accentMenuBeat = beat);

  void _hideAccentMenu() => setState(() => _accentMenuBeat = null);

  /// «Доля 3 · тап меняет по кругу»: 232 pt menu under the beat with an arrow (canvas «уровень доли»).
  /// `below`: bottom of the beat strip in the screen's space (the arrow sits 6 pt under it).
  Widget _accentMenu(AppModel app, {required double below, required double width, required bool landscape}) {
    final beat = _accentMenuBeat;
    final m = _m(app);
    Widget child = const SizedBox.shrink(key: ValueKey('none'));
    if (beat != null && beat < m.meter.numerator) {
      final centers = _beatCenters(m.meter, _stripLeft, _stripWidth);
      final x = centers[beat];
      final left = math.min(math.max(16.0, x - 116), width - 248);
      // Landscape: the menu would run off the bottom — it opens beside the beat instead.
      final menuTop = landscape ? math.max(8.0, below - 140) : below + 14;
      const menuFill = Color(0xFA282A2F);
      final accents = m.meter.accents;
      child = Stack(
        key: ValueKey('menu$beat'),
        children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _hideAccentMenu),
          ),
          if (!landscape)
            Positioned(
              left: x - 8,
              top: below + 6,
              width: 16,
              height: 16,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: const ColoredBox(color: menuFill),
              ),
            ),
          Positioned(
            left: left,
            top: menuTop,
            width: 232,
            child: ShapeBox(
              shape: const SwiftShape.rounded(14, continuous: true),
              shadows: [SwiftShadow(TruverColors.black(0.7), 25, y: 20)],
              fills: const [SwiftFill(menuFill)],
              clip: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text('Доля ${beat + 1} · уровень', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                  ),
                  // Soundbrenner-style: this beat's own note value.
                  Pressable(
                    scale: 1,
                    onTap: () {
                      _hideAccentMenu();
                      app.sheet = AppSheet('metroRhythmBeat', beat);
                    },
                    child: SizedBox(
                      height: 42,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 26,
                              height: 18,
                              child: RhythmGlyph(
                                rhythm: m.meter.rhythmForBeat(beat) != null
                                    ? RhythmLibrary.describe(m.meter.rhythmForBeat(beat)!)
                                    : m.currentRhythm,
                                denominator: m.meter.denominator,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('Ритм доли', maxLines: 1, style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)),
                            const Spacer(),
                            const AppIconView(AppIcon.chevronRight, size: 14, color: TruverColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ColoredBox(color: TruverColors.white(0.08), child: const SizedBox(height: 1)),
                  for (final level in const [Accent.strong, Accent.normal, Accent.soft, Accent.off])
                    Pressable(
                      scale: 1,
                      onTap: () {
                        m.setAccent(beat, level);
                        _hideAccentMenu();
                      },
                      child: SizedBox(
                        height: 42,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: swatchHeight(level),
                                    child: ShapeBox(shape: const SwiftShape.rounded(2), fills: [SwiftFill(swatch(level))]),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(menuName(level), style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)),
                              const Spacer(),
                              if (beat < accents.length && accents[beat] == level)
                                const AppIconView(AppIcon.check, size: 16, lineWidth: 2, color: TruverColors.textPrimary),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return AnimatedSwitcher(
      duration: Motion.quick,
      switchInCurve: Motion.out,
      switchOutCurve: Motion.out,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: child,
    );
  }

  static String menuName(int level) => switch (level) {
    Accent.strong => 'Сильная',
    Accent.normal => 'Обычная',
    Accent.soft => 'Тихая',
    _ => 'Выключена',
  };

  static Color swatch(int level) => switch (level) {
    Accent.strong => TruverColors.beat.withValues(alpha: 0.7),
    Accent.normal => TruverColors.white(0.35),
    Accent.soft => TruverColors.white(0.25),
    _ => TruverColors.white(0.15),
  };

  static double swatchHeight(int level) => switch (level) {
    Accent.strong => 18,
    Accent.normal => 12,
    Accent.soft => 7,
    _ => 3,
  };

  // MARK: Status and chips

  Widget _statusLine(MetronomeController m) => Semantics(
    excludeSemantics: m.statusText == null,
    child: SizedBox(
      height: 18,
      width: double.infinity,
      // Canvas: the line sits at the top of its 18 pt box (CSS `min-height`), not centred in it.
      child: Align(
        alignment: Alignment.topCenter,
        child: Text(
          m.statusText ?? ' ',
          textAlign: TextAlign.center,
          style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary),
        ),
      ),
    ),
  );

  /// Fits in one line when it can, otherwise scrolls sideways.
  Widget _chipsRow(AppModel app) => SizedBox(
    height: 36,
    width: double.infinity,
    child: LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: math.max(0, box.maxWidth - 4)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: _chipsLine(app)),
          ),
        ),
      ),
    ),
  );

  List<Widget> _chipsLine(AppModel app) {
    final m = _m(app);
    final mode = m.modeChip;
    final items = <Widget>[
      // Note value, one tap to the grid of values and figures (user: «как в Soundbrenner»).
      const RhythmChip(),
      // Stage SM: «Проверка игры» — the microphone grades the playing.
      Pressable(
        onTap: () => app.sheet = const AppSheet('playCheck'),
        label: 'Проверка игры',
        child: Chip(
          text: 'Проверка',
          icon: AppIcon.mic,
          style: app.playCheck.isOn ? ChipStyle.emphasized : ChipStyle.plain,
          size: ChipSize.large,
        ),
      ),
      // The meter is always visible and opens «Размер и деление».
      Pressable(
        onTap: () => app.sheet = const AppSheet('metroMeter'),
        label:
            'Размер ${m.meter.numerator}/${m.meter.denominator}'
            '${(m.meter.grouping?.length ?? 0) > 1 ? ', группы ${m.meter.grouping!.join('+')}' : ''}',
        child: Chip(text: '${m.meter.numerator}/${m.meter.denominator}', size: ChipSize.large),
      ),
      Pressable(
        onTap: () => app.sheet = const AppSheet('metroModes'),
        label: mode.kind == ChipKind.mode ? 'Режим: ${mode.text.toLowerCase()}' : 'Режимы',
        child: Chip(
          text: mode.text,
          icon: mode.kind == ChipKind.mode && const [ModeChoice.speedUp, ModeChoice.twoForward].contains(m.modeChoice)
              ? AppIcon.arrowUp
              : null,
          style: mode.kind == ChipKind.mode ? ChipStyle.emphasized : ChipStyle.plain,
          size: ChipSize.large,
        ),
      ),
      for (final chip in m.chips)
        Pressable(
          enabled: chip.action != null,
          onTap: chip.action == null
              ? null
              : () => app.sheet = AppSheet(switch (chip.action!) {
                  ChipAction.modes => 'metroModes',
                  ChipAction.timer => 'metroTimer',
                  ChipAction.meter => 'metroMeter',
                }),
          child: Chip(text: chip.text, icon: chipIcon(chip.kind), style: chipStyle(chip.kind), size: ChipSize.large),
        ),
    ];
    return [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 8), items[i]],
    ];
  }

  static AppIcon? chipIcon(ChipKind kind) => switch (kind) {
    ChipKind.plain => null,
    ChipKind.mode => AppIcon.arrowUp,
    ChipKind.target => AppIcon.check,
    ChipKind.timer => AppIcon.timer,
    ChipKind.warning => AppIcon.warning,
  };

  static ChipStyle chipStyle(ChipKind kind) => switch (kind) {
    ChipKind.plain || ChipKind.timer => ChipStyle.plain,
    ChipKind.mode => ChipStyle.emphasized,
    ChipKind.target => ChipStyle.positive,
    ChipKind.warning => ChipStyle.muted,
  };

  // MARK: Controls

  Widget _limitButton(AppIcon icon, double size, double iconSize, String label, bool atLimit, VoidCallback onTap) => Stack(
    alignment: Alignment.center,
    children: [
      RoundIconButton(icon: icon, size: size, iconSize: iconSize, label: label, onTap: onTap, enabled: !atLimit),
      if (atLimit)
        IgnorePointer(
          child: SizedBox(
            width: size,
            height: size,
            child: ShapeBox(shape: SwiftShape.circle, fills: [SwiftFill(TruverColors.background.withValues(alpha: 0.6))]),
          ),
        ),
    ],
  );

  Widget _controls(MetronomeController m, {required double minus, required double play, required double icon, required double playIcon}) =>
      Row(
        children: [
          _limitButton(AppIcon.minus, minus, icon, 'Медленнее на 1', m.atMinimum, () => m.step(-1)),
          const Spacer(),
          PrimaryRoundButton(
            icon: m.isPlaying ? AppIcon.stop : AppIcon.play,
            size: play,
            iconSize: playIcon,
            label: m.isPlaying ? 'Стоп' : 'Старт',
            onTap: m.toggle,
          ),
          const Spacer(),
          _limitButton(AppIcon.plus, minus, icon, 'Быстрее на 1', m.atMaximum, () => m.step(1)),
        ],
      );

  Widget _tapButton(MetronomeController m, {required double height, required double radius, required TextStyle font}) => Pressable(
    onTap: m.tapTempo,
    label: 'Tap tempo — стучите в ритм',
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: ShapeBox(
        shape: SwiftShape.rounded(radius),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Center(
          child: Text('Tap — стучите в ритм', style: font.copyWith(color: TruverColors.textBody)),
        ),
      ),
    ),
  );

  Widget _interruptionBanner(MetronomeController m) => metronomeInterruptionBanner(m);

  /// Canvas toast (radius 16, 13 medium); a reached target is green — icon and text.
  Widget _toast(MetronomeController m) {
    final toast = m.toast;
    final check = toast?.icon == AppIcon.check;
    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.out,
      switchOutCurve: Motion.out,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: toast == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Center(
              key: ValueKey(toast.text),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ShapeBox(
                  shape: const SwiftShape.rounded(16),
                  shadows: [SwiftShadow(TruverColors.black(0.6), 15, y: 14)],
                  fills: const [SwiftFill(Color(0xF526282D))],
                  strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                  child: Padding(
                    // padding 11 × 16 inside a 1 pt CSS border (the stroke is drawn inside here).
                    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIconView(
                          toast.icon,
                          size: 16,
                          lineWidth: check ? 2 : 1.6,
                          color: check ? TruverColors.inTune : TruverColors.beat,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            toast.text,
                            style: Typo.inter(13, TypoWeight.medium, check ? TruverColors.inTune : TruverColors.textBody),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _fullScreenFlash(BuildContext context, AppModel app) {
    final m = _m(app);
    if (m.state.flash != FlashTarget.screen) return const SizedBox.shrink();
    // `.ignoresSafeArea()`: up under the status bar too.
    final view = View.of(context);
    final top = widget.landscape ? 0.0 : view.padding.top / view.devicePixelRatio;
    return Positioned(
      left: 0,
      right: 0,
      top: -top,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: m.flashOn ? 1 : 0,
          duration: m.flashOn ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: ColoredBox(color: TruverColors.beat.withValues(alpha: 0.16)),
        ),
      ),
    );
  }

  // MARK: Large text (canvas «Метроном — крупный шрифт»: the knob gives way to the number and buttons)

  /// Title 34 bold (top 50), «Риф 7/8 · Разгон» 20 (116), the tempo 120 light (180) with «BPM» 22, − / play / +
  /// 80 / 100 (380), Tap 76 (510), the note 15 (606). Sizes are fixed: the layout already is the large one.
  Widget _largeText(AppModel app) {
    final m = _m(app);
    final mode = m.modeChip;
    final subtitle = [
      m.state.currentPreset?.name ?? '${m.meter.numerator}/${m.meter.denominator}',
      if (mode.kind == ChipKind.mode) mode.text,
    ].join(' · ');
    Widget line(
      String text,
      double size,
      double height,
      Color color, {
      TypoWeight weight = TypoWeight.regular,
      Alignment alignment = Alignment.centerLeft,
    }) => SizedBox(
      height: height,
      child: OverflowBox(
        alignment: alignment,
        maxHeight: double.infinity,
        child: Text(text, textScaler: TextScaler.noScaling, style: Typo.fixed(size, weight, color)),
      ),
    );
    return MediaQuery.withNoTextScaling(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Semantics(header: true, child: line('Метроном', 34, 41.2, TruverColors.textPrimary, weight: TypoWeight.bold)),
            const SizedBox(height: 24.8),
            line(subtitle, 20, 24.2, TruverColors.textSecondary),
            const SizedBox(height: 39.8),
            line('${m.displayBPM.toInt()}', 120, 120, TruverColors.textPrimary, weight: TypoWeight.light, alignment: Alignment.center),
            line('BPM', 22, 26.6, TruverColors.textSecondary, alignment: Alignment.center),
            const SizedBox(height: 53.4),
            _controls(m, minus: 80, play: 100, icon: 30, playIcon: 36),
            const SizedBox(height: 30),
            _tapButton(m, height: 76, radius: 20, font: Typo.fixed(22)),
            SizedBox(height: m.interrupted ? 20 : 21.43),
            if (m.interrupted)
              _interruptionBanner(m)
            else
              SizedBox(
                width: double.infinity,
                child: Text(
                  'Ручка заменена числом и кнопками: при крупном шрифте их легче нажать',
                  textAlign: TextAlign.center,
                  textHeightBehavior: swiftLineSpacing,
                  style: lineSpaced(Typo.fixed(15, TypoWeight.regular, TruverColors.textTertiary), 21 - 18.15),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «Остановлено звонком. Продолжить с 150 BPM, такт 12» + «Продолжить» (canvas: radius 14, orange tint). The root
/// draws it above the tab bar in portrait (canvas «Прервано звонком», y 698).
Widget metronomeInterruptionBanner(MetronomeController m) => ShapeBox(
  shape: const SwiftShape.rounded(14),
  fills: [SwiftFill(TruverColors.sharp.withValues(alpha: 0.1))],
  strokes: [SwiftStroke(TruverColors.sharp.withValues(alpha: 0.35), inside: true)],
  child: Padding(
    padding: const EdgeInsets.only(left: 15, right: 13, top: 11, bottom: 11), // padding 10 12 10 14 + the 1 pt border
    child: Row(
      children: [
        const AppIconView(AppIcon.warning, size: 18, color: TruverColors.sharp),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 0.91), // the half-leading of line-height 1.35
            child: Text(
              m.interruptionText,
              textHeightBehavior: swiftLineSpacing,
              style: lineSpaced(Typo.inter(13, TypoWeight.regular, TruverColors.textBody), 17.55 - 15.73),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: () => m.start(),
          child: SizedBox(
            height: 36,
            child: ShapeBox(
              shape: SwiftShape.capsule,
              fills: const [SwiftFill.gradient(TruverGradients.primaryFill)],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  widthFactor: 1,
                  child: Text('Продолжить', style: Typo.inter(15, TypoWeight.semibold, TruverColors.background)),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  ),
);

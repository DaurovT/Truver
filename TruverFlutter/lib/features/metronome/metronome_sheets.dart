/// Port of Truver/Sources/Features/Metronome/MetronomeSheets.swift
///
/// Metronome sheets of the canvas. Heights are 844 − the panel's top on the canvas. Overlays of a `DesignSheet`
/// (text-field alerts, the modes toast) lie over the panel only, as in SwiftUI; system alerts cover the screen.
library;

import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'metronome_controller.dart';
import 'rhythm_library.dart';

TextStyle get _captionTertiary => Typo.caption.copyWith(color: TruverColors.textTertiary);

/// Column with SwiftUI `VStack(spacing:)` gaps.
List<Widget> _spaced(double spacing, List<Widget> children) => [
  for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: spacing), children[i]],
];

/// A system alert over the whole screen (SwiftUI `.alert`), shown while `alert` is not null.
class _ScreenAlert extends StatefulWidget {
  const _ScreenAlert({required this.alert, required this.child});
  final Widget? alert;
  final Widget child;

  @override
  State<_ScreenAlert> createState() => _ScreenAlertState();
}

class _ScreenAlertState extends State<_ScreenAlert> {
  final _controller = OverlayPortalController();

  void _sync() {
    if (widget.alert != null && !_controller.isShowing) _controller.show();
    if (widget.alert == null && _controller.isShowing) _controller.hide();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
    return OverlayPortal(controller: _controller, overlayChildBuilder: (_) => widget.alert ?? const SizedBox.shrink(), child: widget.child);
  }
}

/// Canvas card of the metronome sheets (`Card` already keeps its rows inside the 1 pt border, as CSS does; the
/// rows' own border-bottom comes from [MetroRow]).
class MetroCard extends StatelessWidget {
  const MetroCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(children: children);
}

/// A canvas row (`display: flex; align-items: center; justify-content: space-between; padding: 0 16px; gap: 10px`):
/// title 15 body (one line), subtitle 12 tertiary 2 below, trailing 14 secondary; `minHeight` is the canvas
/// `min-height`, the divider adds its 1 pt below it.
class MetroRow extends StatelessWidget {
  const MetroRow({super.key, required this.title, this.subtitle, this.showsDivider = true, this.trailing, this.minHeight = 56});
  final String title;
  final String? subtitle;
  final bool showsDivider;
  final Widget? trailing;
  final double minHeight;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border: showsDivider ? Border(bottom: BorderSide(color: TruverColors.white(0.06))) : null,
    ),
    child: Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: showsDivider ? 1 : 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwiftText(title, maxLines: 1, softWrap: false, style: Typo.row.copyWith(color: TruverColors.textBody)),
                  if (subtitle != null) ...[const SizedBox(height: 2), SwiftText(subtitle!, maxLines: 2, style: _captionTertiary)],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              DefaultTextStyle.merge(style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary), child: trailing!),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A text-field alert over the sheet panel (SwiftUI `.overlay { TextFieldAlert(...) }`).
Widget _withPanelOverlay(Widget sheet, Widget? overlay) => Stack(
  children: [
    sheet,
    if (overlay != null) Positioned.fill(child: overlay),
  ],
);

// MARK: «Размер и деление» (canvas top 96): beats per bar and the beat value, groups as chips, the subdivision
// «Нет 2 3 4», a preview of the strip. Swing and the second track moved to «Ритм» (♫) — the canvas sheet has none.

class MeterSheet extends StatelessWidget {
  const MeterSheet({super.key});

  /// Groupings of 2s and 3s: ascending first (2+2+3), then descending (3+2+2), then the rest; at most three, plus
  /// the current one if it is another.
  static List<List<int>> groupings(int n, List<int>? current) {
    final all = <List<int>>[];
    void build(int left, List<int> prefix) {
      if (left == 0) {
        if (prefix.length > 1) all.add(prefix);
        return;
      }
      for (final part in const [2, 3]) {
        if (part <= left) build(left - part, [...prefix, part]);
      }
    }

    if (n <= 12) build(n, []);
    bool same(List<int> a, List<int> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
    final result = <List<int>>[];
    if (all.isNotEmpty) {
      final fewest = all.map((g) => g.length).reduce(math.min);
      final asc = [...all.firstWhere((g) => g.length == fewest)]..sort();
      result.add(asc);
      final desc = asc.reversed.toList();
      if (!same(desc, asc)) result.add(desc);
      final sorted = [...all]..sort((a, b) => a.length.compareTo(b.length));
      for (final g in sorted) {
        if (result.length < 3 && !result.any((r) => same(r, g))) result.add(g);
      }
    }
    if (current != null && current.length > 1 && !result.any((r) => same(r, current))) result.add(current);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final m = metronome.meter;
    final grouping = m.grouping;
    final sum = grouping?.fold<int>(0, (a, b) => a + b);
    final error = grouping != null && grouping.length > 1 && sum != m.numerator ? 'Сумма групп $sum, а долей ${m.numerator}' : null;
    final rhythm = m.rhythm == null ? null : RhythmLibrary.describe(m.rhythm!);
    bool same(List<int>? a, List<int> b) => a != null && a.join('+') == b.join('+');
    void setGrouping(List<int>? g) => metronome.updateMeter((x) {
      x.put('grouping', g);
      x['accents'] = metronome.defaultAccents(x.numerator, g);
    });
    void setNumerator(int value) => metronome.updateMeter((x) {
      x['numerator'] = value;
      final g = x.grouping;
      if (g != null && g.fold<int>(0, (a, b) => a + b) != value) x.put('grouping', null);
      x['accents'] = metronome.defaultAccents(value, x.grouping);
    });
    return DesignSheet(
      title: 'Размер и деление',
      height: 748,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: SheetButton(title: 'Готово', onTap: () => app.sheet = null),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(14, [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionCaption(text: 'Размер'),
              MetroCard(
                children: [
                  MetroRow(
                    title: 'Долей в такте',
                    minHeight: 60,
                    trailing: ValueStepper(
                      value: '${m.numerator}',
                      canDecrement: m.numerator > 1,
                      canIncrement: m.numerator < 16,
                      decrement: () => setNumerator(m.numerator - 1),
                      increment: () => setNumerator(m.numerator + 1),
                    ),
                  ),
                  MetroRow(
                    title: 'Длительность доли',
                    minHeight: 60,
                    trailing: SizedBox(
                      width: 150,
                      child: Segments<int>(
                        options: const [(4, '♩ 4'), (8, '♪ 8'), (16, '♬ 16')],
                        selection: m.denominator,
                        size: SegmentsSize.compact,
                        onChanged: (v) => metronome.updateMeter((x) => x['denominator'] = v),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionCaption(text: 'Группы'),
              MetroCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FlowLayout(
                          spacing: 6,
                          children: [
                            for (final g in groupings(m.numerator, grouping))
                              Pressable(
                                onTap: () => setGrouping(g),
                                child: Chip(text: g.join('+'), style: same(grouping, g) ? ChipStyle.emphasized : ChipStyle.plain),
                              ),
                            Pressable(
                              onTap: () => setGrouping(null),
                              child: Chip(text: 'Без групп', style: (grouping?.length ?? 0) < 2 ? ChipStyle.emphasized : ChipStyle.plain),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SwiftText(
                          error ?? 'Сильные доли — с акцентом. Удобно для 7/8, 5/8, 9/8',
                          maxLines: 1,
                          softWrap: false, // one line, as on the canvas
                          style: Typo.caption.copyWith(color: error == null ? TruverColors.textTertiary : TruverColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionCaption(text: 'Деление доли · щелчок между долями'),
              MetroCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(6),
                    // ME-3 1–9 and figures live in «Ритм» (♫); here the canvas offers none / 2 / 3 / 4.
                    child: Segments<int>(
                      options: const [(1, 'Нет'), (2, '2'), (3, '3'), (4, '4')],
                      selection: rhythm == null || rhythm.isPlain ? m.subdivision : 0,
                      size: SegmentsSize.compact,
                      onChanged: (v) => metronome.updateMeter((x) {
                        x['subdivision'] = v;
                        x.remove('rhythm');
                        if (v % 2 != 0) x['swing'] = 0.5;
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: BeatStripPreview()),
        ]),
      ),
    );
  }
}

/// The beat strip under «Размер и деление» (same bars as the screen, the lit beat included).
class BeatStripPreview extends StatelessWidget {
  const BeatStripPreview({super.key});

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

  @override
  Widget build(BuildContext context) {
    final metronome = AppScope.of(context).metronome;
    final m = metronome.meter;
    final g = m.grouping;
    final sizes = g != null && g.fold<int>(0, (a, b) => a + b) == m.numerator ? g : [m.numerator];
    final accents = m.accents;
    return ExcludeSemantics(
      child: SizedBox(
        height: 44,
        child: LayoutBuilder(
          builder: (context, box) {
            final gaps = (sizes.length - 1) * 14 + (m.numerator - sizes.length) * 5;
            final w = math.min(34.0, (box.maxWidth - gaps) / math.max(1, m.numerator));
            var beat = 0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var gi = 0; gi < sizes.length; gi++) ...[
                  if (gi > 0) const SizedBox(width: 14),
                  for (var bi = 0; bi < sizes[gi]; bi++) ...[
                    if (bi > 0) const SizedBox(width: 5),
                    Builder(
                      builder: (_) {
                        final b = beat++;
                        final level = b < accents.length ? accents[b] : Accent.normal;
                        return SizedBox(
                          width: w,
                          height: barHeight(level),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ShapeBox(shape: const SwiftShape.rounded(3), fills: [SwiftFill(barFill(level))]),
                              if (metronome.litBeat == b)
                                ShapeBox(
                                  shape: const SwiftShape.rounded(3),
                                  shadows: [
                                    SwiftShadow(TruverColors.beat.withValues(alpha: 0.9), 6),
                                    SwiftShadow(TruverColors.beat.withValues(alpha: 0.45), 3),
                                  ],
                                  fills: const [SwiftFill(TruverColors.beat)],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Swing (ME-3) for «Ритм»: it was in «Размер и деление», which the canvas now draws without it.
class SwingCard extends StatelessWidget {
  const SwingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final metronome = AppScope.of(context).metronome;
    final m = metronome.meter;
    final rhythm = m.rhythm == null ? null : RhythmLibrary.describe(m.rhythm!);
    // A rhythmic figure plays as drawn: swing does not apply to it (it was offered and ignored).
    final figure = (rhythm != null && !rhythm.isPlain) || m['beatRhythms'] != null;
    void set(double v) => metronome.updateMeter((x) => x['swing'] = v.clamp(0.5, 0.75));
    return MetroCard(
      children: [
        MetroRow(
          title: 'Свинг',
          subtitle: figure ? 'Не действует при ритмической фигуре' : (m.isSwingAvailable ? null : 'Доступен при чётном делении'),
          showsDivider: false,
          trailing: m.isSwingAvailable && !figure
              ? ValueStepper(
                  value: '${((m.swing - 0.5) / 0.25 * 100).round()} %',
                  canDecrement: m.swing > 0.5,
                  canIncrement: m.swing < 0.75,
                  decrement: () => set(m.swing - 0.025),
                  increment: () => set(m.swing + 0.025),
                )
              : const Text('0 %'),
        ),
      ],
    );
  }
}

// MARK: «Режимы» (canvas top 150): one mode at a time — Обычный, Разгон (with its numbers), Тренировка пропусков,
// Случайный пропуск, Карта песни; the other modes of the app follow under «Ещё режимы».

class ModesSheet extends StatelessWidget {
  const ModesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final m = metronome.state.modes;
    final choice = metronome.modeChoice;

    Widget row(ModeChoice mode, String title, String subtitle, {String? params, Widget? extra}) {
      final selected = mode == choice;
      return Semantics(
        selected: selected,
        button: true,
        child: Pressable(
          scale: 1,
          onTap: () {
            if (selected && params != null) {
              app.sheet = AppSheet('metroModeParams', params);
              return;
            }
            metronome.choose(mode);
            // Modes whose numbers are not on the row open their parameters.
            if (params != null && mode != ModeChoice.speedUp) app.sheet = AppSheet('metroModeParams', params);
          },
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: TruverColors.white(0.06))),
            ),
            // CSS content box: `min-height: 60` is the content's, padding 8 and the border-bottom come on top.
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 9),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SwiftText(title, style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)),
                          const SizedBox(height: 2),
                          SwiftText(subtitle, style: _captionTertiary),
                          ?extra,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    selected
                        ? const AppIconView(AppIcon.check, size: 20, lineWidth: 2, color: TruverColors.textPrimary)
                        : const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// «От 142»: radius 12, white 5 %, padding 8 × 10, caption 11, value 17.
    Widget tile(String caption, String value) => Expanded(
      child: Pressable(
        scale: 1,
        onTap: () => app.sheet = const AppSheet('metroModeParams', 'speedUp'),
        child: ShapeBox(
          shape: const SwiftShape.rounded(12),
          fills: [SwiftFill(TruverColors.white(0.05))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwiftText(caption, style: Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
                SwiftText(value, maxLines: 1, style: Typo.inter(17, TypoWeight.regular, TruverColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );

    return DesignSheet(
      title: 'Режимы',
      height: 694,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: SheetButton(title: 'Готово', onTap: () => app.sheet = null),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption(text: 'Один режим за раз'),
          MetroCard(
            children: [
              row(ModeChoice.normal, 'Обычный', 'темп не меняется'),
              row(
                ModeChoice.speedUp,
                'Разгон',
                'темп растёт до цели',
                params: 'speedUp',
                extra: choice != ModeChoice.speedUp
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 12), // the column's gap 2 + margin-top 10
                        child: Row(
                          children: [
                            tile('От', '${m.start.toInt()}'),
                            const SizedBox(width: 8),
                            tile('До', '${m.target.toInt()}'),
                            const SizedBox(width: 8),
                            tile(
                              'Шаг',
                              m.interval == ModeInterval.seconds
                                  ? '+${m.step.toInt()} · ${m.everySeconds} с'
                                  : '+${m.step.toInt()} · ${m.every} т.',
                            ),
                          ],
                        ),
                      ),
              ),
              row(
                ModeChoice.gapBars,
                'Тренировка пропусков',
                'играет ${m.gapOn} ${MetronomeController.bars(m.gapOn)}, молчит ${m.gapOff}',
                params: 'gapBars',
              ),
              row(ModeChoice.randomMute, 'Случайный пропуск', 'доли выпадают с вероятностью', params: 'randomMute'),
              row(ModeChoice.songMap, 'Карта песни', 'части со своим темпом и размером', params: 'songMap'),
            ],
          ),
          // gap 14 + padding 10 + the half-leading of line-height 1.4.
          const SizedBox(height: 25.14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SwiftText(
              'Режим работает поверх размера и деления. Выключить — выбрать «Обычный».',
              lineSpacing: 16.8 - 14.52,
              style: _captionTertiary,
            ),
          ),
          // Below the canvas content, under the footer until scrolled.
          const SizedBox(height: 34),
          const SectionCaption(text: 'Ещё режимы'),
          MetroCard(
            children: [
              row(
                ModeChoice.twoForward,
                'Два вперёд, один назад',
                '${m.start.toInt()} → ${m.target.toInt()} · N = ${m.step.toInt()}',
                params: 'twoForward',
              ),
              row(ModeChoice.fastSlow, 'Быстро / медленно', 'чередование двух темпов', params: 'fastSlow'),
              row(ModeChoice.displaced, 'Перенос щелчка', 'только 2 и 4 / только «и» / только раз', params: 'displaced'),
              row(ModeChoice.ladder, 'Лесенка делений', '1 → 2 → 3 → 4', params: 'ladder'),
            ],
          ),
        ],
      ),
    );
  }
}

// MARK: Mode parameters (canvas «Режим «Разгон» — параметры», top 200): steppers, «Готово» returns to the modes.

/// `ModeParamKind` raw values: speedUp, twoForward, fastSlow, songMap, displaced, gapBars, randomMute, ladder.
class ModeParamsSheet extends StatelessWidget {
  const ModeParamsSheet({super.key, required this.kind});
  final String kind;

  String get title => switch (kind) {
    'speedUp' => 'Разгон',
    'twoForward' => 'Два вперёд, один назад',
    'fastSlow' => 'Быстро / медленно',
    'songMap' => 'Карта песни',
    'displaced' => 'Перенос щелчка',
    'gapBars' => 'Пропадающие такты',
    'randomMute' => 'Случайный пропуск',
    _ => 'Лесенка делений',
  };

  static String steps(int n) => MetronomeController.plural(n, 'шаг', 'шага', 'шагов');
  static String minutes(int n) => MetronomeController.plural(n, 'минута', 'минуты', 'минут');

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final note = _note(metronome);
    final Widget child;
    if (kind == 'songMap') {
      child = const SongMapEditor();
    } else if (kind == 'randomMute') {
      // Canvas: the card (row 68), then the note 13 / 1.4, 12 below.
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetroCard(children: _rows(metronome)),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, top: 12 + 1.24),
              child: SwiftText(note, lineSpacing: 18.2 - 15.73, style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary)),
            ),
        ],
      );
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(14, [MetroCard(children: _rows(metronome)), if (note != null) SwiftText(note, style: _captionTertiary)]),
      );
    }
    return DesignSheet(
      title: title,
      // Canvas: «Карта песни» top 54, «Случайный пропуск» top 500; the others keep the «Разгон» sheet (top 200).
      height: switch (kind) {
        'songMap' => 790,
        'randomMute' => 344,
        _ => 644,
      },
      close: () => app.sheet = null,
      footer: [
        if (kind == 'songMap') _SaveSongButton(metronome: metronome),
        Expanded(
          child: SheetButton(title: 'Готово', onTap: () => app.sheet = const AppSheet('metroModes')),
        ),
      ],
      child: child,
    );
  }

  List<Widget> _rows(MetronomeController metronome) {
    final m = metronome.state.modes;
    void update(void Function(MetronomeModes m) change) => metronome.updateModes(change);
    switch (kind) {
      case 'speedUp' || 'twoForward':
        return [
          MetroRow(
            title: 'Старт',
            subtitle: 'BPM',
            trailing: ValueStepper(
              value: '${m.start.toInt()}',
              canDecrement: m.start > 20,
              canIncrement: m.start < m.target - 1,
              decrement: () => update((x) => x.start = math.max(20, x.start - 1)),
              increment: () => update((x) => x.start = math.min(x.target - 1, x.start + 1)),
            ),
          ),
          MetroRow(
            title: 'Цель',
            subtitle: 'BPM',
            trailing: ValueStepper(
              value: '${m.target.toInt()}',
              canDecrement: m.target > m.start + 1,
              canIncrement: m.target < 400,
              decrement: () => update((x) => x.target = math.max(x.start + 1, x.target - 1)),
              increment: () => update((x) => x.target = math.min(400, x.target + 1)),
            ),
          ),
          MetroRow(
            title: kind == 'speedUp' ? 'Шаг' : 'N',
            subtitle: 'BPM',
            trailing: ValueStepper(
              value: '+${m.step.toInt()}',
              canDecrement: m.step > 1,
              canIncrement: m.step < 20,
              decrement: () => update((x) => x.step = math.max(1, x.step - 1)),
              increment: () => update((x) => x.step = math.min(20, x.step + 1)),
            ),
          ),
          if (kind == 'speedUp')
            MetroRow(
              title: 'Интервал',
              trailing: SizedBox(
                width: 170,
                child: Segments<ModeInterval>(
                  options: const [(ModeInterval.bars, 'Такты'), (ModeInterval.seconds, 'Секунды')],
                  selection: m.interval,
                  size: SegmentsSize.compact,
                  onChanged: (v) => update((x) => x.interval = v),
                ),
              ),
            ),
          if (kind == 'speedUp' && m.interval == ModeInterval.seconds)
            MetroRow(
              title: 'Каждые',
              subtitle: 'секунд',
              showsDivider: false,
              trailing: ValueStepper(
                value: '${m.everySeconds}',
                canDecrement: m.everySeconds > 5,
                canIncrement: m.everySeconds < 300,
                decrement: () => update((x) => x.everySeconds = math.max(5, x.everySeconds - 5)),
                increment: () => update((x) => x.everySeconds = math.min(300, x.everySeconds + 5)),
              ),
            )
          else
            MetroRow(
              title: 'Каждые',
              subtitle: MetronomeController.bars(m.every),
              showsDivider: false,
              trailing: ValueStepper(
                value: '${m.every}',
                canDecrement: m.every > 1,
                canIncrement: m.every < 32,
                decrement: () => update((x) => x.every = math.max(1, x.every - 1)),
                increment: () => update((x) => x.every = math.min(32, x.every + 1)),
              ),
            ),
        ];
      case 'fastSlow':
        return [
          MetroRow(
            title: 'Медленно',
            subtitle: 'BPM',
            trailing: ValueStepper(
              value: '${m.start.toInt()}',
              canDecrement: m.start > 20,
              canIncrement: m.start < 400,
              decrement: () => update((x) => x.start = math.max(20, x.start - 1)),
              increment: () => update((x) => x.start = math.min(400, x.start + 1)),
            ),
          ),
          MetroRow(
            title: 'Быстро',
            subtitle: 'BPM',
            trailing: ValueStepper(
              value: '${m.fast.toInt()}',
              canDecrement: m.fast > 20,
              canIncrement: m.fast < 400,
              decrement: () => update((x) => x.fast = math.max(20, x.fast - 1)),
              increment: () => update((x) => x.fast = math.min(400, x.fast + 1)),
            ),
          ),
          MetroRow(
            title: 'Каждые',
            subtitle: MetronomeController.bars(m.fastSlowBars),
            showsDivider: false,
            trailing: ValueStepper(
              value: '${m.fastSlowBars}',
              canDecrement: m.fastSlowBars > 1,
              canIncrement: m.fastSlowBars < 32,
              decrement: () => update((x) => x.fastSlowBars -= 1),
              increment: () => update((x) => x.fastSlowBars += 1),
            ),
          ),
        ];
      case 'randomMute':
        return [
          MetroRow(
            title: 'Вероятность пропуска',
            subtitle: 'первая доля звучит всегда',
            minHeight: 68,
            trailing: ValueStepper(
              value: '${m.muteChance} %',
              canDecrement: m.muteChance > 5,
              canIncrement: m.muteChance < 90,
              decrement: () => update((x) => x.muteChance = math.max(5, x.muteChance - 5)),
              increment: () => update((x) => x.muteChance = math.min(90, x.muteChance + 5)),
            ),
          ),
        ];
      case 'displaced':
        return [
          for (final pattern in const ['backbeats', 'offbeats', 'downbeat'])
            RadioRow(
              title: _capitalizedFirst(metronome.patternTitle(pattern)),
              selected: m.pattern == pattern,
              showsDivider: pattern != 'downbeat',
              onTap: () => update((x) => x.pattern = pattern),
            ),
        ];
      case 'gapBars':
        return [
          MetroRow(
            title: 'Со щелчком',
            subtitle: MetronomeController.bars(m.gapOn),
            trailing: ValueStepper(
              value: '${m.gapOn}',
              canDecrement: m.gapOn > 1,
              canIncrement: m.gapOn < 8,
              decrement: () => update((x) => x.gapOn -= 1),
              increment: () => update((x) => x.gapOn += 1),
            ),
          ),
          MetroRow(
            title: 'Без щелчка',
            subtitle: MetronomeController.bars(m.gapOff),
            showsDivider: false,
            trailing: ValueStepper(
              value: '${m.gapOff}',
              canDecrement: m.gapOff > 1,
              canIncrement: m.gapOff < 8,
              decrement: () => update((x) => x.gapOff -= 1),
              increment: () => update((x) => x.gapOff += 1),
            ),
          ),
        ];
      case 'ladder':
        return [
          MetroRow(
            title: 'Тактов на шаг',
            subtitle: 'деления 1 → 2 → 3 → 4',
            showsDivider: false,
            trailing: ValueStepper(
              value: '${m.ladderBarsPerStep}',
              canDecrement: m.ladderBarsPerStep > 1,
              canIncrement: m.ladderBarsPerStep < 8,
              decrement: () => update((x) => x.ladderBarsPerStep -= 1),
              increment: () => update((x) => x.ladderBarsPerStep += 1),
            ),
          ),
        ];
    }
    return const [];
  }

  /// «До цели — 10 шагов, примерно 3 минуты».
  String? _note(MetronomeController metronome) {
    final m = metronome.state.modes;
    if (kind == 'fastSlow') return 'Темп меняется на границе такта. Начинается с медленного.';
    if (kind == 'songMap') {
      return 'Части сменяются на границе такта. Сохраните как пресет — получится песня для сет-листа; педаль ↑ ↓ листает пресеты.';
    }
    if (kind == 'randomMute') {
      return 'Пропущенная доля молчит везде: звук, вспышка, вибрация.';
    }
    if (!(kind == 'speedUp' || kind == 'twoForward') || m.target <= m.start || m.step <= 0) return null;
    final steps = ((m.target - m.start) / m.step).ceil();
    var seconds = 0.0;
    for (var i = 0; i < steps; i++) {
      final bpm = m.start + i * m.step;
      if (kind == 'speedUp' && m.interval == ModeInterval.seconds) {
        seconds += m.everySeconds;
      } else {
        seconds += m.every * metronome.meter.numerator * 60 / bpm;
      }
    }
    if (kind == 'twoForward') seconds *= 1.5;
    final minutes = math.max(1, (seconds / 60).round());
    return 'До цели — $steps ${ModeParamsSheet.steps(steps)}, примерно $minutes ${ModeParamsSheet.minutes(minutes)}';
  }
}

String _capitalizedFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// «В пресет» of «Карта песни» (130 pt, secondary): names and saves the current settings as a preset.
class _SaveSongButton extends StatefulWidget {
  const _SaveSongButton({required this.metronome});
  final MetronomeController metronome;

  @override
  State<_SaveSongButton> createState() => _SaveSongButtonState();
}

class _SaveSongButtonState extends State<_SaveSongButton> {
  final _name = TextEditingController();
  bool _naming = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ScreenAlert(
    alert: !_naming
        ? null
        : TextFieldAlert(
            title: 'Имя пресета',
            controller: _name,
            cancel: () => setState(() => _naming = false),
            save: () {
              final t = _name.text.trim();
              if (t.isNotEmpty) widget.metronome.savePreset(t);
              setState(() => _naming = false);
            },
          ),
    child: Pressable(
      onTap: () {
        _name.text = 'Песня';
        setState(() => _naming = true);
      },
      child: SizedBox(
        width: 130,
        height: 50,
        child: ShapeBox(
          shape: SwiftShape.capsule,
          fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: Center(child: Text('В пресет', style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody))),
        ),
      ),
    ),
  );
}

// MARK: «Пресеты» (canvas top 300; empty: 430): rows 60 pt, swipe left for «Переименовать» / «Удалить» (64 pt each),
// «+ Сохранить текущий как пресет» under the list; while a row is open — the hint about undoing a deletion.

class PresetsSheet extends StatefulWidget {
  const PresetsSheet({super.key});

  @override
  State<PresetsSheet> createState() => _PresetsSheetState();
}

class _PresetsSheetState extends State<PresetsSheet> {
  String? _openRow;

  /// null — no alert; '' — a new preset; otherwise the id being renamed.
  String? _naming;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = AppScope.read(context).metronome.debugOpenPreset;
      if (id != null) setState(() => _openRow = id);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startNaming(MetronomeController m) {
    final figure = m.meter.rhythm == null ? null : RhythmLibrary.describe(m.meter.rhythm!);
    _name.text = '${m.meter.numerator}/${m.meter.denominator}${figure != null ? ' · ${figure.name}' : ''}';
    setState(() => _naming = '');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    return ListenableBuilder(
      listenable: metronome,
      builder: (context, _) {
        final presets = metronome.state.presets;
        final sheet = DesignSheet(
          title: 'Пресеты',
          height: presets.isEmpty ? 414 : 544,
          close: () => app.sheet = null,
          child: presets.isEmpty ? _empty(metronome) : _list(app, metronome, presets),
        );
        final deleted = metronome.deletedPreset;
        return Stack(
          children: [
            sheet,
            if (deleted != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 40,
                child: ShapeBox(
                  shape: const SwiftShape.rounded(16),
                  shadows: [SwiftShadow(TruverColors.black(0.6), 15, y: 14)],
                  fills: const [SwiftFill(Color(0xF526282D))],
                  strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    child: Row(
                      children: [
                        const AppIconView(AppIcon.trash, size: 16, color: TruverColors.textTertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '«${deleted.preset.name}» удалён',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Typo.inter(13, TypoWeight.medium, TruverColors.textBody),
                          ),
                        ),
                        Pressable(
                          onTap: metronome.undoDelete,
                          child: Text('Отменить', style: Typo.inter(13, TypoWeight.semibold, TruverColors.textPrimary)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_naming != null)
              Positioned.fill(
                child: TextFieldAlert(
                  title: 'Имя пресета',
                  controller: _name,
                  cancel: () => setState(() => _naming = null),
                  save: () {
                    final t = _name.text.trim();
                    if (t.isNotEmpty) {
                      if (_naming!.isEmpty) {
                        metronome.savePreset(t);
                      } else {
                        metronome.renamePreset(_naming!, t);
                      }
                    }
                    setState(() {
                      _naming = null;
                      _openRow = null;
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _list(AppModel app, MetronomeController metronome, List<MetronomePreset> presets) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionCaption(text: _openRow == null ? 'Пресеты · размер, деление, режим и темп' : 'Пресеты'),
      MetroCard(
        children: [
          for (final preset in presets)
            PresetSwipeRow(
              open: _openRow == preset.id,
              onOpen: (open) => setState(() => _openRow = open ? preset.id : null),
              rename: () {
                _name.text = preset.name;
                setState(() => _naming = preset.id);
              },
              delete: () {
                setState(() => _openRow = null);
                metronome.deletePresetUndoable(preset.id);
              },
              child: Pressable(
                scale: 1,
                onTap: () {
                  metronome.load(preset);
                  app.sheet = null;
                },
                child: SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwiftText(preset.name, maxLines: 1, style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)),
                              const SizedBox(height: 2),
                              SwiftText(metronome.presetSubtitle(preset), maxLines: 1, style: _captionTertiary),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${preset.settings.bpm.toInt()}', style: Typo.inter(15, TypoWeight.regular, TruverColors.textSecondary)),
                        if (_openRow != preset.id) ...[
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: preset.id == metronome.state.currentPresetId
                                ? const AppIconView(AppIcon.check, size: 20, lineWidth: 2, color: TruverColors.textPrimary)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      if (_openRow != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, top: 11.14),
          child: SwiftText(
            'Свайп влево — переименовать или удалить. Удалённый можно вернуть: «Отменить» на 5 секунд.',
            lineSpacing: 16.8 - 14.52,
            style: _captionTertiary,
          ),
        )
      else
        Pressable(
          onTap: () => _startNaming(metronome),
          child: SizedBox(
            height: 50,
            child: ShapeBox(
              shape: SwiftShape.capsule,
              fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
              strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppIconView(AppIcon.plus, size: 16, color: TruverColors.textBody),
                  const SizedBox(width: 8),
                  Text('Сохранить текущий как пресет', style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody)),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  /// «Пресетов пока нет»: the metronome icon in a 56 pt ring, title 17 semibold, text 13, the ivory button 18 below.
  Widget _empty(MetronomeController metronome) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 26, left: 10, right: 10, bottom: 10),
        child: Column(
          children: [
            // A 56 pt CSS span with a 1 pt border outside its content box — 58 in all.
            SizedBox(
              width: 58,
              height: 58,
              child: ShapeBox(
                shape: SwiftShape.circle,
                strokes: [SwiftStroke(TruverColors.white(0.12), inside: true)],
                child: const Center(child: AppIconView(AppIcon.metronome, size: 24, color: TruverColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 10),
            SwiftText('Пресетов пока нет', style: Typo.inter(17, TypoWeight.semibold, TruverColors.textPrimary)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.24), // the half-leading of line-height 1.4
                child: SwiftText(
                  'Настройте темп, размер и режим — и сохраните, чтобы включать одним касанием',
                  textAlign: TextAlign.center,
                  lineSpacing: 18.2 - 15.73,
                  style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      SheetButton(title: 'Сохранить текущий как пресет', onTap: () => _startNaming(metronome)),
    ],
  );
}

/// A preset row with swipe-left actions (canvas «Пресеты — свайп»): «Переименовать» #3a3d44 and «Удалить» #c9483e,
/// 64 pt each, icons only; the open row narrows to the space left of them.
class PresetSwipeRow extends StatefulWidget {
  const PresetSwipeRow({
    super.key,
    required this.open,
    required this.onOpen,
    required this.rename,
    required this.delete,
    required this.child,
  });
  final bool open;
  final ValueChanged<bool> onOpen;
  final VoidCallback rename;
  final VoidCallback delete;
  final Widget child;

  @override
  State<PresetSwipeRow> createState() => _PresetSwipeRowState();
}

class _PresetSwipeRowState extends State<PresetSwipeRow> {
  static const _reveal = 128.0;
  double _drag = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.open ? -_reveal : 0.0;
    final offset = (base + _drag).clamp(-_reveal, 0.0);
    final settled = widget.open && !_dragging;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Переименовать'): widget.rename,
        const CustomSemanticsAction(label: 'Удалить'): widget.delete,
      },
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => setState(() => _drag += d.delta.dx),
        onHorizontalDragEnd: (_) {
          final open = base + _drag < -_reveal / 2;
          setState(() {
            _drag = 0;
            _dragging = false;
          });
          widget.onOpen(open);
        },
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: TruverColors.white(0.06))),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 1), // the row's border-bottom under its 60 pt
            child: SizedBox(
              height: 60,
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    children: [
                      if (offset < 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Row(
                            children: [
                              Pressable(
                                scale: 1,
                                label: 'Переименовать',
                                onTap: widget.rename,
                                child: Container(
                                  width: 64,
                                  color: const Color(0xFF3A3D44),
                                  alignment: Alignment.center,
                                  child: const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: Stack(
                                      children: [
                                        AppIconView(AppIcon.list, size: 18, color: TruverColors.textPrimary),
                                        Positioned(
                                          left: 6.75 - 1.5,
                                          top: 5.25 - 1.5,
                                          width: 3,
                                          height: 3,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: TruverColors.background,
                                              shape: BoxShape.circle,
                                              border: Border.fromBorderSide(BorderSide(color: TruverColors.textPrimary, width: 1.2)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Pressable(
                                scale: 1,
                                label: 'Удалить',
                                onTap: widget.delete,
                                child: Container(
                                  width: 64,
                                  color: const Color(0xFFC9483E),
                                  alignment: Alignment.center,
                                  child: const AppIconView(AppIcon.trash, size: 18, color: Color(0xFFFFFFFF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Positioned(
                        left: settled ? 0 : offset,
                        top: 0,
                        bottom: 0,
                        width: settled ? box.maxWidth - _reveal : box.maxWidth,
                        child: ColoredBox(color: offset < 0 ? const Color(0xFF1A1C20) : const Color(0x00000000), child: widget.child),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// MARK: «Звуки и выход» (canvas top 230): the click set as chips, «Громкость акцента», vibration on the strong beat,
// flash and output rows.

class SoundsSheet extends StatefulWidget {
  const SoundsSheet({super.key});

  static String title(String kind) => switch (kind) {
    'wood' => 'Дерево',
    'electronic' => 'Бип',
    'hiHat' => 'Хай-хэт',
    'voice' => 'Голос',
    _ => 'Щелчок',
  };

  static String flashTitle(FlashTarget t) => switch (t) {
    FlashTarget.off => 'Выкл',
    FlashTarget.strip => 'Полоса долей',
    FlashTarget.screen => 'Весь экран',
  };

  /// «+6 дБ», «0 дБ», «−3 дБ».
  static String db(double value) {
    final n = value.round();
    return '${n > 0 ? '+$n' : (n < 0 ? '−${-n}' : '0')} дБ';
  }

  @override
  State<SoundsSheet> createState() => _SoundsSheetState();
}

class _SoundsSheetState extends State<SoundsSheet> {
  bool _choosingFlash = false;
  bool _confirmScreenFlash = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final s = metronome.state;
    Widget chevronValue(String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
        const SizedBox(width: 8),
        const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
      ],
    );
    final sheet = DesignSheet(
      title: 'Звуки и выход',
      height: 614,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: SheetButton(title: 'Готово', onTap: () => app.sheet = null),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(14, [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionCaption(text: 'Звук'),
              MetroCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FlowLayout(
                        spacing: 6,
                        children: [
                          for (final kind in const ['click', 'wood', 'electronic', 'hiHat', 'voice'])
                            Pressable(
                              onTap: () {
                                metronome.updateState((x) => x.sound = kind);
                                app.audio.setVolumes(sound: kind);
                              },
                              child: Chip(text: SoundsSheet.title(kind), style: s.sound == kind ? ChipStyle.emphasized : ChipStyle.plain),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          MetroCard(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Громкость акцента', style: Typo.row.copyWith(color: TruverColors.textBody)),
                        const Spacer(),
                        Text(
                          SoundsSheet.db(s.accentDB),
                          style: Typo.monospacedDigit(Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AccentSlider(
                      value: s.accentDB,
                      onChanged: (v) {
                        metronome.updateState((x) => x.accentDB = v);
                        app.audio.setVolumes(accentDB: v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          MetroCard(
            children: [
              MetroRow(
                title: 'Вибрация на сильной доле',
                trailing: ToggleSwitch(
                  isOn: app.settings.vibration,
                  label: 'Вибрация на сильной доле',
                  onChanged: (v) => app.updateSettings((x) => x.vibration = v),
                ),
              ),
              Pressable(
                scale: 1,
                onTap: () => setState(() => _choosingFlash = true),
                child: MetroRow(title: 'Вспышка', minHeight: 52, trailing: chevronValue(SoundsSheet.flashTitle(s.flash))),
              ),
              Pressable(
                scale: 1,
                onTap: () => app.showSettings = true,
                child: MetroRow(
                  title: 'Выход',
                  subtitle: 'при наушниках — в наушники',
                  minHeight: 60,
                  trailing: chevronValue(app.audio.outputName),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
    final Widget? alert;
    if (_confirmScreenFlash) {
      alert = DesignAlert(
        title: 'Вспышка на весь экран',
        message:
            'Экран будет мигать в такт — не больше 3 раз в секунду. Если у вас светочувствительность, оставьте вспышку на полосе долей.',
        dismiss: () => setState(() => _confirmScreenFlash = false),
        actions: [
          DesignAlertAction('Отмена', () => setState(() => _confirmScreenFlash = false), role: DesignAlertRole.preferred),
          DesignAlertAction('Включить', () {
            metronome.updateState((x) => x.flash = FlashTarget.screen);
            setState(() => _confirmScreenFlash = false);
          }),
        ],
      );
    } else {
      alert = null;
    }
    return _ScreenAlert(
      alert: alert,
      child: _withPanelOverlay(
        sheet,
        !_choosingFlash
            ? null
            : DesignAlert(
                title: 'Вспышка',
                message: 'Не больше 3 вспышек в секунду',
                dismiss: () => setState(() => _choosingFlash = false),
                actions: [
                  for (final t in FlashTarget.values)
                    DesignAlertAction(SoundsSheet.flashTitle(t), () {
                      setState(() {
                        _choosingFlash = false;
                        if (t == FlashTarget.screen) _confirmScreenFlash = true;
                      });
                      if (t != FlashTarget.screen) metronome.updateState((x) => x.flash = t);
                    }, role: s.flash == t ? DesignAlertRole.preferred : DesignAlertRole.normal),
                ],
              ),
      ),
    );
  }
}

/// «Громкость акцента» slider of the canvas: 4 pt track (white 12 %), ivory fill, 28 pt white thumb; −3…+17 dB in
/// 1 dB steps (+6 sits at 45 %).
class AccentSlider extends StatelessWidget {
  const AccentSlider({super.key, required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  static const lower = -3.0, upper = 17.0;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Громкость акцента',
    value: SoundsSheet.db(value),
    increasedValue: SoundsSheet.db(math.min(upper, value + 1)),
    decreasedValue: SoundsSheet.db(math.max(lower, value - 1)),
    onIncrease: () => onChanged(math.min(upper, value + 1)),
    onDecrease: () => onChanged(math.max(lower, value - 1)),
    child: SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final f = (value - lower) / (upper - lower);
          void set(double x) => onChanged((lower + (x / w).clamp(0.0, 1.0) * (upper - lower)).roundToDouble());
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => set(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 12,
                  height: 4,
                  child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.12))]),
                ),
                Positioned(
                  left: 0,
                  width: w * f,
                  top: 12,
                  height: 4,
                  child: const ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.accent)]),
                ),
                Positioned(
                  left: w * f - 14,
                  top: 0,
                  width: 28,
                  height: 28,
                  child: ShapeBox(
                    shape: SwiftShape.circle,
                    shadows: [SwiftShadow(TruverColors.black(0.5), 3, y: 2)],
                    fills: const [SwiftFill(Color(0xFFFFFFFF))],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

// MARK: «Таймер занятия» (canvas top 520): «Остановить через 20 мин» with a switch, «Минут» — 5 10 20 30 45 «…».

class TimerSheet extends StatefulWidget {
  const TimerSheet({super.key});

  @override
  State<TimerSheet> createState() => _TimerSheetState();
}

class _TimerSheetState extends State<TimerSheet> {
  static const _presets = [5, 10, 20, 30, 45];
  bool _custom = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set(MetronomeController metronome, int minutes) => metronome.updateState((x) {
    x.timerMinutes = minutes.clamp(1, 180);
    x.timerEnabled = true;
  });

  /// 40 pt capsule, 14 medium; the chosen one has an ivory ring.
  Widget _cell(String text, bool selected, VoidCallback onTap) => Expanded(
    child: Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        label: text == '…' ? 'Другое время' : '$text минут',
        child: SizedBox(
          height: 40,
          child: ShapeBox(
            shape: SwiftShape.capsule,
            fills: [SwiftFill(TruverColors.white(selected ? 0.1 : 0.05))],
            strokes: [SwiftStroke(selected ? TruverColors.selectedBorder : TruverColors.hairlineStrong, inside: true)],
            child: Center(child: Text(text, style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary))),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final s = metronome.state;
    final sheet = DesignSheet(
      title: 'Таймер занятия',
      height: 324,
      close: () => app.sheet = null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetroCard(
            children: [
              MetroRow(
                title: 'Остановить через ${s.timerMinutes} мин',
                subtitle: 'сигнал, такт доигрывается',
                minHeight: 60,
                trailing: ToggleSwitch(
                  isOn: s.timerEnabled,
                  label: 'Таймер занятия',
                  onChanged: (v) => metronome.updateState((x) => x.timerEnabled = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SectionCaption(text: 'Минут'),
          Row(
            children: [
              for (final minutes in _presets) ...[
                _cell('$minutes', s.timerMinutes == minutes, () => _set(metronome, minutes)),
                const SizedBox(width: 6),
              ],
              _cell('…', !_presets.contains(s.timerMinutes), () {
                _text.text = '${s.timerMinutes}';
                setState(() => _custom = true);
              }),
            ],
          ),
        ],
      ),
    );
    return _withPanelOverlay(
      sheet,
      !_custom
          ? null
          : TextFieldAlert(
              title: 'Минут, от 1 до 180',
              controller: _text,
              cancel: () => setState(() => _custom = false),
              save: () {
                final n = int.tryParse(_text.text.trim());
                if (n != null) _set(metronome, n);
                setState(() => _custom = false);
              },
            ),
    );
  }
}

// MARK: «Карта песни» (canvas top 54): count-in and loop, parts as cards (≡ drag handle, number, name, meter chip,
// delete; tempo and length steppers), «+ Часть». The list sits in a 560 pt window that fades at the bottom.

class SongMapEditor extends StatefulWidget {
  const SongMapEditor({super.key});

  static const meters = [(2, 4), (3, 4), (4, 4), (5, 4), (6, 8), (7, 8), (9, 8), (12, 8), (5, 8), (11, 8), (13, 16)];

  /// A part card is 11 + 36 + 6 + 36 + 2 + 13 + 13 pt tall, 10 apart.
  static const partStride = 127.0 + 10;

  @override
  State<SongMapEditor> createState() => _SongMapEditorState();
}

class _SongMapEditorState extends State<SongMapEditor> {
  String? _renaming;
  final _name = TextEditingController();

  /// The part whose meter menu is open.
  String? _meterMenu;
  String? _dragging;
  double _dragOffset = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _update(MetronomeController metronome, void Function(MetronomeModes m) change) => metronome.updateModes(change);

  void _set(MetronomeController metronome, int index, void Function(Map<String, dynamic> part) change) => _update(metronome, (m) {
    if (index >= 0 && index < m.song.length) change(m.song[index]);
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final modes = metronome.state.modes;
    final song = modes.song;
    final editor = SizedBox(
      height: 560,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetroCard(
                  children: [
                    MetroRow(
                      title: 'Отсчёт',
                      subtitle: 'такт перед первой частью',
                      trailing: ToggleSwitch(
                        isOn: modes.songCountIn,
                        label: 'Отсчёт',
                        onChanged: (v) => _update(metronome, (m) => m.songCountIn = v),
                      ),
                    ),
                    MetroRow(
                      title: 'По кругу',
                      subtitle: 'иначе в конце — стоп',
                      trailing: ToggleSwitch(
                        isOn: modes.songLoop,
                        label: 'По кругу',
                        onChanged: (v) => _update(metronome, (m) => m.songLoop = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
                  child: SwiftText('Части · сменяются на границе такта · ≡ — перетащить', style: _captionTertiary),
                ),
                for (var i = 0; i < song.length; i++) ...[
                  const SizedBox(height: 10),
                  Transform.translate(
                    offset: Offset(0, _dragging == '${song[i]['id']}' ? _dragOffset : 0),
                    child: _partCard(metronome, i, song[i], song.length),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Pressable(
                    onTap: () => _update(metronome, (m) {
                      final next = Map<String, dynamic>.from(
                        m.song.lastOrNull ?? {'name': 'Часть', 'bpm': 120, 'numerator': 4, 'denominator': 4, 'bars': 8},
                      );
                      next['id'] = newUuid();
                      next['name'] = 'Часть ${m.song.length + 1}';
                      m.song.add(next);
                    }),
                    child: const Chip(text: '+ Часть'),
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 40,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000D0E10), TruverColors.panel],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (_renaming == null) return editor;
    // TextFieldAlert over the editor (SwiftUI `.overlay` of the editor).
    return Stack(
      children: [
        editor,
        Positioned.fill(
          child: TextFieldAlert(
            title: 'Название части',
            controller: _name,
            cancel: () => setState(() => _renaming = null),
            save: () {
              final t = _name.text.trim();
              final id = _renaming;
              if (id != null && t.isNotEmpty) {
                _update(metronome, (m) {
                  for (final s in m.song) {
                    if (s['id'] == id) s['name'] = t;
                  }
                });
              }
              setState(() => _renaming = null);
            },
          ),
        ),
      ],
    );
  }

  Widget _partCard(MetronomeController metronome, int index, Map<String, dynamic> part, int count) {
    final bpm = (part['bpm'] as num).toDouble();
    final bars = (part['bars'] as num).toInt();
    final id = '${part['id']}';
    final label = Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary);
    return ShapeBox(
      shape: const SwiftShape.rounded(16),
      fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
      strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
      child: Padding(
        padding: const EdgeInsets.only(left: 13, right: 13, top: 11, bottom: 13),
        child: Column(
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Semantics(
                    label: 'Перетащить',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => setState(() {
                        _dragging = id;
                        _dragOffset = 0;
                      }),
                      onVerticalDragUpdate: (d) => setState(() => _dragOffset += d.delta.dy),
                      onVerticalDragEnd: (_) {
                        final shift = (_dragOffset / SongMapEditor.partStride).round();
                        final target = (index + shift).clamp(0, count - 1);
                        setState(() {
                          _dragging = null;
                          _dragOffset = 0;
                        });
                        if (target != index) {
                          _update(metronome, (m) {
                            final p = m.song.removeAt(index);
                            m.song.insert(target, p);
                          });
                        }
                      },
                      child: SizedBox(
                        width: 18,
                        height: 36,
                        child: Center(child: Text('≡', style: Typo.inter(18, TypoWeight.regular, TruverColors.textTertiary))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 12, child: Text('${index + 1}', style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Pressable(
                      scale: 1,
                      onTap: () {
                        _name.text = '${part['name']}';
                        setState(() => _renaming = id);
                      },
                      child: Text(
                        '${part['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Typo.inter(16, TypoWeight.medium, TruverColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _meterButton(metronome, index, part, id),
                  if (count > 1) ...[
                    const SizedBox(width: 8),
                    RoundIconButton(
                      icon: AppIcon.trash,
                      size: 36,
                      iconSize: 16,
                      label: 'Удалить часть',
                      onTap: () => _update(metronome, (m) => m.song.removeAt(index)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueStepper(
                      value: '${bpm.toInt()}',
                      valueMaxWidth: null,
                      canDecrement: bpm > 20,
                      canIncrement: bpm < 400,
                      decrement: () => _set(metronome, index, (p) => p['bpm'] = math.max(20, bpm - 1)),
                      increment: () => _set(metronome, index, (p) => p['bpm'] = math.min(400, bpm + 1)),
                    ),
                    const SizedBox(height: 2),
                    SwiftText('BPM', style: label),
                  ],
                ),
                const Spacer(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueStepper(
                      value: '$bars',
                      valueMaxWidth: null,
                      canDecrement: bars > 1,
                      canIncrement: bars < 128,
                      decrement: () => _set(metronome, index, (p) => p['bars'] = bars - 1),
                      increment: () => _set(metronome, index, (p) => p['bars'] = bars + 1),
                    ),
                    const SizedBox(height: 2),
                    SwiftText(MetronomeController.bars(bars), style: label),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// SwiftUI `Menu` of meters: the header chip opens a list over the card.
  Widget _meterButton(MetronomeController metronome, int index, Map<String, dynamic> part, String id) {
    final label = '${part['numerator']}/${part['denominator']}';
    return _MenuAnchor(
      open: _meterMenu == id,
      onClose: () => setState(() => _meterMenu = null),
      items: [
        for (final (n, d) in SongMapEditor.meters)
          (
            '$n/$d',
            () {
              setState(() => _meterMenu = null);
              _set(metronome, index, (p) {
                p['numerator'] = n;
                p['denominator'] = d;
              });
            },
          ),
      ],
      child: Pressable(
        label: 'Размер $label',
        onTap: () => setState(() => _meterMenu = id),
        child: HeaderChip(text: label, icon: AppIcon.chevronDown, iconSize: 12),
      ),
    );
  }
}

/// A popup list under its anchor (iOS `Menu`): rows of 44 pt on the menu material, closes on a tap outside.
class _MenuAnchor extends StatefulWidget {
  const _MenuAnchor({required this.open, required this.onClose, required this.items, required this.child});
  final bool open;
  final VoidCallback onClose;
  final List<(String, VoidCallback)> items;
  final Widget child;

  @override
  State<_MenuAnchor> createState() => _MenuAnchorState();
}

class _MenuAnchorState extends State<_MenuAnchor> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.open && !_controller.isShowing) _controller.show();
      if (!widget.open && _controller.isShowing) _controller.hide();
    });
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (_) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onClose),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: SizedBox(
                width: 180,
                child: ShapeBox(
                  shape: const SwiftShape.rounded(14, continuous: true),
                  shadows: [SwiftShadow(TruverColors.black(0.7), 25, y: 20)],
                  fills: const [SwiftFill(Color(0xFA282A2F))],
                  clip: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (title, action) in widget.items)
                            Pressable(
                              scale: 1,
                              onTap: action,
                              child: DecoratedBox(
                                position: DecorationPosition.foreground,
                                decoration: rowDivider,
                                child: SizedBox(
                                  height: 44,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(title, style: Typo.inter(16, TypoWeight.regular, TruverColors.textPrimary)),
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
              ),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

// MARK: ME-8 «Вторая дорожка» in «Размер и деление»: none, polyrhythm (N even pulses per bar) or polymeter (a click
// every N beats across bar lines), its own bell sound.

class PolyTrackSection extends StatelessWidget {
  const PolyTrackSection({super.key});

  static int _lcm(int a, int b) {
    int gcd(int x, int y) => y == 0 ? x : gcd(y, x % y);
    return a ~/ math.max(1, gcd(a, b)) * b;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final m = metronome.meter;
    final poly = m.poly;
    final count = (poly?['count'] as num?)?.toInt() ?? 0;
    final isRhythm = poly?['kind'] == 'rhythm';
    void setCount(int n) => metronome.updateMeter((x) => x['poly'] = {...?x.poly, 'count': n});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(8, [
        SwiftText('Вторая дорожка', style: _captionTertiary),
        Segments<String>(
          options: const [('none', 'Нет'), ('rhythm', 'Полиритм'), ('meter', 'Полиметр')],
          selection: poly == null ? 'none' : (isRhythm ? 'rhythm' : 'meter'),
          size: SegmentsSize.compact,
          onChanged: (choice) => metronome.updateMeter((x) {
            switch (choice) {
              case 'rhythm':
                x['poly'] = {'kind': 'rhythm', 'count': x.numerator == 3 ? 2 : 3};
              case 'meter':
                x['poly'] = {'kind': 'meter', 'count': x.numerator == 3 ? 4 : 3};
              default:
                x.remove('poly');
            }
          }),
        ),
        if (poly != null)
          MetroCard(
            children: [
              MetroRow(
                title: isRhythm ? '$count против ${m.numerator}' : '$count/${m.denominator} против ${m.numerator}/${m.denominator}',
                subtitle: isRhythm
                    ? 'ровных ударов на такт, свой звук'
                    : 'щелчок каждые $count доли, сходятся через ${_lcm(count, m.numerator)}',
                showsDivider: false,
                trailing: ValueStepper(
                  value: '$count',
                  canDecrement: count > 2,
                  canIncrement: count < 16,
                  decrement: () => setCount(count - 1),
                  increment: () => setCount(count + 1),
                ),
              ),
            ],
          ),
      ]),
    );
  }
}

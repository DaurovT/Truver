/// Port of Truver/Sources/Features/Fretboard/ProgressionViews.swift
///
/// «Прогрессия» row under the mode switcher: key «G ▾» (transposes the whole progression, TH-7), the progression
/// «Поп · I–V–vi–IV ▾», and the «Ритм» sheet; the chord ribbon, the window / tempo row, the chord sheet.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'fret_menu.dart';
import 'fret_modes.dart';
import 'fretboard_controller.dart';
import 'fretboard_screen.dart';
import 'progression_controller.dart';

double _bpm(AppModel app) => (app.settings.metronome.meter['bpm'] as num?)?.toDouble() ?? 100;
int _meterInt(AppModel app, String key) => (app.settings.metronome.meter[key] as num?)?.toInt() ?? 4;
void _stepBpm(AppModel app, double delta) =>
    app.updateSettings((s) => s.metronome.meter['bpm'] = (_bpm(app) + delta).clamp(20, 400).roundToDouble());

class ProgressionPickerRow extends StatelessWidget {
  const ProgressionPickerRow({super.key, required this.askName});

  /// Asks for a name: true — rename the open progression, false — save as new.
  final void Function(bool rename) askName;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.fretboard.progression;
    if (p.rows.isEmpty) p.recompute();
    return Row(
      children: [
        Builder(
          builder: (context) => Pressable(
            label: 'Тональность ${p.keyText}',
            onTap: () {
              final names = spellings(app, [for (var pc = 0; pc < 12; pc++) (pc, const [1, 3, 8, 10].contains(pc))]);
              final keyPC = notePitchClass(p.key);
              showFretMenu(context, [
                for (var pc = 0; pc < names.length; pc++) FretMenuItem(names[pc].text, () => p.transpose(((pc - keyPC) % 12 + 12) % 12)),
              ]);
            },
            child: _capsule('${p.keyText}${p.isMinor ? ' минор' : ' мажор'}', 116),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Builder(
            builder: (context) => Pressable(
              label: 'Прогрессия: ${p.name}',
              onTap: () => showFretMenu(context, [
                FretMenuItem('Сохранить как…', () => askName(false)),
                if (p.activeSaved != null) ...[
                  FretMenuItem('Переименовать…', () => askName(true)),
                  FretMenuItem('Удалить', p.deleteActive, destructive: true),
                ] else if (p.isCustom)
                  FretMenuItem('Вернуть «${p.templateName}»', p.resetToTemplate),
                for (final item in p.saved) FretMenuItem(item.name, () => p.open(item)),
                for (final t in p.templates) FretMenuItem(t.name, () => p.templateId = t.id),
              ]),
              child: _capsule(p.name, null),
            ),
          ),
        ),
        const SizedBox(width: 8),
        RoundIconButton(icon: AppIcon.sliders, size: 44, label: 'Ритм', onTap: () => app.sheet = const AppSheet('fretProgression')),
      ],
    );
  }

  Widget _capsule(String text, double? width) => SizedBox(
        width: width,
        height: 44,
        child: ShapeBox(
          shape: SwiftShape.capsule,
          fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            // A fixed width centres the label and the chevron (SwiftUI `.frame(width:)`); otherwise the label fills.
            child: width != null
                ? Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text.rich(Typo.notes(text, Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      const AppIconView(AppIcon.chevronDown, size: 14, color: TruverColors.textTertiary),
                    ]),
                  )
                : Row(children: [
                    Expanded(
                      child: Text.rich(Typo.notes(text, Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    const AppIconView(AppIcon.chevronDown, size: 14, color: TruverColors.textTertiary),
                  ]),
          ),
        ),
      );
}

/// The chord ribbon (FB-24): bar numbers, chord name, Roman numeral; the current chord is lit; «вне позиции» when a
/// chord left the hand window (FB-22). Tap shows the chord and strums it; a tap on the shown one opens its editor.
class ProgressionRibbon extends StatefulWidget {
  const ProgressionRibbon({super.key});

  @override
  State<ProgressionRibbon> createState() => _ProgressionRibbonState();
}

class _ProgressionRibbonState extends State<ProgressionRibbon> {
  final _scroll = ScrollController();
  int _lastCurrent = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _barNumber(ProgressionController p, int index) {
    var bar = 1;
    final chords = p.chords;
    for (var i = 0; i < index && i < chords.length; i++) {
      bar += p.barsPerChord ?? chords[i].bars;
    }
    return bar;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.fretboard.progression;
    if (p.current != _lastCurrent) {
      _lastCurrent = p.current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target = (p.current * 70.0 - 120).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target, duration: const Duration(milliseconds: 240), curve: const Cubic(0.2, 0.8, 0.2, 1));
      });
    }
    final rows = p.rows;
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Row(
          children: [
            for (var index = 0; index < p.voiced.length; index++) ...[
              () {
                final v = p.voiced[index];
                final selected = index == p.current;
                final numeral = index < rows.length ? rows[index].numeral : '';
                final caption = v.voicing == null ? 'не помещается' : (v.outOfWindow ? 'вне позиции' : numeral);
                return Pressable(
                  selected: selected,
                  label: 'Такт ${_barNumber(p, index)}, ${v.name}',
                  onTap: () {
                    if (index == p.current && !p.isPlaying) {
                      app.sheet = AppSheet('progressionChord', index);
                    } else {
                      p.select(index);
                    }
                  },
                  child: _RibbonCard(
                    bar: _barNumber(p, index),
                    name: Typo.compactChordName(v.name),
                    caption: caption,
                    warning: v.outOfWindow || v.voicing == null,
                    missing: v.voicing == null,
                    selected: selected,
                    beats: selected && p.isPlaying ? _meterInt(app, 'numerator') : null,
                    beat: p.playingBeat,
                  ),
                );
              }(),
              const SizedBox(width: 6),
            ],
            Pressable(
              label: 'Добавить аккорд',
              onTap: () => app.sheet = const AppSheet('progressionChord'),
              child: SizedBox(
                width: 52,
                height: 64,
                child: CustomPaint(
                  painter: _DashedRoundRect(),
                  child: const Center(child: AppIconView(AppIcon.plus, size: 20, color: TruverColors.textSecondary)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRoundRect extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = const SwiftShape.rounded(14, continuous: true).path(Offset.zero & size, 0.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = TruverColors.hairlineStrong;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundRect old) => false;
}

class _RibbonCard extends StatelessWidget {
  const _RibbonCard({
    required this.bar,
    required this.name,
    required this.caption,
    required this.warning,
    required this.missing,
    required this.selected,
    this.beats,
    this.beat,
  });

  final int bar;
  final String name;
  final String caption;
  final bool warning;
  final bool missing;
  final bool selected;

  /// While it plays: the bar's beats as dots instead of the numeral — you see when the change comes.
  final int? beats;
  final int? beat;

  @override
  Widget build(BuildContext context) => ShapeBox(
        shape: const SwiftShape.rounded(14, continuous: true),
        fills: [selected ? SwiftFill(TruverColors.textPrimary.withValues(alpha: 0.12)) : const SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: [SwiftStroke(selected ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true)],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SwiftText('такт $bar', style: Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary)),
                const SizedBox(height: 2),
                notesText(name, Typo.inter(17, TypoWeight.medium, missing ? TruverColors.textTertiary : TruverColors.textPrimary),
                    maxLines: 1),
                const SizedBox(height: 2),
                if (beats != null)
                  SizedBox(
                    height: 13,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < math.min(beats!, 9); i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        SizedBox(
                          width: 5,
                          height: 5,
                          child: ShapeBox(shape: SwiftShape.circle, fills: [SwiftFill(i == beat ? TruverColors.textPrimary : TruverColors.white(0.2))]),
                        ),
                      ],
                    ]),
                  )
                else
                  notesText(caption, Typo.inter(11, TypoWeight.regular, warning ? TruverColors.sharp : TruverColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
}

/// Window «‹ лады 4–8 ›» (FB-22) or the tempo, and «Сыграть / Стоп».
class ProgressionControlRow extends StatelessWidget {
  const ProgressionControlRow({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.fretboard.progression;
    final window = p.window;
    return Row(
      children: [
        if (window != null) ...[
          RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Окно ниже', onTap: () => p.shiftWindow(-1)),
          const SizedBox(width: 8),
          Expanded(
            child: Pressable(
              scale: 1,
              label: 'Тап — весь гриф',
              onTap: p.useWholeNeck,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwiftText('Окно руки', style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
                SwiftText('лады ${window.$1}–${window.$2}', style: Typo.inter(12, TypoWeight.semibold, TruverColors.textPrimary)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          RoundIconButton(icon: AppIcon.chevronRight, size: 44, label: 'Окно выше', onTap: () => p.shiftWindow(1)),
        ] else
          // Tempo right here (it is the metronome's): ± 1, long press ± 5.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _tempoButton(app, AppIcon.minus, -1),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 40),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SwiftText('${_bpm(app).round()}',
                        style: Typo.monospacedDigit(Typo.fixed(17, TypoWeight.semibold, TruverColors.textPrimary))),
                    SwiftText('BPM', style: Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary)),
                  ]),
                ),
                const SizedBox(width: 6),
                _tempoButton(app, AppIcon.plus, 1),
              ],
            ),
          ),
        const SizedBox(width: 8),
        Pressable(
          label: p.isPlaying ? 'Стоп' : 'Сыграть прогрессию',
          onTap: p.toggle,
          child: SizedBox(
            height: 52,
            child: ShapeBox(
              shape: SwiftShape.capsule,
              shadows: [SwiftShadow(TruverColors.black(0.35), 9, y: 6)],
              fills: const [SwiftFill(TruverColors.textPrimary)],
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 18),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIconView(p.isPlaying ? AppIcon.stop : AppIcon.play, size: 18, color: TruverColors.background),
                  const SizedBox(width: 8),
                  Text(p.isPlaying ? 'Стоп' : 'Сыграть', style: Typo.inter(16, TypoWeight.semibold, TruverColors.background)),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tempoButton(AppModel app, AppIcon icon, double delta) => GestureDetector(
        onLongPress: () => _stepBpm(app, delta * 5),
        child: RoundIconButton(icon: icon, size: 40, iconSize: 16, label: delta > 0 ? 'Быстрее' : 'Медленнее', onTap: () => _stepBpm(app, delta)),
      );
}

/// One chord of the progression (tap on the shown chord, or «+»): another voicing, order, bars, delete, another
/// chord from the palette or any chord. `index` null = adding a chord at the end; `insertAt` — at this place.
class ProgressionChordSheet extends StatefulWidget {
  const ProgressionChordSheet({super.key, this.index, this.insertAt});
  final int? index;
  final int? insertAt;

  @override
  State<ProgressionChordSheet> createState() => _ProgressionChordSheetState();
}

class _ProgressionChordSheetState extends State<ProgressionChordSheet> {
  bool _anyChord = false;
  int _anyRoot = 0;
  String _anyType = 'maj7';

  void _apply(AppModel app, ProgressionChord chord) {
    final p = app.fretboard.progression;
    if (widget.insertAt != null) {
      p.insertChord(chord, widget.insertAt!);
    } else if (widget.index != null) {
      p.replaceChord(widget.index!, chord);
    } else {
      p.addChord(chord);
    }
    app.sheet = null;
  }

  int _bar(ProgressionController p, int index) {
    var bar = 1;
    final chords = p.chords;
    for (var i = 0; i < index && i < chords.length; i++) {
      bar += p.barsPerChord ?? chords[i].bars;
    }
    return bar;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.fretboard.progression;
    final index = widget.index;
    final chords = p.chords;
    final chord = index != null && index < chords.length ? chords[index] : null;
    final voiced = index != null && index < p.voiced.length ? p.voiced[index] : null;
    final title = voiced != null
        ? 'Такт ${_bar(p, index!)} · ${Typo.compactChordName(voiced.letterName)}'
        : (widget.insertAt != null ? 'Вставить аккорд' : 'Добавить аккорд');
    final children = <Widget>[];
    if (widget.insertAt == null && index != null && chord != null) {
      final alternatives = p.alternatives(index);
      if (alternatives.isNotEmpty) {
        children.addAll([
          SwiftText('Расположение · ${alternatives.length}', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final v in alternatives) ...[
                Pressable(
                  onTap: () => p.chooseVoicing(v, index),
                  child: ShapeBox(
                    shape: const SwiftShape.rounded(14, continuous: true),
                    fills: [voiced?.voicing == v ? SwiftFill(TruverColors.textPrimary.withValues(alpha: 0.12)) : const SwiftFill.gradient(TruverGradients.cardFill)],
                    strokes: [SwiftStroke(voiced?.voicing == v ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true)],
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 64, height: 72, child: Center(child: ChordDiagram(voicing: v, courses: app.courseCount))),
                        const SizedBox(height: 4),
                        Text('${v.usesOpenStrings && v.lowestFret <= 4 ? 'откр.' : 'лад ${v.lowestFret}'} · ${v.notes.length} стр.',
                            style: Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ]);
      }
      final count = chords.length;
      children.addAll([
        Card(children: [
          CardRow(
            title: 'Порядок',
            subtitle: 'или удерживайте аккорд в ленте и тяните',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Opacity(
                opacity: index == 0 ? 0.35 : 1,
                child: RoundIconButton(
                  icon: AppIcon.chevronLeft,
                  size: 36,
                  iconSize: 14,
                  label: 'Раньше',
                  enabled: index > 0,
                  onTap: () {
                    p.moveChord(index, index - 1);
                    app.sheet = AppSheet('progressionChord', index - 1);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Opacity(
                opacity: index + 1 >= count ? 0.35 : 1,
                child: RoundIconButton(
                  icon: AppIcon.chevronRight,
                  size: 36,
                  iconSize: 14,
                  label: 'Позже',
                  enabled: index + 1 < count,
                  onTap: () {
                    p.moveChord(index, index + 1);
                    app.sheet = AppSheet('progressionChord', index + 1);
                  },
                ),
              ),
            ]),
          ),
          CardRow(
            title: 'Вставить аккорд',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Pressable(onTap: () => app.sheet = AppSheet('progressionInsert', index), child: const Chip(text: 'перед')),
              const SizedBox(width: 6),
              Pressable(onTap: () => app.sheet = AppSheet('progressionInsert', index + 1), child: const Chip(text: 'после')),
            ]),
          ),
          CardRow(
            title: 'Тактов',
            subtitle: 'сколько звучит этот аккорд',
            trailing: ValueStepper(
              value: '${chord.bars}',
              canDecrement: chord.bars > 1,
              canIncrement: chord.bars < 8,
              decrement: () => p.setBars(index, chord.bars - 1),
              increment: () => p.setBars(index, chord.bars + 1),
            ),
          ),
          Opacity(
            opacity: count <= 1 ? 0.4 : 1,
            child: Pressable(
              scale: 1,
              enabled: count > 1,
              onTap: () {
                p.removeChord(index);
                app.sheet = null;
              },
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: TruverColors.danger),
                child: const CardRow(
                  title: 'Убрать из прогрессии',
                  showsDivider: false,
                  trailing: AppIconView(AppIcon.trash, size: 18, color: TruverColors.danger),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
      ]);
    }
    children.addAll([
      SwiftText(index == null || widget.insertAt != null ? 'Какой аккорд' : 'Заменить на', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
      const SizedBox(height: 16),
      Segments<bool>(options: const [(false, 'Из тональности'), (true, 'Любой аккорд')], selection: _anyChord, onChanged: (v) => setState(() => _anyChord = v)),
      const SizedBox(height: 16),
    ]);
    if (_anyChord) {
      children.add(_anyChordPicker(app));
    } else {
      for (final (groupTitle, numerals) in ProgressionController.palette) {
        final items = p.paletteChords(numerals);
        children.addAll([
          SwiftText(groupTitle, style: Typo.inter(12, TypoWeight.medium, TruverColors.textSecondary)),
          const SizedBox(height: 8),
          for (var row = 0; row * 4 < items.length; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(children: [
              for (var col = 0; col < 4; col++) ...[
                if (col > 0) const SizedBox(width: 6),
                Expanded(
                  child: row * 4 + col < items.length
                      ? () {
                          final it = items[row * 4 + col];
                          final selected = chord != null &&
                              chord.degree == it.chord.degree &&
                              chord.accidental == it.chord.accidental &&
                              chord.chordId == it.chord.chordId;
                          return Pressable(
                            onTap: () => _apply(app, it.chord),
                            child: ShapeBox(
                              shape: const SwiftShape.rounded(12, continuous: true),
                              fills: [selected ? SwiftFill(TruverColors.textPrimary.withValues(alpha: 0.12)) : const SwiftFill.gradient(TruverGradients.cardFill)],
                              strokes: [SwiftStroke(selected ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true)],
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 48, minWidth: double.infinity),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  FitText(
                                    child: notesText(Typo.compactChordName(it.name), Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary),
                                        maxLines: 1),
                                  ),
                                  const SizedBox(height: 1),
                                  notesText(it.numeral, Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary)),
                                ]),
                              ),
                            ),
                          );
                        }()
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
          ],
          const SizedBox(height: 16),
        ]);
      }
    }
    return DesignSheet(
      title: title,
      height: 784,
      close: () => app.sheet = null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  /// Any root × any type of the library (TH-3b), named at once on the button.
  Widget _anyChordPicker(AppModel app) {
    final p = app.fretboard.progression;
    final names = spellings(app, [for (var pc = 0; pc < 12; pc++) (pc, const [1, 3, 8, 10].contains(pc))]);
    final library = FretLibrary.load(app);
    final root = _anyRoot < names.length ? names[_anyRoot].name : const {'letter': 0, 'accidental': 0};
    final any = p.anyChord(root, _anyType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 6),
          Row(children: [
            for (var col = 0; col < 6; col++) ...[
              if (col > 0) const SizedBox(width: 6),
              Expanded(
                child: () {
                  final pc = row * 6 + col;
                  final selected = _anyRoot == pc;
                  return Pressable(
                    onTap: () => setState(() => _anyRoot = pc),
                    child: SizedBox(
                      height: 40,
                      child: ShapeBox(
                        shape: const SwiftShape.rounded(12, continuous: true),
                        fills: [SwiftFill(selected ? TruverColors.textPrimary.withValues(alpha: 0.12) : TruverColors.white(0.04))],
                        strokes: [SwiftStroke(selected ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true)],
                        child: Center(
                          child: Text.rich(Typo.notes(pc < names.length ? names[pc].text : '', Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary))),
                        ),
                      ),
                    ),
                  );
                }(),
              ),
            ],
          ]),
        ],
        const SizedBox(height: 10),
        FlowLayout(children: [
          for (final c in library.chords)
            Pressable(
              onTap: () => setState(() => _anyType = c.id),
              child: Chip(text: c.chipName, style: _anyType == c.id ? ChipStyle.emphasized : ChipStyle.muted),
            ),
        ]),
        const SizedBox(height: 10),
        if (any != null) SheetButton(title: 'Поставить ${Typo.compactChordName(any.name)}', onTap: () => _apply(app, any.chord)),
      ],
    );
  }
}

/// «Ритм» (FB-24): bars per chord, stroke pattern, labels, loop, click; the tempo is the metronome's.
class FretProgressionSheet extends StatelessWidget {
  const FretProgressionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.fretboard.progression;
    final caption = Typo.caption.copyWith(color: TruverColors.textTertiary);
    return DesignSheet(
      title: 'Ритм',
      height: 610,
      close: () => app.sheet = null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwiftText('Тактов на аккорд', style: caption),
          const SizedBox(height: 8),
          Segments<int>(
            options: const [(0, 'Как в схеме'), (1, '1'), (2, '2'), (4, '4')],
            selection: p.barsPerChord ?? 0,
            onChanged: (v) => p.barsPerChord = v == 0 ? null : v,
          ),
          const SizedBox(height: 16),
          SwiftText('Удар', style: caption),
          const SizedBox(height: 8),
          Segments<StrumRhythm>(
            options: const [(StrumRhythm.perBar, 'На такт'), (StrumRhythm.perBeat, 'На долю'), (StrumRhythm.downUpEighths, 'Вниз-вверх')],
            selection: p.rhythm,
            onChanged: (v) => p.rhythm = v,
          ),
          const SizedBox(height: 16),
          SwiftText('Подписи на грифе', style: caption),
          const SizedBox(height: 8),
          Segments<bool>(options: const [(false, 'Ноты'), (true, 'Ступени')], selection: p.showsDegrees, onChanged: (v) => p.showsDegrees = v),
          const SizedBox(height: 16),
          Card(children: [
            CardRow(title: 'По кругу', trailing: ToggleSwitch(isOn: p.loop, label: 'По кругу', onChanged: (v) => p.loop = v)),
            CardRow(
              title: 'Щелчок метронома',
              subtitle: 'с отсчётом в такт',
              trailing: ToggleSwitch(isOn: p.click, label: 'Щелчок метронома', onChanged: (v) => p.click = v),
            ),
            CardRow(
              title: 'Темп',
              subtitle: 'общий с метрономом',
              showsDivider: false,
              trailing: Text('${_bpm(app).round()} BPM · ${_meterInt(app, 'numerator')}/${_meterInt(app, 'denominator')}'),
            ),
          ]),
        ],
      ),
    );
  }
}

// MARK: Progression sheets (canvas 2026-11-25)

/// Library templates as the sheets name them: the numerals and the style.
class ProgressionTemplateInfo {
  static const order = [
    'jazz-251', 'fifties', 'andalusian', 'pop', 'sad-pop', 'three', 'jazz-1625', 'minor-251', 'blues', //
    'epic-minor', 'aeolian', 'phrygian', 'power',
  ];
  static const info = {
    'pop': ('I–V–vi–IV', 'поп'),
    'fifties': ('I–vi–IV–V', '50-е'),
    'sad-pop': ('vi–IV–I–V', 'поп'),
    'three': ('I–IV–V', 'блюз, рок'),
    'jazz-251': ('ii–V–I', 'джаз'),
    'jazz-1625': ('I–vi–ii–V', 'джаз'),
    'minor-251': ('iiø–V–i', 'джаз, минор'),
    'blues': ('I–IV–V · 12 тактов', 'блюз'),
    'andalusian': ('i–♭VII–♭VI–V', 'андалузская'),
    'epic-minor': ('i–♭VI–♭III–♭VII', 'эпический минор'),
    'aeolian': ('i–♭VI–♭VII–i', 'минор'),
    'phrygian': ('i–♭II', 'фригийский'),
    'power': ('I5–♭VI5–♭VII5', 'пауэр-аккорды'),
  };
}

/// «Прогрессии» (canvas «Прогрессии», top 180): «Мои прогрессии» with the tempo and a check on the open one,
/// «Шаблоны · от выбранной ноты», «Новая прогрессия».
class FretProgressionsSheet extends StatelessWidget {
  const FretProgressionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final p = fretboard.progression;
    final templateIds = {for (final t in p.templates) t.id};
    return DesignSheet(
      title: 'Прогрессии',
      height: 664,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: SheetButton(
            title: 'Новая прогрессия',
            onTap: () {
              final first = p.chordsIn(p.key, [p.isMinor ? 'i' : 'I']);
              if (first.isNotEmpty) p.useChords([first.first.chord], p.key);
              app.sheet = const AppSheet('progressionChord');
            },
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.saved.isNotEmpty) ...[
            const SectionCaption(text: 'Мои прогрессии'),
            Card(children: [
              for (final item in p.saved)
                Pressable(
                  scale: 1,
                  onTap: () {
                    p.open(item);
                    if (item.bpm != null) fretboard.bpm = item.bpm!.toDouble();
                    app.sheet = null;
                  },
                  child: _ProgressionListRow(
                    title: item.name,
                    subtitle: item.note ?? '${item.chords.length} ${ruPlural(item.chords.length, 'аккорд', 'аккорда', 'аккордов')}',
                    tempo: item.bpm == null ? null : '♩=${item.bpm}',
                    checked: p.activeSaved?.id == item.id,
                  ),
                ),
            ]),
            const SizedBox(height: 12),
          ],
          const SectionCaption(text: 'Шаблоны · от выбранной ноты'),
          Card(children: [
            for (final id in ProgressionTemplateInfo.order)
              if (ProgressionTemplateInfo.info[id] != null && templateIds.contains(id))
                Pressable(
                  scale: 1,
                  onTap: () {
                    p.templateId = id;
                    app.sheet = null;
                  },
                  child: _ProgressionListRow(
                    title: ProgressionTemplateInfo.info[id]!.$1,
                    subtitle: ProgressionTemplateInfo.info[id]!.$2,
                    checked: p.activeSaved == null && !p.isCustom && p.templateId == id,
                  ),
                ),
          ]),
        ],
      ),
    );
  }
}

/// Row of «Прогрессии» (canvas: 60 pt + border, padding 0 16, gap 12; title 15 primary, subtitle 12; «♩=92» 15
/// secondary; a 20 pt check or its place).
class _ProgressionListRow extends StatelessWidget {
  const _ProgressionListRow({required this.title, required this.subtitle, this.tempo, required this.checked});
  final String title;
  final String subtitle;
  final String? tempo;
  final bool checked;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BottomHairline(),
        child: SizedBox(
          height: 61,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwiftText.rich(Typo.notes(title, Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)), maxLines: 1),
                    const SizedBox(height: 2),
                    SwiftText.rich(Typo.notes(subtitle, Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)), maxLines: 1),
                  ],
                ),
              ),
              if (tempo != null) ...[
                const SizedBox(width: 12),
                SwiftText(tempo!, style: Typo.inter(15, TypoWeight.regular, TruverColors.textSecondary)),
              ],
              const SizedBox(width: 12),
              SizedBox(
                width: 20,
                height: 20,
                child: checked ? const AppIconView(AppIcon.check, size: 20, lineWidth: 2, color: TruverColors.textPrimary) : null,
              ),
            ]),
          ),
        ),
      );
}

/// «Прогрессия от A» (canvas «Нота → прогрессия», top 300): major or minor from the pressed note, common
/// progressions with their chords; «Показать на грифе» opens «Прогрессия» from that place.
class ProgressionFromNoteSheet extends StatefulWidget {
  const ProgressionFromNoteSheet({super.key, required this.spot});
  final NeckSpot spot;

  static const major = [
    ('I V vi IV', 'I – V – vi – IV · поп'),
    ('I IV V', 'I – IV – V · блюз, рок'),
    ('ii V I', 'ii – V – I · джаз'),
    ('vi IV I V', 'vi – IV – I – V'),
  ];
  static const minorList = [
    ('i ♭VI ♭III ♭VII', 'i – VI – III – VII · рок-баллада'),
    ('i iv v', 'i – iv – v · минор'),
    ('i ♭VII ♭VI V', 'i – VII – VI – V · андалузская'),
    ('ii° V i', 'ii° – V – i · джаз'),
  ];

  @override
  State<ProgressionFromNoteSheet> createState() => _ProgressionFromNoteSheetState();
}

class _ProgressionFromNoteSheetState extends State<ProgressionFromNoteSheet> {
  bool _minor = false;
  int _picked = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.fretboard.progression;
    final root = p.spotKey(widget.spot);
    final rootName = root == null ? '' : app.noteName(root);
    final list = _minor ? ProgressionFromNoteSheet.minorList : ProgressionFromNoteSheet.major;
    String names(String numerals) =>
        root == null ? '' : [for (final c in p.chordsIn(root, numerals.split(' '))) Typo.compactChordName(c.name)].join(' · ');
    return DesignSheet(
      title: 'Прогрессия от $rootName',
      height: 544,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: SheetButton(
            title: 'Показать на грифе',
            onTap: () {
              if (root == null) return;
              final chords = [for (final c in p.chordsIn(root, list[_picked].$1.split(' '))) c.chord];
              p.useChords(chords, root);
              app.fretboard.mode = FretMode.progression;
              p.start(widget.spot);
              app.sheet = null;
            },
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Segments<bool>(
            options: [(false, '$rootName мажор'), (true, '$rootName минор')],
            selection: _minor,
            onChanged: (v) => setState(() {
              _minor = v;
              _picked = 0;
            }),
          ),
          const SizedBox(height: 12),
          SectionCaption(text: 'Прогрессии от $rootName'),
          Card(children: [
            for (var i = 0; i < list.length; i++)
              Pressable(
                scale: 1,
                selected: _picked == i,
                onTap: () => setState(() => _picked = i),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: const BottomHairline(),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 59),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 14),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwiftText.rich(
                                Typo.notes(names(list[i].$1),
                                    Typo.inter(15, _picked == i ? TypoWeight.semibold : TypoWeight.regular, TruverColors.textPrimary)),
                                maxLines: 1,
                              ),
                              const SizedBox(height: 2),
                              SwiftText.rich(Typo.notes(list[i].$2, Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)), maxLines: 1),
                            ],
                          ),
                        ),
                        if (_picked == i) ...[
                          const SizedBox(width: 12),
                          const AppIconView(AppIcon.check, size: 18, lineWidth: 2, color: TruverColors.textPrimary),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

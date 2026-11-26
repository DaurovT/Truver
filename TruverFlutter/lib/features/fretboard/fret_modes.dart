/// Port of Truver/Sources/Features/Fretboard/FretModes.swift
///
/// FB-26 «Гамма · Аккорд · Поиск», FB-9 chord library, FB-10 search, FB-21 chords from a note, FB-25 scale from a
/// note, the note menu (canvas «v1.x · P1»), the path sheet.
library;

import 'dart:math' as math;

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
import 'fret_menu.dart';
import 'fretboard_controller.dart';
import 'fretboard_screen.dart';

dynamic coreCall(AppModel app, String method, Map<String, dynamic> params) {
  try {
    return app.core?.call(method, params);
  } catch (_) {
    return null;
  }
}

/// Simple spellings of pitch classes in the app's notation: `(name JSON, text)`.
List<NamedNote> spellings(AppModel app, List<(int, bool)> items) {
  final r = coreCall(app, 'fretboard.spellings', {
    'items': [for (final (pc, flats) in items) {'pc': pc, 'flats': flats}],
  });
  return [for (final m in (r as List? ?? const [])) NamedNote(Map<String, dynamic>.from(m as Map))];
}

/// `Typo.notes(text, size:…)` stacked with SwiftUI line boxes (the style carries the size for [SwiftText]).
SwiftText notesText(String text, TextStyle style, {TextAlign? textAlign, int? maxLines, double lineSpacing = 0}) =>
    SwiftText.rich(Typo.notes(text, style), style: style, textAlign: textAlign, maxLines: maxLines, lineSpacing: lineSpacing);

/// A 30 pt capsule chip with a selected state (chord types, inversions).
class SelectChip extends StatelessWidget {
  const SelectChip({super.key, required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        selected: selected,
        onTap: onTap,
        child: SizedBox(
          height: 30,
          child: ShapeBox(
            shape: SwiftShape.capsule,
            fills: [SwiftFill(selected ? TruverColors.textPrimary.withValues(alpha: 0.12) : TruverColors.fill)],
            strokes: [SwiftStroke(selected ? TruverColors.textPrimary.withValues(alpha: 0.6) : TruverColors.hairlineStrong, inside: true)],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text.rich(
                  Typo.notes(text, Typo.inter(12, TypoWeight.medium, selected ? TruverColors.textPrimary : TruverColors.textSecondary)),
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ),
      );
}

/// Mode switcher under the header (canvas: 34 pt segments in a 20 pt-radius tray).
class FretModeSwitcher extends StatelessWidget {
  const FretModeSwitcher({super.key, required this.mode, required this.onChanged});
  final FretMode mode;
  final ValueChanged<FretMode> onChanged;

  @override
  Widget build(BuildContext context) => ShapeBox(
        shape: const SwiftShape.rounded(20, continuous: true),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              for (final (value, title) in const [
                (FretMode.scale, 'Гамма'),
                (FretMode.chord, 'Аккорд'),
                (FretMode.search, 'Поиск'),
                (FretMode.progression, 'Прогрессия'),
              ])
                Expanded(
                  child: Pressable(
                    scale: 1,
                    selected: value == mode,
                    onTap: () => onChanged(value),
                    child: ShapeBox(
                      shape: SwiftShape.capsule,
                      fills: [SwiftFill(value == mode ? TruverColors.accent : const Color(0x00000000))],
                      child: SizedBox(
                        height: 34,
                        child: Center(
                          child: FitText(
                            child: Text(title,
                                maxLines: 1,
                                style: (value == mode ? Typo.segmentSelected : Typo.segment)
                                    .copyWith(color: value == mode ? TruverColors.background : TruverColors.textSecondary)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Chord row: root «A ▾», type chips (m, m7, 7, maj7 …), library button.
class ChordPickerRow extends StatelessWidget {
  const ChordPickerRow({super.key, required this.openLibrary});
  final VoidCallback openLibrary;

  static const quickTypes = ['maj', 'm', '7', 'm7', 'maj7', 'sus4', 'm7b5', 'dim', 'add9', '9'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final library = FretLibrary.load(app);
    final ids = [...quickTypes, ...app.settings.customChords.map((c) => c['id'] as String? ?? '')];
    return Row(
      children: [
        Builder(
          builder: (context) => Pressable(
            onTap: () {
              final names = spellings(app, [for (var pc = 0; pc < 12; pc++) (pc, const [1, 3, 8, 10].contains(pc) && pc != 1)]);
              showFretMenu(context, [
                for (final n in names)
                  FretMenuItem(n.text, () {
                    fretboard.chordAnchor = null;
                    fretboard.chordRoot = n.name;
                  }),
              ]);
            },
            child: SizedBox(
              height: 36,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text.rich(Typo.notes(fretboard.chordData?.rootText ?? '', Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary))),
                    const SizedBox(width: 4),
                    const AppIconView(AppIcon.chevronDown, size: 12, color: TruverColors.textTertiary),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final id in ids)
                  if (library.chords.where((c) => c.id == id).firstOrNull case final chord?) ...[
                    SelectChip(text: chord.chipName, selected: fretboard.chordId == id, onTap: () => fretboard.chordId = id),
                    const SizedBox(width: 6),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        RoundIconButton(icon: AppIcon.rename, size: 44, label: 'Все аккорды', onTap: openLibrary),
      ],
    );
  }
}

/// Inversions «Am7 · Am7/C · Am7/G» and «Гаммы ›».
class ChordInversionRow extends StatelessWidget {
  const ChordInversionRow({super.key, this.showsLabels = false, required this.showScales});
  final bool showsLabels;
  final VoidCallback showScales;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final tones = fretboard.chordData?.tones ?? const <ChordTone>[];
    final labelTitle = switch (fretboard.chordLabels) {
      LabelMode.degrees => 'Ступени',
      LabelMode.fingers => 'Пальцы',
      _ => 'Ноты',
    };
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < math.min(4, tones.length); i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    () {
                      final bass = i == 0 ? null : tones[i].pc;
                      return SelectChip(
                        text: fretboard.chordName(bass: bass),
                        selected: fretboard.chordBass == bass,
                        onTap: () => fretboard.chordBass = bass,
                      );
                    }(),
                  ],
                ],
              ),
            ),
          ),
          if (showsLabels) ...[
            const SizedBox(width: 6),
            Pressable(
              label: 'Подписи: $labelTitle',
              onTap: () => fretboard.chordLabels = switch (fretboard.chordLabels) {
                LabelMode.notes => LabelMode.degrees,
                LabelMode.degrees => LabelMode.fingers,
                _ => LabelMode.notes,
              },
              child: Chip(text: labelTitle),
            ),
          ],
          const SizedBox(width: 6),
          Pressable(scale: 1, onTap: showScales, child: Text('Гаммы ›', style: Typo.chip.copyWith(color: TruverColors.textSecondary))),
        ],
      ),
    );
  }
}

/// «‹ 1 из 14 · от 5-го лада › ♪ ▶ Сыграть».
class ChordNavigationRow extends StatelessWidget {
  const ChordNavigationRow({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final empty = fretboard.voicings.isEmpty;
    final style = Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary);
    return Row(
      children: [
        RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Предыдущее расположение', onTap: () => fretboard.stepVoicing(-1)),
        const SizedBox(width: 8),
        Expanded(
          child: FitText(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: empty
                  ? [SwiftText('Расположений нет', style: style)]
                  : [
                      SwiftText.rich(style: style, TextSpan(style: style, children: [
                        TextSpan(text: '${fretboard.voicingIndex + 1}', style: Typo.inter(12, TypoWeight.semibold, TruverColors.textPrimary)),
                        TextSpan(text: ' из ${fretboard.voicings.length}'),
                      ])),
                      SwiftText(fretboard.currentVoicing == null ? '' : fretboard.voicingTitle(fretboard.currentVoicing!), style: style),
                    ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        RoundIconButton(icon: AppIcon.chevronRight, size: 44, label: 'Следующее расположение', onTap: () => fretboard.stepVoicing(1)),
        const SizedBox(width: 8),
        Opacity(
          opacity: empty ? 0.4 : 1,
          child: RoundIconButton(icon: AppIcon.music, size: 44, label: 'Арпеджио', enabled: !empty, onTap: () => fretboard.playVoicing(null, true)),
        ),
        const SizedBox(width: 8),
        Opacity(
          opacity: empty ? 0.4 : 1,
          child: Pressable(
            enabled: !empty,
            onTap: () => fretboard.playVoicing(),
            child: SizedBox(
              height: 52,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                shadows: [SwiftShadow(TruverColors.black(0.35), 9, y: 6)],
                fills: const [SwiftFill(TruverColors.textPrimary)],
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 18),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const AppIconView(AppIcon.play, size: 18, color: TruverColors.background),
                    const SizedBox(width: 8),
                    Text('Сыграть', style: Typo.inter(16, TypoWeight.semibold, TruverColors.background)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// «Поиск»: prompt + «Сбросить».
class SearchPromptRow extends StatelessWidget {
  const SearchPromptRow({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final empty = app.fretboard.marked.isEmpty;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: Text('Отметьте ноты на грифе', style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary))),
          Opacity(
            opacity: empty ? 0.4 : 1,
            child: Pressable(
              enabled: !empty,
              onTap: () => app.fretboard.marked = [],
              child: const Chip(text: 'Сбросить', icon: AppIcon.refresh, style: ChipStyle.muted),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _infoCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => ShapeBox(
      shape: const SwiftShape.rounded(18, continuous: true),
      fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
      strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
      child: Padding(padding: padding, child: child),
    );

/// Result card (canvas: «Am7 · или C6/A · 4 ноты: A C E G»), or «Отметьте хотя бы 3 ноты», or «Ничего не найдено».
class SearchResultCard extends StatelessWidget {
  const SearchResultCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final search = fretboard.search;
    final pitches = search.pitches;
    final names = pitches.map((p) => p.plain).toList();
    if (pitches.length < 3) {
      return SizedBox(
        width: double.infinity,
        child: _infoCard(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwiftText('Отметьте хотя бы 3 ноты', style: Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
            const SizedBox(height: 4),
            SwiftText('Тап по ладу — отметить, повторный — снять', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
          ]),
        ),
      );
    }
    final best = search.chords.firstOrNull;
    if (best != null) {
      final alt = search.chords.length > 1 ? search.chords[1] : null;
      final detail = '${alt == null ? '' : 'или ${Typo.compactChordName(alt.name)} · '}${pitches.length} ${ruPlural(pitches.length, 'нота', 'ноты', 'нот')}: ${names.join(' ')}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: _infoCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text.rich(Typo.notes(Typo.compactChordName(best.name), Typo.inter(22, TypoWeight.semibold, TruverColors.textPrimary))),
                  const SizedBox(width: 10),
                  Flexible(
                    child: FitText(
                      child: Text.rich(Typo.notes(detail, Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary)), maxLines: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Pressable(onTap: () => fretboard.openInChordMode(best), child: const Chip(text: 'Открыть в «Аккорде»')),
            const SizedBox(width: 8),
            Pressable(onTap: () => app.sheet = const AppSheet('searchResults'), child: const Chip(text: 'Гаммы с этими нотами ›')),
          ]),
        ],
      );
    }
    final nearest = search.nearest;
    final hint = nearest == null
        ? 'Такого аккорда нет в библиотеке · ${names.join(' ')}'
        : 'Такого аккорда нет в библиотеке. Ближайшее: ${Typo.compactChordName(nearest.match.name)} — ${nearest.matched} ${ruPlural(nearest.matched, 'нота', 'ноты', 'нот')} из ${search.distinct}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: _infoCard(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwiftText('Ничего не найдено', style: Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
              const SizedBox(height: 4),
              notesText(hint, Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary), textAlign: TextAlign.center),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          if (nearest != null) ...[
            Pressable(onTap: () => fretboard.openInChordMode(nearest.match), child: const Chip(text: 'Показать ближайшее')),
            const SizedBox(width: 8),
          ],
          Pressable(onTap: () => app.sheet = const AppSheet('searchResults'), child: const Chip(text: 'Гаммы с этими нотами ›')),
        ]),
      ],
    );
  }
}

/// Note menu (long press): «A2 · 6-я струна, 5-й лад · ступень 4» and five actions (canvas «меню ноты»).
class NoteMenu extends StatelessWidget {
  const NoteMenu({super.key, required this.spot, required this.close});
  final NeckSpot spot;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final info = fretboard.noteInfo(spot);
    final string = app.courseCount - spot.course;
    final degree = info?.degreeLabel;
    final hidden = fretboard.isHidden(spot);
    return SizedBox(
      width: 232,
      child: ShapeBox(
        shape: const SwiftShape.rounded(14, continuous: true),
        shadows: [SwiftShadow(TruverColors.black(0.7), 25, y: 20)],
        fills: [SwiftFill(const Color(0xFF282A2F).withValues(alpha: 0.98))],
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: notesText(
                  '${info?.chroma ?? ''} · $string-я струна, ${spot.fret}-й лад${degree == null ? '' : ' · ступень $degree'}',
                  Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
            ),
            _item(AppIcon.fretboard, 'Гамма от этой ноты', () => app.sheet = AppSheet('scaleFromNote', spot)),
            _item(AppIcon.chevronRight, 'Путь отсюда', () => fretboard.startPath(spot)),
            _item(AppIcon.music, 'Аккорды от этой ноты', () => app.sheet = AppSheet('chordsFromNote', spot)),
            _item(AppIcon.list, 'Прогрессия отсюда', () => fretboard.progression.start(spot)),
            if (fretboard.mode == FretMode.scale)
              _item(
                AppIcon.close,
                hidden ? 'Показать ноту' : (degree == null ? 'Добавить ноту' : 'Скрыть ноту'),
                () => fretboard.toggle(spot.course, spot.fret),
                danger: degree != null && !hidden,
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(AppIcon icon, String title, VoidCallback action, {bool danger = false}) => Pressable(
        scale: 1,
        onTap: () {
          close();
          action();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: TruverColors.white(0.06)))),
          child: SizedBox(
            height: 41,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                AppIconView(icon, size: 16, color: danger ? TruverColors.danger : TruverColors.textBody),
                const SizedBox(width: 10),
                Flexible(
                  child: FitText(
                    child: Text(title, maxLines: 1, style: Typo.inter(15, TypoWeight.regular, danger ? TruverColors.danger : TruverColors.textPrimary)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// A small chord box (canvas list rows): strings vertical, 5 frets, dots, × and ○ above, the first fret number.
class ChordDiagram extends StatelessWidget {
  const ChordDiagram({super.key, required this.voicing, required this.courses});
  final ChordVoicing voicing;
  final int courses;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 58, height: 62, child: CustomPaint(painter: _ChordDiagramPainter(voicing, courses)));
}

class _ChordDiagramPainter extends CustomPainter {
  _ChordDiagramPainter(this.voicing, this.courses);
  final ChordVoicing voicing;
  final int courses;

  void _text(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: Typo.fixed(7, TypoWeight.regular, color)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0, left = 8.0;
    final w = size.width - left - 2, h = size.height - top - 2;
    final fretted = voicing.notes.map((n) => n.fret).where((f) => f > 0).toList();
    final maxF = fretted.isEmpty ? 0 : fretted.reduce(math.max);
    final minF = fretted.isEmpty ? 1 : fretted.reduce(math.min);
    final first = voicing.usesOpenStrings && maxF <= 5 ? 1 : math.max(1, minF);
    final dx = courses > 1 ? w / (courses - 1) : 0.0, dy = h / 5;
    final line = Paint()
      ..color = TruverColors.white(0.35)
      ..style = PaintingStyle.stroke;
    for (var c = 0; c < courses; c++) {
      canvas.drawLine(Offset(left + c * dx, top), Offset(left + c * dx, top + h), line..strokeWidth = 0.8);
    }
    for (var r = 0; r <= 5; r++) {
      canvas.drawLine(Offset(left, top + r * dy), Offset(left + w, top + r * dy), line..strokeWidth = r == 0 && first == 1 ? 2 : 0.8);
    }
    if (first > 1) _text(canvas, '$first', Offset(2, top + dy / 2), TruverColors.textTertiary);
    for (var c = 0; c < voicing.frets.length; c++) {
      final x = left + c * dx;
      final fret = voicing.frets[c];
      if (fret == null) {
        _text(canvas, '×', Offset(x, 3), TruverColors.textTertiary);
        continue;
      }
      if (fret == 0) {
        canvas.drawOval(Rect.fromLTWH(x - 2, 1, 4, 4), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = TruverColors.textSecondary);
      } else {
        final row = (fret - first) + 0.5;
        final r = math.min(3.2, dx * 0.42);
        canvas.drawCircle(Offset(x, top + row * dy), r, Paint()..color = TruverColors.textPrimary);
      }
    }
  }

  @override
  bool shouldRepaint(_ChordDiagramPainter old) => old.voicing != voicing || old.courses != courses;
}

/// Chord box of the canvas lists (98 × 96, viewBox −6 0 98 96): strings 8…84, five frets 14.8 apart from y 14 to 88
/// (the nut 3 pt white 80 % from the first fret, else a 1 pt line), «×» 8 pt above muted strings, an open ring
/// r 2.6, dots r 4.4 #f3efe6, the first fret number at the left (8 pt).
class ChordBox extends StatelessWidget {
  const ChordBox({super.key, required this.voicing, required this.courses});
  final ChordVoicing voicing;
  final int courses;

  static int firstFret(ChordVoicing v) {
    final fretted = v.notes.map((n) => n.fret).where((f) => f > 0).toList();
    final maxF = fretted.isEmpty ? 0 : fretted.reduce(math.max);
    final minF = fretted.isEmpty ? 1 : fretted.reduce(math.min);
    return v.usesOpenStrings && maxF <= 5 ? 1 : math.max(1, minF);
  }

  @override
  Widget build(BuildContext context) => SizedBox(width: 98, height: 96, child: CustomPaint(painter: _ChordBoxPainter(voicing, courses)));
}

class _ChordBoxPainter extends CustomPainter {
  _ChordBoxPainter(this.voicing, this.courses);
  final ChordVoicing voicing;
  final int courses;

  /// SVG text: `x` is the anchor (middle or start), `y` the baseline.
  void _text(Canvas canvas, String text, double x, double baseline, {bool middle = true}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: Typo.fixed(8, TypoWeight.regular, TruverColors.textTertiary)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(canvas, Offset(middle ? x - tp.width / 2 : x, baseline - ascent));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const ox = 6.0, left = 8.0, right = 84.0, top = 14.0, step = 14.8;
    final first = ChordBox.firstFret(voicing);
    final dx = courses > 1 ? (right - left) / (courses - 1) : 0.0;
    double x(int c) => ox + left + c * dx;
    final line = Paint()..style = PaintingStyle.stroke;
    for (var c = 0; c < courses; c++) {
      canvas.drawLine(Offset(x(c), top), Offset(x(c), top + 5 * step), line
        ..color = TruverColors.white(0.35)
        ..strokeWidth = 1);
    }
    for (var r = 0; r <= 5; r++) {
      final nut = r == 0 && first == 1;
      final y = top + r * step;
      canvas.drawLine(Offset(ox + left, y), Offset(ox + right, y), line
        ..color = TruverColors.white(nut ? 0.8 : 0.25)
        ..strokeWidth = nut ? 3 : 1);
    }
    if (first > 1) _text(canvas, '$first', ox, 24.4, middle: false);
    for (var c = 0; c < voicing.frets.length && c < courses; c++) {
      final fret = voicing.frets[c];
      if (fret == null) {
        _text(canvas, '×', x(c), 9);
      } else if (fret == 0) {
        canvas.drawCircle(Offset(x(c), 6), 2.6, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = TruverColors.textSecondary);
      } else {
        canvas.drawCircle(Offset(x(c), top + (fret - first + 0.5) * step), 4.4, Paint()..color = const Color(0xFFF3EFE6));
      }
    }
  }

  @override
  bool shouldRepaint(_ChordBoxPainter old) => old.voicing != voicing || old.courses != courses;
}

/// Voicing row of the canvas lists («Аккорд · Am7», «Аккорды от A»): box 98 × 96, title 15 medium, subtitle 12,
/// «проще всего» on the easiest, › on the rest; padding 8 14 8 8, gap 12.
class VoicingCardRow extends StatelessWidget {
  const VoicingCardRow({super.key, required this.voicing, required this.anchored, required this.easiest, this.selected = false, required this.onTap});
  final ChordVoicing voicing;
  final bool anchored;
  final bool easiest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final card = app.fretboard.voicingCard(voicing, anchored: anchored);
    return Pressable(
      scale: 1,
      onTap: onTap,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BottomHairline(),
        child: ColoredBox(
          color: selected ? TruverColors.white(0.05) : const Color(0x00000000),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 9),
            child: Row(children: [
              ChordBox(voicing: voicing, courses: app.courseCount),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  notesText(card.title, Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
                  const SizedBox(height: 3),
                  notesText(card.subtitle, Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
                ]),
              ),
              const SizedBox(width: 12),
              if (easiest)
                const Chip(text: 'проще всего', style: ChipStyle.positive)
              else
                const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
            ]),
          ),
        ),
      ),
    );
  }
}

extension VoicingCardText on FretboardController {
  /// Title and subtitle of a voicing in the canvas lists (see `voicingCard` in FretModes.swift).
  ({String title, String subtitle}) voicingCard(ChordVoicing v, {required bool anchored}) {
    final n = app.courseCount;
    final count = v.notes.length;
    final strings = '$count ${ruPlural(count, 'струна', 'струны', 'струн')}';
    final names = v.notes.map((note) => note.plain).join(' ');
    final fingers = v.fingers == 1 ? 'один палец' : '${v.fingers} ${ruPlural(v.fingers, 'палец', 'пальца', 'пальцев')}';
    final bassString = n - v.bass.course;
    final rootBass = v.bass.pc == notePitchClass(chordRoot);
    final fretted = v.notes.map((x) => x.fret).where((f) => f > 0).toList();
    final stretch = 'растяжка ${fretted.isEmpty ? 0 : fretted.reduce(math.min)}–${fretted.isEmpty ? 0 : fretted.reduce(math.max)} лад';
    if (v.usesOpenStrings && v.lowestFret <= 4) return (title: 'Открытый', subtitle: '$names · $fingers');
    if (bassString > 6) return (title: 'С басом ${v.bass.chroma} · $strings', subtitle: v.isStretch ? stretch : '$names · $fingers');
    final barre = v.barreFret;
    if (barre != null) {
      if (count <= 4) return (title: 'Частичное баррэ · $strings', subtitle: '$names · $fingers');
      return anchored
          ? (title: 'Баррэ · $strings', subtitle: 'полный звук · баррэ на $barre-м')
          : (title: 'Баррэ на $barre-м · $strings', subtitle: rootBass ? 'тоника на $bassString-й' : '$names · $fingers');
    }
    if (anchored) return (title: 'Без баррэ · $strings', subtitle: v.isStretch ? stretch : '$names · $fingers');
    return (title: 'От ${v.lowestFret}-го лада', subtitle: '${rootBass ? 'тоника на $bassString-й' : names} · $fingers');
  }
}

/// One voicing row: diagram, «Am7 · от 5-го лада», subtitle, «удобно / растяжка».
class VoicingRow extends StatelessWidget {
  const VoicingRow({super.key, required this.voicing, required this.title, required this.selected, this.showsDivider = true, required this.onTap});
  final ChordVoicing voicing;
  final String title;
  final bool selected;
  final bool showsDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Pressable(
      scale: 1,
      onTap: onTap,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: showsDivider ? rowDivider : const BoxDecoration(),
        child: ColoredBox(
          color: selected ? TruverColors.white(0.05) : const Color(0x00000000),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 82),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                ChordDiagram(voicing: voicing, courses: app.courseCount),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    notesText(title, Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)),
                    const SizedBox(height: 2),
                    notesText(app.fretboard.voicingSubtitle(voicing), Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
                  ]),
                ),
                const SizedBox(width: 12),
                Text(voicing.isStretch ? 'растяжка' : 'удобно', style: Typo.caption.copyWith(color: TruverColors.textSecondary)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outline capsule button of the sheets' footers (54 pt).
class OutlineButton extends StatelessWidget {
  const OutlineButton({super.key, required this.title, this.icon, required this.onTap});
  final String title;
  final AppIcon? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: ShapeBox(
          shape: SwiftShape.capsule,
          fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54, minWidth: double.infinity),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[AppIconView(icon!, size: 16, color: TruverColors.textBody), const SizedBox(width: 8)],
              Text(title, style: Typo.button.copyWith(color: TruverColors.textBody)),
            ]),
          ),
        ),
      );
}

/// «Аккорды от A · 6-я, 5-й лад» (canvas: sheet over the neck): types, voicings from this place, «Сыграть ещё» /
/// «Арпеджио»; nothing fits → «Опустить 11 / 9».
class ChordsFromNoteSheet extends StatefulWidget {
  const ChordsFromNoteSheet({super.key, required this.spot});
  final NeckSpot spot;

  @override
  State<ChordsFromNoteSheet> createState() => _ChordsFromNoteSheetState();
}

class _ChordsFromNoteSheetState extends State<ChordsFromNoteSheet> {
  ChordVoicing? _picked;
  NoteInfo? _info;
  late final FretboardController _fretboard;

  @override
  void initState() {
    super.initState();
    _fretboard = AppScope.read(context).fretboard;
    _info = _fretboard.noteInfo(widget.spot);
    if (_info != null) _fretboard.beginChordsFromNote(widget.spot, _info!.majorRoot, triadId: _info!.triadId);
  }

  @override
  void dispose() {
    _fretboard.endChordsFromNote();
    super.dispose();
  }

  /// The current type (the key's chord on this degree) first, then the common ones.
  List<String> _typeIds() {
    // Canvas «Аккорды от A»: Am, A, Am7, A7, Amaj7, Asus4, Asus2, A5 — the key's chord first.
    const common = ['maj', 'm', 'm7', '7', 'maj7', 'sus4', 'sus2', '5'];
    final current = _fretboard.chordId;
    return [current, ...common.where((c) => c != current)];
  }

  static String _simpler(String id) =>
      const {'13#11': '7#11', '13': '9', 'm13': 'm9', '11': '9', 'm11': 'm9', '9': '7', 'm9': 'm7', 'maj9': 'maj7', 'maj13': 'maj7'}[id] ?? 'maj';

  void _close(AppModel app) {
    app.fretboard.chordAnchor = null;
    app.sheet = null;
  }

  void _pick(ChordVoicing? v) {
    setState(() => _picked = v);
    _fretboard.chordPreview = v;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final info = _info;
    final string = app.courseCount - widget.spot.course;
    final ids = _typeIds();
    final names = info == null
        ? const <String, String>{}
        : {
            for (final m in (coreCall(app, 'fretboard.chordNames', {'root': info.majorRoot, 'ids': ids}) as List? ?? const []))
              (m as Map)['id'] as String: m['name'] as String,
          };
    final voicings = fretboard.voicings;
    final hint = fretboard.omissionHint;
    final List<Widget> footer;
    if (voicings.isEmpty) {
      footer = [
        Expanded(
          child: hint != null
              ? OutlineButton(title: 'Опустить ступень ${hint['number']}', onTap: () => fretboard.omit(hint))
              : OutlineButton(title: 'Упростить', onTap: () => fretboard.chordId = _simpler(fretboard.chordId)),
        ),
      ];
    } else if (_picked != null) {
      footer = [
        Expanded(child: SheetButton(title: 'Сыграть ещё', icon: AppIcon.play, onTap: () => fretboard.playVoicing(_picked))),
        Expanded(child: OutlineButton(title: 'Арпеджио', icon: AppIcon.music, onTap: () => fretboard.playVoicing(_picked, true))),
      ];
    } else {
      footer = const [];
    }
    return DesignSheet(
      title: 'Аккорды от ${info?.majorRootText ?? ''} · $string-я, ${widget.spot.fret}-й лад',
      height: 552,
      close: () => _close(app),
      footer: footer.isEmpty ? null : footer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FlowLayout(children: [
              for (final id in ids)
                if (names[id] case final name?)
                  Pressable(
                    onTap: () {
                      _pick(null);
                      fretboard.chordId = id;
                    },
                    child: NoteChip(
                      text: Typo.compactChordName(name),
                      style: fretboard.chordId == id ? NoteChipStyle.selected : NoteChipStyle.plain,
                    ),
                  ),
            ]),
          ),
          const SizedBox(height: 12),
          if (voicings.isEmpty)
            _infoCard(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: ShapeBox(
                    shape: SwiftShape.circle,
                    fills: const [SwiftFill(TruverColors.fill)],
                    strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                    child: const Center(child: AppIconView(AppIcon.fretboard, size: 22, color: TruverColors.textSecondary)),
                  ),
                ),
                const SizedBox(height: 6),
                SwiftText('Расположений не найдено', textAlign: TextAlign.center, style: Typo.inter(17, TypoWeight.medium, TruverColors.textBody)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: notesText(
                        'От этого места ${fretboard.chordName()} не помещается в 4 пальца и 5 ладов${hint == null ? '' : '. Попробуйте опустить ${hint['number']}-ю ступень'}',
                        Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]),
            )
          else ...[
            const SectionCaption(text: 'От этого места'),
            Card(children: [
              for (var i = 0; i < math.min(6, voicings.length); i++)
                VoicingCardRow(
                  voicing: voicings[i],
                  anchored: true,
                  easiest: i == 0,
                  selected: _picked == voicings[i],
                  onTap: () {
                    _pick(voicings[i]);
                    fretboard.voicingIndex = i;
                    fretboard.playVoicing(voicings[i]);
                  },
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// «Гамма от A · 6-я, 5-й лад» (FB-25): scale type chips, «Все гаммы», layout, position «от этой ноты»,
/// «Построить гамму».
class ScaleFromNoteSheet extends StatefulWidget {
  const ScaleFromNoteSheet({super.key, required this.spot});
  final NeckSpot spot;

  @override
  State<ScaleFromNoteSheet> createState() => _ScaleFromNoteSheetState();
}

class _ScaleFromNoteSheetState extends State<ScaleFromNoteSheet> {
  String _scaleId = 'aeolian';
  NoteInfo? _info;
  late final FretboardController _fretboard;

  static const common = [
    ('aeolian', 'Натур. минор'),
    ('major', 'Мажор'),
    ('dorian', 'Дорийский'),
    ('phrygian-dominant', 'Фриг. доминант'),
    ('harmonic-minor', 'Гарм. минор'),
    ('minor-pentatonic', 'Минорная пентатоника'),
  ];

  @override
  void initState() {
    super.initState();
    _fretboard = AppScope.read(context).fretboard;
    _info = _fretboard.noteInfo(widget.spot);
    _fretboard.menuSpot = widget.spot;
    // The mode of the current scale from this note comes first and is preselected.
    if (_info?.modeId != null) _scaleId = _info!.modeId!;
    _fretboard.previewScale(widget.spot, _scaleId);
  }

  @override
  void dispose() {
    _fretboard.fromNotePreview = null;
    _fretboard.menuSpot = null;
    super.dispose();
  }

  void _setScale(String id) {
    setState(() => _scaleId = id);
    _fretboard.previewScale(widget.spot, id);
  }

  void _setLayout(String kind) {
    _fretboard.updateSettings((s) => s.layout = kind);
    _fretboard.previewScale(widget.spot, _scaleId);
  }

  List<(String, String)> _choices(FretLibrary library) {
    var list = [...common];
    final info = _info;
    if (info?.modeId != null) {
      list = [(info!.modeId!, '${info.modeName} · из гаммы'), ...list.where((c) => c.$1 != info.modeId)];
    }
    if (!list.any((c) => c.$1 == _scaleId)) {
      final picked = library.scales.where((s) => s.id == _scaleId).firstOrNull;
      if (picked != null) list.insert(0, (picked.id, picked.name));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final library = FretLibrary.load(app);
    final string = app.courseCount - widget.spot.course;
    final r = fretboard.fromNotePreview?.position;
    final positionHint = r == null ? 'Тоника — самая низкая нота позиции' : 'Тоника — самая низкая нота позиции, лады ${r.lo}–${r.hi}';
    final layout = fretboard.settings.layout == 'boxes' ? 'Ящики' : '3 ноты на струну';
    return DesignSheet(
      title: 'Гамма от ${_info?.plain ?? ''} · $string-я, ${widget.spot.fret}-й лад',
      height: 460,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: SheetButton(
            title: 'Построить гамму',
            onTap: () {
              fretboard.buildScale(widget.spot, _scaleId);
              app.sheet = null;
            },
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowLayout(children: [
            for (final (id, title) in _choices(library))
              if (library.scales.any((s) => s.id == id))
                Pressable(onTap: () => _setScale(id), child: Chip(text: title, style: _scaleId == id ? ChipStyle.emphasized : ChipStyle.muted)),
          ]),
          const SizedBox(height: 14),
          Card(children: [
            Builder(
              builder: (context) => Pressable(
                scale: 1,
                // Stays in this sheet: the place on the neck is not lost.
                onTap: () => showFretMenu(context, [
                  for (final s in library.scales.where((s) => !s.needsReview)) FretMenuItem(s.name, () => _setScale(s.id), checked: s.id == _scaleId),
                ]),
                child: CardRow(
                  title: 'Все гаммы',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(library.scales.where((s) => s.id == _scaleId).firstOrNull?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                  ]),
                ),
              ),
            ),
            Builder(
              builder: (context) => Pressable(
                scale: 1,
                onTap: () => showFretMenu(context, [
                  FretMenuItem('3 ноты на струну', () => _setLayout('threeNotesPerString')),
                  FretMenuItem('Ящики', () => _setLayout('boxes')),
                ]),
                child: CardRow(
                  title: 'Раскладка',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(layout),
                    const SizedBox(width: 8),
                    const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                  ]),
                ),
              ),
            ),
            CardRow(title: 'Позиция', subtitle: positionHint, showsDivider: false, trailing: const Text('от этой ноты')),
          ]),
        ],
      ),
    );
  }
}

/// «Отмечено 4 ноты» (canvas «Поиск — результаты», top 402): the marked notes, chords with their tones (missing ones
/// struck through), «точно» on an exact match; the scales that hold all the notes below.
class SearchResultsSheet extends StatelessWidget {
  const SearchResultsSheet({super.key});

  /// «Am7», «C6 / A в басу», «Am9 · без ноны».
  static String title(ChordMatch m) {
    var name = Typo.compactChordName(m.chordOnly.isEmpty ? m.name : m.chordOnly);
    final rootPc = notePitchClass(m.root);
    if (m.bass != null && m.bass != rootPc && m.bassName != null) name += ' / ${m.bassName} в басу';
    final missing = m.toneList.where((t) => t.missing).firstOrNull;
    if (missing != null) {
      final semitones = ((missing.pc - rootPc) % 12 + 12) % 12;
      final degree = switch (semitones) {
        3 || 4 => 'терции',
        6 || 7 || 8 => 'квинты',
        10 || 11 => 'септимы',
        1 || 2 => 'ноны',
        5 => 'кварты',
        _ => 'сексты',
      };
      name += ' · без $degree';
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final search = fretboard.search;
    // The marked notes once each, upwards from the bass: «A C E G».
    final sorted = [...search.pitches]..sort((a, b) => a.cents.compareTo(b.cents));
    final names = <String>[];
    if (sorted.isNotEmpty) {
      final bassPc = centsPitchClass(sorted.first.cents);
      final seen = <int>{};
      final byPc = [...sorted]..sort((a, b) => ((centsPitchClass(a.cents) - bassPc + 12) % 12).compareTo((centsPitchClass(b.cents) - bassPc + 12) % 12));
      for (final p in byPc) {
        if (seen.add(centsPitchClass(p.cents))) names.add(p.plain);
      }
    }
    final chords = search.chords.take(4).toList();
    final scales = search.scales.take(6).toList();
    return DesignSheet(
      title: 'Отмечено ${names.length} ${ruPlural(names.length, 'нота', 'ноты', 'нот')}',
      height: 442,
      close: () => app.sheet = null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            for (var i = 0; i < names.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              NoteChip(text: names[i], style: NoteChipStyle.marked),
            ],
          ]),
          const SizedBox(height: 14),
          const SectionCaption(text: 'Аккорды'),
          Card(children: [
            for (var i = 0; i < chords.length; i++)
              Pressable(
                scale: 1,
                onTap: () {
                  fretboard.openInChordMode(chords[i]);
                  app.sheet = null;
                },
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: const BottomHairline(),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 63),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 14),
                      child: Row(children: [
                        Expanded(
                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            notesText(title(chords[i]), Typo.inter(16, TypoWeight.regular, TruverColors.textPrimary), maxLines: 1),
                            const SizedBox(height: 3),
                            SwiftText.rich(
                              TextSpan(children: [
                                for (var k = 0; k < chords[i].toneList.length; k++) ...[
                                  if (k > 0) const TextSpan(text: ' '),
                                  Typo.notes(
                                    chords[i].toneList[k].name,
                                    Typo.inter(12, TypoWeight.regular, chords[i].toneList[k].missing ? TruverColors.textTertiary : TruverColors.textBody).copyWith(
                                      letterSpacing: 0.96,
                                      decoration: chords[i].toneList[k].missing ? TextDecoration.lineThrough : null,
                                      decorationColor: TruverColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ]),
                              maxLines: 1,
                            ),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        if (i == 0 && !chords[i].toneList.any((t) => t.missing))
                          const Chip(text: 'точно')
                        else
                          const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
          if (scales.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SectionCaption(text: 'Гаммы'),
            Card(children: [
              for (var i = 0; i < scales.length; i++)
                Pressable(
                  scale: 1,
                  onTap: () {
                    fretboard.updateSettings((s) {
                      s.scaleId = scales[i].scaleId;
                      s.tonic = scales[i].tonic;
                    });
                    fretboard.mode = FretMode.scale;
                    app.sheet = null;
                  },
                  child: CardRow(
                    title: scales[i].title,
                    subtitle: 'все ${names.length} ${ruPlural(names.length, 'нота', 'ноты', 'нот')} в гамме',
                    minHeight: 63,
                    trailing: const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Chord library (canvas «Аккорд — расположения»): roots, types, voicings by comfort, inversions, suitable scales.
class ChordLibraryView extends StatefulWidget {
  const ChordLibraryView({super.key, this.atScales = false, this.bottomInset = 0, required this.close});
  final bool atScales;

  /// The part of the view under the tuning pill and the tab bar (scrolled content stays reachable above them).
  final double bottomInset;
  final VoidCallback close;

  @override
  State<ChordLibraryView> createState() => _ChordLibraryViewState();
}

class _ChordLibraryViewState extends State<ChordLibraryView> {
  bool _showAllTypes = false;
  final _scalesKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.atScales) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToScales(animated: false));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToScales({bool animated = true}) {
    final ctx = _scalesKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: animated ? const Duration(milliseconds: 240) : Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final library = FretLibrary.load(app);
    const order = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
    final roots = spellings(app, [for (final pc in order) (pc, const [3, 8, 10].contains(pc))]);
    final rootPC = notePitchClass(fretboard.chordRoot);
    final userChords = library.chords.where((c) => c.isUser).toList();
    // Canvas: maj m 7 m7 maj7 dim aug sus2 sus4, then «ещё…» for the rest of the library.
    const shown = ['maj', 'm', '7', 'm7', 'maj7', 'dim', 'aug', 'sus2', 'sus4'];
    final builtIn = _showAllTypes
        ? library.chords.where((c) => !c.isUser).toList()
        : [for (final id in shown) ...library.chords.where((c) => !c.isUser && c.id == id)];
    final voicings = fretboard.voicings;
    final pcs = (fretboard.chordData?.tones ?? const <ChordTone>[]).map((t) => t.pc).toSet().toList();
    final scales = [
      for (final m in (coreCall(app, 'fretboard.scalesContaining', {'pitchClasses': pcs, 'preferredTonic': rootPC, 'limit': 6}) as List? ?? const []))
        ScaleMatch(Map<String, dynamic>.from(m as Map)),
    ];
    return Stack(
      children: [
        const Positioned.fill(child: ScreenBackground()),
        Column(
          children: [
            // Canvas «Аккорд — библиотека» (FixFretChordLibrary): back 40, «Аккорд · Am7» 17 medium, the instrument.
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 3),
              child: SizedBox(
                height: 44,
                child: Row(children: [
                  RoundIconButton(icon: AppIcon.chevronLeft, label: 'Назад', onTap: widget.close),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    notesText('Аккорд · ${fretboard.chordName()}', Typo.inter(17, TypoWeight.medium, TruverColors.textPrimary), maxLines: 1),
                    const SizedBox(height: 1),
                    notesText(app.title, Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
                  ]),
                ]),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 72 + widget.bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var row = 0; row < 2; row++) ...[
                      if (row > 0) const SizedBox(height: 6),
                      Row(children: [
                        for (var col = 0; col < 6; col++) ...[
                          if (col > 0) const SizedBox(width: 6),
                          Expanded(
                            child: row * 6 + col < roots.length
                                ? () {
                                    final pc = order[row * 6 + col];
                                    final n = roots[row * 6 + col];
                                    final selected = rootPC == pc;
                                    return Pressable(
                                      selected: selected,
                                      onTap: () {
                                        fretboard.chordAnchor = null;
                                        fretboard.chordRoot = n.name;
                                      },
                                      child: SizedBox(
                                        height: 40,
                                        child: ShapeBox(
                                          shape: const SwiftShape.rounded(10),
                                          fills: [SwiftFill(TruverColors.white(selected ? 0.1 : 0.04))],
                                          strokes: [SwiftStroke(selected ? TruverColors.selectedBorder : TruverColors.hairline, inside: true)],
                                          child: Center(child: Text.rich(Typo.notes(n.text, Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)))),
                                        ),
                                      ),
                                    );
                                  }()
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ]),
                    ],
                    const SizedBox(height: 12),
                    FlowLayout(children: [
                      // TH-8: the user's own chords first (long press — edit), then the library.
                      for (final c in userChords)
                        GestureDetector(
                          onLongPress: () => app.sheet = AppSheet('chordBuilder', c.id),
                          child: Pressable(
                            onTap: () => fretboard.chordId = c.id,
                            child: NoteChip(text: c.chipName, style: fretboard.chordId == c.id ? NoteChipStyle.selected : NoteChipStyle.plain),
                          ),
                        ),
                      for (final c in builtIn)
                        Pressable(
                          onTap: () => fretboard.chordId = c.id,
                          child: NoteChip(text: c.chipName, style: fretboard.chordId == c.id ? NoteChipStyle.selected : NoteChipStyle.plain),
                        ),
                      Pressable(
                        onTap: () => setState(() => _showAllTypes = !_showAllTypes),
                        child: NoteChip(text: _showAllTypes ? 'меньше' : 'ещё…'),
                      ),
                      if (_showAllTypes)
                        Pressable(
                          label: 'Свой аккорд',
                          onTap: () => app.sheet = const AppSheet('chordBuilder'),
                          child: const NoteChip(text: '+ Свой'),
                        ),
                    ]),
                    const SizedBox(height: 22),
                    const SectionCaption(text: 'Расположения · от простых к сложным'),
                    if (voicings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: ChordNoneState(
                          chordName: fretboard.chordName(),
                          hint: fretboard.omissionHint,
                          omit: () {
                            final hint = fretboard.omissionHint;
                            if (hint != null) fretboard.omit(hint);
                          },
                        ),
                      )
                    else
                      Card(children: [
                        for (var i = 0; i < math.min(8, voicings.length); i++)
                          VoicingCardRow(
                            voicing: voicings[i],
                            anchored: false,
                            easiest: i == 0,
                            onTap: () {
                              fretboard.voicingIndex = i;
                              fretboard.mode = FretMode.chord;
                              fretboard.playVoicing(voicings[i]);
                              widget.close();
                            },
                          ),
                      ]),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SwiftText('Обращения', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                    ),
                    const SizedBox(height: 6),
                    ChordInversionRow(showScales: _scrollToScales),
                    const SizedBox(height: 14),
                    Padding(
                      key: _scalesKey,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SwiftText('Подходящие гаммы', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                    ),
                    const SizedBox(height: 6),
                    FlowLayout(children: [
                      for (final m in scales)
                        Pressable(
                          onTap: () {
                            fretboard.updateSettings((s) {
                              s.scaleId = m.scaleId;
                              s.tonic = m.tonic;
                            });
                            fretboard.mode = FretMode.scale;
                            widget.close();
                          },
                          child: Chip(text: m.title),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// «Путь по грифу» (canvas sheet over the neck): 3 per string, 4 diagonal, one string; sequence; leave the path.
class FretPathSheet extends StatelessWidget {
  const FretPathSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    return DesignSheet(
      title: 'Путь по грифу',
      height: 600,
      close: () => app.sheet = null,
      footer: [
        Expanded(
          child: OutlineButton(
            title: 'Выйти из пути',
            onTap: () {
              fretboard.stopPlayback();
              fretboard.pathKind = null;
              fretboard.pathStart = null;
              app.sheet = null;
            },
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption(text: 'Путь'),
          Card(children: [
            RadioRow(
              title: '3 ноты на струну',
              subtitle: 'Позиция за позицией',
              selected: fretboard.pathKind == PathKind.threePerString,
              onTap: () => fretboard.pathKind = PathKind.threePerString,
            ),
            RadioRow(
              title: '4 ноты наискосок',
              subtitle: 'Через весь гриф за один проход',
              selected: fretboard.pathKind == PathKind.fourDiagonal,
              onTap: () => fretboard.pathKind = PathKind.fourDiagonal,
            ),
            RadioRow(
              title: 'По одной струне',
              subtitle: 'Вдоль грифа, удобно для слайдов',
              selected: fretboard.pathKind == PathKind.oneString,
              showsDivider: false,
              onTap: () => fretboard.pathKind = PathKind.oneString,
            ),
          ]),
          const SizedBox(height: 14),
          const PlaybackControls(),
        ],
      ),
    );
  }
}

/// «Расположений не найдено» (canvas «Аккорд — не помещается»): 52 pt icon, 17 medium title (168 wide),
/// 12 pt explanation with the degree to drop (160 wide), «Опустить ступень N» 48 pt outline button 44 below.
class ChordNoneState extends StatelessWidget {
  const ChordNoneState({super.key, required this.chordName, required this.hint, required this.omit});
  final String chordName;
  final Map<String, dynamic>? hint;
  final VoidCallback omit;

  @override
  Widget build(BuildContext context) {
    final h = hint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: ShapeBox(
            shape: SwiftShape.circle,
            fills: const [SwiftFill(TruverColors.fill)],
            strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
            child: const Center(child: AppIconView(AppIcon.fretboard, size: 24, color: TruverColors.textSecondary)),
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 168),
          child: SwiftText('Расположений не найдено', textAlign: TextAlign.center, style: Typo.inter(17, TypoWeight.medium, TruverColors.textBody)),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: notesText('$chordName не помещается в 4 пальца в этом строе.${h == null ? ' Выберите другой тип' : ' Попробуйте опустить ${h['number']}-ю ступень'}',
                Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary),
            textAlign: TextAlign.center,
            lineSpacing: 4,
          ),
        ),
        if (h != null) ...[
          const SizedBox(height: 44),
          Pressable(
            onTap: omit,
            child: SizedBox(
              height: 48,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Center(widthFactor: 1, child: Text('Опустить ступень ${h['number']}', style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody))),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

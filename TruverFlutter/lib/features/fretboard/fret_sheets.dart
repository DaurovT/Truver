/// Port of Truver/Sources/Features/Fretboard/FretSheets.swift
///
/// The fretboard sheets «Гамма», «Вид и подписи», «Проигрывание» and the playback controls they share with the
/// path sheet.
library;

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

// MARK: Sheets

/// «Гамма» (canvas «Гамма», top 60): the tonic as chips, «Частые» scales with a check, «Ещё» — categories that open
/// their list in the sheet; the user's own scales and «Сохранить изменённую как свою» stay reachable.
class FretScaleSheet extends StatefulWidget {
  const FretScaleSheet({super.key});

  @override
  State<FretScaleSheet> createState() => _FretScaleSheetState();
}

class _FretScaleSheetState extends State<FretScaleSheet> {
  String? _category;

  /// «Частые»: canvas titles and subtitles (the selected one shows its steps instead).
  static const common = [
    ('major', 'Мажор (ионийский)', 'ионийский'),
    ('aeolian', 'Натуральный минор', 'эолийский'),
    ('major-pentatonic', 'Пентатоника мажорная', '5 нот'),
    ('minor-pentatonic', 'Пентатоника минорная', '5 нот'),
    ('blues', 'Блюзовая', '6 нот · с ♭5'),
  ];

  /// «Ещё»: categories with a hint of what is inside.
  static const more = [
    ('majorModes', 'Лады', 'дорийский, фригийский, лидийский…'),
    ('harmonicMinorModes', 'Гармонические и мелодические', null),
    ('exotic', 'Экзотические', 'венгерский, хиджаз…'),
    ('pentatonicAndBlues', 'Пентатоники и блюз', null),
    ('symmetric', 'Симметричные', 'целотонная, уменьшённые'),
    ('bebop', 'Бибоп', null),
    ('maqam', 'Макамы', null),
    ('user', 'Мои гаммы', null),
  ];

  /// Sharps for the tonic chips (letter, accidental) by pitch class.
  static const _sharps = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)];

  /// «Т Т П Т Т Т П»: tones and semitones between the steps (from the core's degree labels: 1 2 ♭3 …).
  static String steps(String labels) {
    const major = [0, 2, 4, 5, 7, 9, 11];
    final pcs = <int>{};
    for (final label in labels.split(' ')) {
      var acc = 0;
      var digits = '';
      for (final rune in label.runes) {
        final ch = String.fromCharCode(rune);
        switch (ch) {
          case '♭':
            acc -= 1;
          case '♯':
            acc += 1;
          case '𝄫':
            acc -= 2;
          case '𝄪':
            acc += 2;
          default:
            if (RegExp(r'\d').hasMatch(ch)) digits += ch;
        }
      }
      final n = int.tryParse(digits);
      if (n == null || n < 1) continue;
      pcs.add(((major[(n - 1) % 7] + 12 * ((n - 1) ~/ 7) + acc) % 12 + 12) % 12);
    }
    final sorted = pcs.toList()..sort();
    if (sorted.length < 2) return '';
    return [
      for (var i = 0; i < sorted.length; i++)
        switch ((i + 1 < sorted.length ? sorted[i + 1] : 12) - sorted[i]) {
          1 => 'П',
          2 => 'Т',
          3 => '1½',
          final g => (g / 2).toString().replaceAll('.0', '').replaceAll('.', ','),
        },
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final library = FretLibrary.load(app);
    final tonicPC = notePitchClass(fretboard.settings.tonic);
    final category = _category;
    return DesignSheet(
      title: 'Гамма',
      height: 784,
      close: () => app.sheet = null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: category != null
            ? _categoryList(app, library, category)
            : [
                const SectionCaption(text: 'Тоника'),
                Card(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(11, 9, 11, 9), // 12 × 10 inside the card's 1 pt border
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FlowLayout(children: [
                        for (var pc = 0; pc < 12; pc++)
                          Pressable(
                            selected: tonicPC == pc,
                            onTap: () => fretboard.setTonic(pc),
                            child: NoteChip(
                              text: tonicPC == pc
                                  ? fretboard.data?.tonicText ?? ''
                                  : app.noteName({'letter': _sharps[pc].$1, 'accidental': _sharps[pc].$2}),
                              style: tonicPC == pc ? NoteChipStyle.selected : NoteChipStyle.plain,
                            ),
                          ),
                      ]),
                    ),
                  ),
                ]),
                if (fretboard.isEdited) ...[
                  const SizedBox(height: 12),
                  // TH-8 / 6.1 п. 13: the edited scale becomes the user's own.
                  Card(children: [
                    Pressable(
                      scale: 1,
                      onTap: () => app.sheet = const AppSheet('scaleBuilder'),
                      child: const ScaleRow(title: 'Сохранить изменённую как свою', subtitle: 'точки и крестики на грифе'),
                    ),
                  ]),
                ],
                const SizedBox(height: 12),
                const SectionCaption(text: 'Частые'),
                Card(children: [
                  for (final (id, title, subtitle) in common)
                    () {
                      final selected = fretboard.settings.scaleId == id;
                      final labels = library.scales.where((s) => s.id == id).firstOrNull?.labels;
                      return Pressable(
                        scale: 1,
                        selected: selected,
                        onTap: () => _pick(app, id),
                        child: ScaleRow(title: title, subtitle: selected && labels != null ? steps(labels) : subtitle, checked: selected),
                      );
                    }(),
                ]),
                const SizedBox(height: 12),
                const SectionCaption(text: 'Ещё'),
                Card(children: [
                  for (final (value, title, subtitle) in more)
                    Pressable(
                      scale: 1,
                      onTap: () => setState(() => _category = value),
                      child: ScaleRow(title: title, subtitle: value == 'user' ? _userSubtitle(app) : subtitle),
                    ),
                ]),
              ],
      ),
    );
  }

  String _userSubtitle(AppModel app) {
    final n = app.settings.customScales.length;
    return n == 0 ? 'своя гамма по ступеням' : '$n ${ruPlural(n, 'гамма', 'гаммы', 'гамм')}';
  }

  void _pick(AppModel app, String id) {
    app.fretboard.setScale(id);
    app.sheet = null;
  }

  /// One category: «‹ Все гаммы», then its scales (the user's own can be edited, and a new one made).
  List<Widget> _categoryList(AppModel app, FretLibrary library, String category) {
    final fretboard = app.fretboard;
    final title = more.where((m) => m.$1 == category).firstOrNull?.$2 ?? '';
    final list = library.scales
        .where((s) => category == 'harmonicMinorModes'
            ? (s.category == 'harmonicMinorModes' || s.category == 'melodicMinorModes')
            : s.category == category)
        .toList();
    return [
      Pressable(
        scale: 1,
        onTap: () => setState(() => _category = null),
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
          child: Row(children: [
            const AppIconView(AppIcon.chevronLeft, size: 16, color: TruverColors.textTertiary),
            const SizedBox(width: 6),
            SwiftText('Все гаммы', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
            const Spacer(),
            SwiftText(title, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
          ]),
        ),
      ),
      Card(children: [
        for (final scale in list)
          Pressable(
            scale: 1,
            onTap: () => _pick(app, scale.id),
            child: ScaleRow(
              title: scale.name,
              subtitle: steps(scale.labels),
              checked: scale.id == fretboard.settings.scaleId,
              showsChevron: false,
              trailing: category == 'user'
                  ? Pressable(
                      scale: 1,
                      label: 'Изменить «${scale.name}»',
                      onTap: () => app.sheet = AppSheet('scaleBuilder', scale.id),
                      child: const SizedBox(width: 36, height: 36, child: Center(child: AppIconView(AppIcon.rename, size: 18, color: TruverColors.textSecondary))),
                    )
                  : null,
            ),
          ),
        if (category == 'user')
          Pressable(
            scale: 1,
            onTap: () => app.sheet = const AppSheet('scaleBuilder'),
            child: ScaleRow(
              title: 'Новая гамма…',
              subtitle: 'ступени от ${fretboard.data?.tonicText ?? ''}',
              showsChevron: false,
              trailing: const AppIconView(AppIcon.plus, size: 18, color: TruverColors.textSecondary),
            ),
          ),
      ]),
    ];
  }
}

/// Row of the scale sheet (canvas: min 60 + padding 8 × 16 + border, gap 12, title 15 primary, subtitle 12, check 20 or › 16).
class ScaleRow extends StatelessWidget {
  const ScaleRow({super.key, required this.title, this.subtitle, this.checked = false, this.showsChevron = true, this.trailing});
  final String title;
  final String? subtitle;
  final bool checked;
  final bool showsChevron;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BottomHairline(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 9),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwiftText.rich(Typo.notes(title, Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary))),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      SwiftText.rich(Typo.notes(subtitle!, Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary))),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (checked) ...[
                const SizedBox(width: 12),
                const AppIconView(AppIcon.check, size: 20, lineWidth: 2, color: TruverColors.textPrimary),
              ] else if (showsChevron) ...[
                const SizedBox(width: 12),
                const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
              ],
            ]),
          ),
        ),
      );
}

/// A 1 pt line of white 6 % along the bottom edge (canvas row `border-bottom`).
class BottomHairline extends Decoration {
  const BottomHairline();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _BottomHairlinePainter();
}

class _BottomHairlinePainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size ?? Size.zero;
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy + size.height - 1, size.width, 1), Paint()..color = TruverColors.white(0.06));
  }
}

enum NoteChipStyle { plain, selected, marked }

/// Chip with a note name (canvas `<span>` chip: 32 pt + border, 12 medium; accidentals in the system font).
class NoteChip extends StatelessWidget {
  const NoteChip({super.key, required this.text, this.style = NoteChipStyle.plain});
  final String text;
  final NoteChipStyle style;

  @override
  Widget build(BuildContext context) {
    // Canvas: plain — white 5 % / 10 % ring, #e9e6df; selected — ivory 10 % / 55 %; marked (search) — 8 % / 40 %.
    final (fill, ring) = switch (style) {
      NoteChipStyle.plain => (TruverColors.fill, TruverColors.hairlineStrong),
      NoteChipStyle.selected => (const Color(0x1AF6F3EC), const Color(0x8CF6F3EC)),
      NoteChipStyle.marked => (const Color(0x14F6F3EC), const Color(0x66F6F3EC)),
    };
    return SizedBox(
      height: 34,
      child: ShapeBox(
        shape: const SwiftShape.rounded(16),
        fills: [SwiftFill(fill)],
        strokes: [SwiftStroke(ring, inside: true)],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Center(
            widthFactor: 1,
            child: Text.rich(
              Typo.notes(text, Typo.inter(12, TypoWeight.medium, style == NoteChipStyle.plain ? TruverColors.textBody : TruverColors.textPrimary)),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Scales and chords of the core library (with the user's own), cached per user library.
class LibraryScale {
  LibraryScale(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        name = j['name'] as String? ?? '',
        category = j['category'] as String? ?? '',
        needsReview = j['needsReview'] == true,
        isUser = j['isUser'] == true,
        labels = j['labels'] as String? ?? '';
  final String id;
  final String name;
  final String category;
  final bool needsReview;
  final bool isUser;
  final String labels;
}

class LibraryChord {
  LibraryChord(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        symbol = j['symbol'] as String? ?? '',
        isUser = j['isUser'] == true;
  final String id;
  final String symbol;
  final bool isUser;
  String get chipName => chordChipName(id, symbol);
}

class FretLibrary {
  FretLibrary._(this.scales, this.chords);
  final List<LibraryScale> scales;
  final List<LibraryChord> chords;

  static FretLibrary? _cached;
  static String _key = '';

  static FretLibrary load(AppModel app) {
    final key = '${app.settings.customScales}|${app.settings.customChords}';
    if (_cached != null && key == _key) return _cached!;
    dynamic r;
    try {
      r = app.core?.call('fretboard.library');
    } catch (_) {}
    final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    _key = key;
    return _cached = FretLibrary._(
      [for (final s in (m['scales'] as List? ?? const [])) LibraryScale(Map<String, dynamic>.from(s as Map))],
      [for (final c in (m['chords'] as List? ?? const [])) LibraryChord(Map<String, dynamic>.from(c as Map))],
    );
  }

  static List<String> search(AppModel app, String query) {
    try {
      return ((app.core?.call('fretboard.scaleSearch', {'query': query}) as List?) ?? const []).cast<String>();
    } catch (_) {
      return const [];
    }
  }
}

/// «Вид и подписи» (canvas «Вид и подписи», top 180): labels on the notes, what to show (notes outside the scale,
/// frets counted from the capo, the capo), how the guitar is held; «Готово».
class FretViewSheet extends StatelessWidget {
  const FretViewSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final s = fretboard.settings;
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    final capoText = capo > 0 ? 'на $capo-м ладу' : 'нет';
    final low = s.leftHanded ? 'справа' : 'слева';
    return DesignSheet(
      title: 'Вид и подписи',
      height: 664,
      close: () => app.sheet = null,
      footer: [Expanded(child: SheetButton(title: 'Готово', onTap: () => app.sheet = null))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption(text: 'Подписи на нотах'),
          SegmentsCard<LabelMode>(
            options: const [(LabelMode.notes, 'Ноты'), (LabelMode.degrees, 'Ступени'), (LabelMode.none, 'Без подписей')],
            selection: const [LabelMode.notes, LabelMode.degrees, LabelMode.none].contains(s.labels) ? s.labels : LabelMode.notes,
            onChanged: (v) => fretboard.updateSettings((s) => s.labels = v),
          ),
          const SizedBox(height: 14),
          const SectionCaption(text: 'Показывать'),
          Card(children: [
            CardRow(
              title: 'Ноты вне гаммы',
              minHeight: 53,
              trailing: ToggleSwitch(isOn: fretboard.showOutOfScale, label: 'Ноты вне гаммы', onChanged: (v) => fretboard.showOutOfScale = v),
            ),
            CardRow(
              title: 'Лады от капо',
              subtitle: 'номера считаются от капо',
              minHeight: 61,
              trailing: ToggleSwitch(isOn: fretboard.fretsFromCapo, label: 'Лады от капо', onChanged: (v) => fretboard.fretsFromCapo = v),
            ),
            Builder(
              builder: (context) => Pressable(
                scale: 1,
                label: 'Капо: $capoText',
                onTap: () => showFretMenu(context, [
                  FretMenuItem('Без капо', () => app.updateInstrument((i) => i['capo'] = 0), checked: capo == 0),
                  for (var f = 1; f <= 12; f++) FretMenuItem('На $f-м ладу', () => app.updateInstrument((i) => i['capo'] = f), checked: capo == f),
                ]),
                child: CardRow(title: 'Капо', minHeight: 53, trailing: ValueChevron(capoText)),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          const SectionCaption(text: 'Как держите гитару'),
          Card(children: [
            CardRow(
              title: 'Для левши',
              subtitle: 'гриф зеркально',
              minHeight: 61,
              trailing: ToggleSwitch(
                isOn: s.leftHanded,
                label: 'Для левши',
                onChanged: (v) => fretboard.updateSettings((s) => s.leftHanded = v),
              ),
            ),
            // In portrait the low string is on the left, mirrored for left-handers (the same setting).
            Builder(
              builder: (context) => Pressable(
                scale: 1,
                label: 'Низкая струна: $low',
                onTap: () => showFretMenu(context, [
                  FretMenuItem('Слева', () => fretboard.updateSettings((s) => s.leftHanded = false), checked: !s.leftHanded),
                  FretMenuItem('Справа', () => fretboard.updateSettings((s) => s.leftHanded = true), checked: s.leftHanded),
                ]),
                child: CardRow(title: 'Низкая струна', minHeight: 53, trailing: ValueChevron(low)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// «на 2-м ладу ›»: a row value with a chevron (canvas: 14 secondary, gap 8, chevron 16).
class ValueChevron extends StatelessWidget {
  const ValueChevron(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SwiftText(text, style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
        const SizedBox(width: 8),
        const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
      ]);
}

/// Segments inside a card with 6 pt around (canvas `<div style="padding: 6px">` in a card).
class SegmentsCard<T> extends StatelessWidget {
  const SegmentsCard({super.key, required this.options, required this.selection, required this.onChanged});
  final List<(T, String)> options;
  final T selection;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Card(children: [
        Padding(
          padding: const EdgeInsets.all(5), // + the card's 1 pt padding = 6 (measured on the canvas render)
          child: Segments<T>(options: options, selection: selection, onChanged: onChanged),
        ),
      ]);
}

/// «Проигрывание» (canvas «Проигрывание», top 150): direction, pattern, tempo shared with the metronome, the click with
/// a one-bar count-in, loop, drone; «С проверкой» (FB-14) and «Играть» at the bottom.
class FretPlaySheet extends StatelessWidget {
  const FretPlaySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return DesignSheet(
      title: 'Проигрывание',
      height: 694,
      close: () => app.sheet = null,
      footer: [
        Pressable(
          label: 'С проверкой',
          onTap: () {
            app.sheet = null;
            app.fretboard.startTraining();
          },
          child: SizedBox(
            width: 168,
            height: 52,
            child: ShapeBox(
              shape: SwiftShape.capsule,
              fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
              strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const AppIconView(AppIcon.mic, size: 18, color: TruverColors.textBody),
                const SizedBox(width: 8),
                SwiftText('С проверкой', maxLines: 1, style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: SheetButton(
            title: 'Играть',
            icon: AppIcon.play,
            height: 52,
            onTap: () {
              app.sheet = null;
              if (!app.fretboard.isPlaying) app.fretboard.startPlayback();
            },
          ),
        ),
      ],
      child: const PlaybackControls(),
    );
  }
}

/// Direction, pattern, tempo, click, loop and drone: the same in «Проигрывание» and in the path sheet.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final bpm = fretboard.bpm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(text: 'Направление'),
        SegmentsCard<PlaybackDirection>(
          options: const [(PlaybackDirection.up, 'Вверх'), (PlaybackDirection.down, 'Вниз'), (PlaybackDirection.upDown, 'Вверх-вниз')],
          selection: fretboard.direction,
          onChanged: (v) => fretboard.direction = v,
        ),
        const SizedBox(height: 14),
        const SectionCaption(text: 'Рисунок'),
        SegmentsCard<PlaybackChoice>(
          options: [for (final p in PlaybackChoice.values) (p, p.title)],
          selection: fretboard.playback,
          onChanged: (v) => fretboard.playback = v,
        ),
        const SizedBox(height: 14),
        Card(children: [
          CardRow(
            title: 'Темп',
            subtitle: 'общий с метрономом',
            minHeight: 61,
            trailing: ValueStepper(
              value: '${bpm.round()}',
              canDecrement: bpm > 20,
              canIncrement: bpm < 400,
              decrement: () => fretboard.bpm = bpm - 1,
              increment: () => fretboard.bpm = bpm + 1,
            ),
          ),
          CardRow(
            title: 'Щелчок метронома',
            subtitle: 'с отсчётом в один такт',
            minHeight: 61,
            trailing: ToggleSwitch(
              isOn: fretboard.settings.clickWithPlayback,
              label: 'Щелчок метронома',
              onChanged: (v) => fretboard.updateSettings((s) => s.clickWithPlayback = v),
            ),
          ),
          CardRow(
            title: 'По кругу',
            minHeight: 53,
            trailing: ToggleSwitch(isOn: fretboard.loop, label: 'По кругу', onChanged: (v) => fretboard.loop = v),
          ),
          CardRow(
            title: 'Бурдон на тонике',
            subtitle: '${fretboard.data?.tonicText ?? ''} тянется, пока не выключите',
            minHeight: 61,
            trailing: ToggleSwitch(
              isOn: fretboard.isDroning,
              label: 'Бурдон на тонике',
              onChanged: (v) => v ? fretboard.startDrone() : fretboard.stopDrone(),
            ),
          ),
        ]),
      ],
    );
  }
}

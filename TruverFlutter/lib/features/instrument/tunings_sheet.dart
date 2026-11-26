/// Port of Truver/Sources/Features/Instrument/TuningsSheet.swift
///
/// «Инструмент и строи» by the canvas (6.2.3): sheets for tunings, adding, editing, the template library, the
/// generator, the instrument and its strings. Heights are 844 − the panel's top on the canvas. Note names, the
/// library, the generator, rebuilding and fans come from the core (`instrument.*`, TruverBridge/InstrumentCommands.swift).
library;

import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'design_menu.dart';

// MARK: Helpers

/// Russian plural: 1 лад, 2 лада, 5 ладов (`ModeParamsSheet.plural`).
String plural(int n, String one, String few, String many) {
  final n10 = n % 10, n100 = n % 100;
  if (n10 == 1 && n100 != 11) return one;
  if (n10 >= 2 && n10 <= 4 && !(n100 >= 12 && n100 <= 14)) return few;
  return many;
}

/// `String.capitalizedFirst`.
String capitalizedFirst(String s) => s.isEmpty ? s : s.substring(0, 1).toUpperCase() + s.substring(1);

/// iOS `LibrarySheet.typeName`.
String instrumentTypeName(String type) => switch (type) {
  'guitar' || 'guitarExtendedHigh' => 'гитара',
  'bass' => 'бас',
  'ukulele' => 'укулеле',
  'mandolin' => 'мандолина',
  'dutar' => 'дутар',
  'tanbur' => 'танбур',
  'rubob' => 'рубоб',
  _ => type,
};

dynamic _core(AppModel app, String method, Map<String, dynamic> params) {
  try {
    return app.core?.call(method, params);
  } catch (e) {
    debugPrint('$method: $e');
    return null;
  }
}

Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// Spelled notes of each course of `tunings` (`tuning.spelledNotes.map { app.noteName($0) }`).
List<List<String>> spellTunings(AppModel app, List<Map<String, dynamic>> tunings) {
  final r = _core(app, 'instrument.spell', {'tunings': tunings});
  if (r is! List) return [for (final _ in tunings) <String>[]];
  return [for (final t in r) (t as List).cast<String>()];
}

/// Replaces the whole instrument JSON with one returned by the core.
void _replaceInstrument(AppModel app, Object? result) {
  final next = _map(result);
  if (next == null) return;
  app.updateInstrument(
    (i) => i
      ..clear()
      ..addAll(next),
  );
}

void _addTuning(AppModel app, Map<String, dynamic> tuning) => app.updateInstrument((i) {
  (i['tunings'] as List).add(tuning);
  i['currentTuningId'] = tuning['id'];
});

List<Map<String, dynamic>> _courses(Map<String, dynamic> instrument) => (instrument['courses'] as List).cast<Map<String, dynamic>>();

Widget _notes(
  String text,
  double size, {
  TypoWeight weight = TypoWeight.regular,
  Color? color,
  int? maxLines,
  TextAlign? align,
  double tracking = 0,
}) {
  final style = tracking == 0 ? Typo.inter(size, weight, color) : Typo.inter(size, weight, color).copyWith(letterSpacing: tracking);
  return SwiftText.rich(Typo.notes(text, style), style: style, maxLines: maxLines, textAlign: align);
}

const _chevron = AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary);

/// `HStack(spacing: 8) { Text(value); Icon(.chevronRight) }` — the trailing of a row that opens something.
Widget _valueChevron(String value, {bool notes = false}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    notes ? NoteText(value, style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)) : Text(value),
    const SizedBox(width: 8),
    _chevron,
  ],
);

/// `Capsule().fill(Theme.cardFill)` + hairline: the outline buttons of these sheets.
class _OutlineCapsule extends StatelessWidget {
  const _OutlineCapsule({required this.title, required this.onTap, this.height = 44, this.style});

  final String title;
  final VoidCallback onTap;
  final double height;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: ShapeBox(
      shape: SwiftShape.capsule,
      fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
      strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
        child: Center(heightFactor: 1, child: Text(title, style: style ?? Typo.inter(15, TypoWeight.medium, TruverColors.textBody))),
      ),
    ),
  );
}

/// A sheet with an alert over it (`.overlay { DesignAlert … }` on the `DesignSheet`). The box is the screen's
/// height, so the alert's dim covers the whole screen and the alert sits at its middle (canvas `top: 50%`); the
/// empty part above the sheet lets touches through to the host's dim.
Widget _withOverlay(Widget sheet, Widget? overlay) => Builder(
  builder: (context) => SizedBox(
    height: MediaQuery.sizeOf(context).height,
    child: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        sheet,
        if (overlay != null) Positioned.fill(child: overlay),
      ],
    ),
  ),
);

/// The canvas row's `border-bottom: 1px` below its height (content-box: a 52 pt row takes 53).
Widget _ruled(Widget child, [bool on = true]) => on
    ? Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          SizedBox(height: 1, child: ColoredBox(color: TruverColors.white(0.06))),
        ],
      )
    : child;

/// A row divider at the bottom (`.overlay(alignment: .bottom) { Rectangle()… }`).
Widget _divided(Widget child, bool divider) =>
    divider ? DecoratedBox(position: DecorationPosition.foreground, decoration: rowDivider, child: child) : child;

/// The two menus of the tuning editor and the instrument: «Капо».
List<MenuItem> _capoItems(AppModel app) => [
  MenuItem('Нет', () => app.updateInstrument((i) => i['capo'] = 0)),
  for (var fret = 1; fret <= 12; fret++) MenuItem('$fret-й лад', () => app.updateInstrument((i) => i['capo'] = fret)),
];

String _capoText(int capo) => capo == 0 ? 'Нет' : '$capo-й лад';

// MARK: Debug launch arguments (canvas boards)

/// `-tuningsDemo`, `-sheet tuningsLastOne | tuningsDelete | tuningUnsaved | libraryDrop | generatorDropC` (set by
/// instrument_feature.dart, read once by the sheets) — `TuningsDebug` in TuningsSheet.swift.
abstract final class TuningsDebug {
  static bool lastOneToast = false;
  static bool deleteLast = false;
  static bool unsaved = false;
  static String? libraryCategory;
  static (int, int)? generator;
}

// MARK: Shared pieces

/// «≡» of the canvas: three lines and a ring on the top one, filled with the background (`EditGlyph`).
class EditGlyph extends StatelessWidget {
  const EditGlyph({super.key, this.size = 16, this.color = TruverColors.textTertiary});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = size / 24;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          AppIconView(AppIcon.list, size: size, color: color),
          Positioned(
            left: 7 * s,
            top: 5 * s,
            width: 4 * s,
            height: 4 * s,
            child: ShapeBox(
              shape: SwiftShape.circle,
              fills: const [SwiftFill(TruverColors.background)],
              strokes: [SwiftStroke(color, width: 1.6 * s)],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of the tunings list and the library (60 pt): check column 20, name 15, notes 12 with 0.06 em tracking.
class TuningListRow extends StatelessWidget {
  const TuningListRow({super.key, required this.name, required this.notes, this.checked = false, this.showsDivider = true, this.trailing});

  final String name;
  final String notes;
  final bool checked;
  final bool showsDivider;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => _ruled(
    SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: checked ? const Center(child: AppIconView(AppIcon.check, size: 18, lineWidth: 2, color: TruverColors.textPrimary)) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _notes(name, 15, color: TruverColors.textPrimary, maxLines: 1),
                  const SizedBox(height: 2),
                  _notes(notes, 12, color: TruverColors.textTertiary, maxLines: 1, tracking: 0.72),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    ),
    showsDivider,
  );
}

/// A sheet lying over «Инструмент и строи»: the tunings sheet stays below under a second dim (canvas boards
/// «Добавить строй», «Библиотека строев», «Генератор строя»).
class OverTunings extends StatelessWidget {
  const OverTunings({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          const IgnorePointer(child: ExcludeSemantics(child: TuningsSheet())),
          Positioned.fill(
            child: GestureDetector(
              onTap: () => app.sheet = const AppSheet('tunings'),
              child: ColoredBox(color: TruverColors.sheetDim),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// The child `amount` wider on both sides than the parent gives (SwiftUI `.padding(.horizontal, -amount)`): the
/// editor's divider and the chips row reach the sheet's edges, the toast is laid out on the screen width.
class Bleed extends SingleChildRenderObjectWidget {
  const Bleed({super.key, required this.amount, super.child});

  final double amount;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBleed(amount);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderBleed).amount = amount;
}

class _RenderBleed extends RenderProxyBox {
  _RenderBleed(this.amount);
  double amount;

  @override
  void performLayout() {
    final c = constraints;
    final width = c.maxWidth + 2 * amount;
    child!.layout(BoxConstraints(minWidth: width, maxWidth: width, minHeight: c.minHeight, maxHeight: c.maxHeight), parentUsesSize: true);
    size = c.constrain(Size(c.maxWidth, child!.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.paintChild(child!, offset.translate(-amount, 0));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintOffset(
    offset: Offset(-amount, 0),
    position: position,
    hitTest: (r, p) => child!.hitTest(r, position: p),
  );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.translateByDouble(-amount, 0, 0, 1);
}

/// Stepper whose value is at most 44 wide and wraps («2 / тона» on the canvas): − 36, value, + 36, gap 4.
class _NarrowStepper extends StatelessWidget {
  const _NarrowStepper({required this.value, this.canDecrement = true, this.canIncrement = true, required this.decrement, required this.increment});

  final String value;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback decrement;
  final VoidCallback increment;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Opacity(
        opacity: canDecrement ? 1 : 0.4,
        child: RoundIconButton(
          icon: AppIcon.minus,
          size: 36,
          iconSize: 16,
          label: 'Меньше',
          onTap: canDecrement ? decrement : null,
          enabled: canDecrement,
        ),
      ),
      const SizedBox(width: 4),
      SizedBox(
        width: 48, // canvas: min-width 44, laid out 48 («2 тона» wraps)
        child: SwiftText(value, textAlign: TextAlign.center, style: Typo.inter(16, TypoWeight.regular, TruverColors.textPrimary)),
      ),
      const SizedBox(width: 4),
      Opacity(
        opacity: canIncrement ? 1 : 0.4,
        child: RoundIconButton(
          icon: AppIcon.plus,
          size: 36,
          iconSize: 16,
          label: 'Больше',
          onTap: canIncrement ? increment : null,
          enabled: canIncrement,
        ),
      ),
    ],
  );
}

/// A row whose title wraps next to a stepper, 10 pt apart (canvas flex `space-between`, gap 10).
class _StepperRow extends StatelessWidget {
  const _StepperRow({required this.title, required this.stepper});

  final String title;
  final Widget stepper;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 60),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SwiftText(title, style: Typo.row.copyWith(color: TruverColors.textBody)),
          ),
          const SizedBox(width: 10),
          stepper,
        ],
      ),
    ),
  );
}

/// «½ тона», «1 тон», «1½ тона», «2 тона» (`TuningRecipe.tones`).
String tonesText(int semitones) {
  final whole = semitones ~/ 2, half = semitones.isOdd;
  final number = whole == 0 ? '½' : '$whole${half ? '½' : ''}';
  final word = whole == 1 && !half ? 'тон' : (whole >= 5 ? 'тонов' : 'тона');
  return '$number $word';
}

/// «Drop D», «Drop D (2)»… (`TuningEditorSheet.uniqueName`).
String uniqueTuningName(AppModel app, String base) {
  final names = {for (final t in app.tunings) t['name']};
  if (!names.contains(base)) return base;
  var n = 2;
  while (names.contains('$base ($n)')) {
    n++;
  }
  return '$base ($n)';
}

// MARK: «Инструмент и строи»

/// «Инструмент и строи» (top 150): the instrument (→ «Инструмент»), tunings (tap — switch, ≡ — edit, swipe —
/// delete), «Добавить строй». The last tuning can't be deleted — a toast says so.
class TuningsSheet extends StatefulWidget {
  const TuningsSheet({super.key});

  @override
  State<TuningsSheet> createState() => _TuningsSheetState();
}

class _TuningsSheetState extends State<TuningsSheet> {
  String? _openRow;
  Map<String, dynamic>? _deleting;
  bool _lastOneToast = false;
  int _toastToken = 0;

  @override
  void initState() {
    super.initState();
    if (TuningsDebug.deleteLast) {
      TuningsDebug.deleteLast = false;
      final tunings = AppScope.read(context).tunings;
      if (tunings.isNotEmpty) _deleting = tunings.last;
    }
    if (TuningsDebug.lastOneToast) {
      TuningsDebug.lastOneToast = false;
      _lastOneToast = true;
    }
  }

  void _showLastOne() {
    final token = ++_toastToken;
    setState(() => _lastOneToast = true);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && token == _toastToken) setState(() => _lastOneToast = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tunings = app.tunings;
    final single = tunings.length == 1;
    final notes = spellTunings(app, tunings);
    final currentId = app.tuning['id'];
    final frets = (app.instrument['fretCount'] as num).toInt();

    Widget row(int index) {
      final tuning = tunings[index];
      final current = tuning['id'] == currentId;
      final name = tuning['name'] as String? ?? '';
      return Pressable(
        scale: 1,
        selected: current,
        onTap: () {
          app.selectTuning(tuning['id'] as String);
          app.sheet = null;
        },
        child: TuningListRow(
          name: name,
          notes: notes[index].join(' '),
          checked: current,
          trailing: Pressable(
            scale: 1,
            label: 'Изменить строй $name',
            onTap: () => app.sheet = AppSheet('tuningEditor', tuning['id']),
            child: const TouchArea(child: EditGlyph()),
          ),
        ),
      );
    }

    final deleting = _deleting;
    return _withOverlay(
      DesignSheet(
        title: 'Инструмент и строи',
        height: 694,
        close: () => app.sheet = null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionCaption(text: 'Инструмент'),
            Card(
              children: [
                Pressable(
                  scale: 1,
                  onTap: () => app.sheet = const AppSheet('instrument'),
                  child: _ruled(
                    CardRow(
                      showsDivider: false,
                      title: app.instrument['name'] as String? ?? '',
                      minHeight: 52,
                      trailing: _valueChevron('$frets ${plural(frets, 'лад', 'лада', 'ладов')}'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SectionCaption(text: single ? 'Строи' : 'Строи · касание — переключить, ≡ — править'),
            Card(
              children: [
                for (var i = 0; i < tunings.length; i++)
                  SwipeRow(
                    key: ValueKey(tunings[i]['id']),
                    id: tunings[i]['id'] as String,
                    openId: _openRow,
                    onOpen: (id) => setState(() => _openRow = id),
                    showsDivider: false,
                    delete: () => single ? _showLastOne() : setState(() => _deleting = tunings[i]),
                    child: row(i),
                  ),
                // «+ Добавить строй» (52 pt) at the end of the list.
                Pressable(
                  scale: 1,
                  onTap: () => app.sheet = const AppSheet('tuningsAdd'),
                  child: SizedBox(
                    height: 52,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const AppIconView(AppIcon.plus, size: 18, color: TruverColors.textPrimary),
                          const SizedBox(width: 10),
                          Text('Добавить строй', style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: Motion.base,
              child: _lastOneToast
                  ? const Bleed(
                      key: ValueKey('toast'),
                      amount: 20,
                      child: Padding(
                        padding: EdgeInsets.only(top: 19),
                        child: Center(
                          child: DesignToast(
                            icon: AppIcon.lock,
                            iconColor: TruverColors.textSecondary,
                            text: 'Последний строй удалить нельзя — сначала добавьте другой',
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ],
        ),
      ),
      deleting == null
          ? null
          : DesignAlert(
              title: 'Удалить «${deleting['name']}»?',
              message: 'Строй пропадёт из списка. Пресеты и занятия не затронет.',
              actions: [
                DesignAlertAction('Отмена', () => setState(() => _deleting = null)),
                DesignAlertAction('Удалить', () {
                  app.deleteTuning(deleting['id'] as String);
                  setState(() {
                    _deleting = null;
                    _openRow = null;
                  });
                }, role: DesignAlertRole.destructive),
              ],
              dismiss: () => setState(() => _deleting = null),
            ),
    );
  }
}

// MARK: «Добавить строй»

/// «Добавить строй» (top 420, over the tunings): from the library, generated, by hand.
class TuningsAddSheet extends StatelessWidget {
  const TuningsAddSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lib = _core(app, 'instrument.library', {'category': null, 'query': ''});
    final count = lib is List ? lib.fold<int>(0, (a, g) => a + ((g as Map)['templates'] as List).length) : 0;
    // Card 16 pt padding: icon tile 44 (radius 12), title 16 semibold, subtitle 12 (line height 1.35), chevron.
    Widget option(Widget icon, String title, String subtitle, VoidCallback onTap) => Pressable(
      onTap: onTap,
      child: ShapeBox(
        shape: const SwiftShape.rounded(16),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Padding(
          padding: const EdgeInsets.all(17), // padding 16 + the 1 pt border outside it (CSS content-box)
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: ShapeBox(
                  shape: const SwiftShape.rounded(12),
                  fills: [SwiftFill(TruverColors.white(0.06))],
                  child: Center(child: icon),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwiftText(title, style: Typo.inter(16, TypoWeight.semibold, TruverColors.textPrimary)),
                    const SizedBox(height: 3),
                    // CSS line-height 1.35: half-leading above and below the lines too.
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 0.85),
                      child: SwiftText(subtitle, style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary), lineSpacing: 1.7),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _chevron,
            ],
          ),
        ),
      ),
    );

    return OverTunings(
      child: DesignSheet(
        title: 'Добавить строй',
        height: 424,
        close: () => app.sheet = const AppSheet('tunings'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(
              const AppIconView(AppIcon.search, size: 22, color: TruverColors.textBody),
              'Из библиотеки',
              '$count ${plural(count, 'готовый строй', 'готовых строя', 'готовых строев')}: Drop, Open, полтона ниже и др.',
              () => app.sheet = const AppSheet('library'),
            ),
            const SizedBox(height: 10),
            option(
              const EditGlyph(size: 22, color: TruverColors.textBody),
              'Сгенерировать',
              'Опустить строй, сделать Drop или Open — по шагам',
              () => app.sheet = const AppSheet('generator'),
            ),
            const SizedBox(height: 10),
            option(
              const AppIconView(AppIcon.plus, size: 22, color: TruverColors.textBody),
              'Вручную',
              'Ноту каждой струны выбираете сами',
              () => _addManual(app),
            ),
          ],
        ),
      ),
    );
  }

  /// «Вручную»: a copy of the current tuning, not saved until «Сохранить».
  void _addManual(AppModel app) {
    final copy = jsonCopy(app.tuning);
    copy['id'] = newUuid();
    copy['name'] = uniqueTuningName(app, 'Свой строй');
    copy['isTemplateCopy'] = false;
    copy.remove('templateId');
    app.unsavedTuning = copy;
    app.sheet = AppSheet('tuningEditor', copy['id']);
  }
}

// MARK: «Редактор строя»

/// «<строй> · редактор» (top 54): strings from the lowest (cents offset, ± semitone), A4 and accidentals, frets and
/// capo of the instrument; the list scrolls in a 560 pt window with a fade. Leaving with changes asks «Сохранить
/// изменения?» — «Сохранить как «Drop D»» when the edit makes another library tuning. The title renames.
class TuningEditorSheet extends StatefulWidget {
  const TuningEditorSheet({super.key, required this.tuningId});

  final String tuningId;

  @override
  State<TuningEditorSheet> createState() => _TuningEditorSheetState();
}

class _TuningEditorSheetState extends State<TuningEditorSheet> {
  Map<String, dynamic>? _draft;
  bool _askSave = false;
  bool _naming = false;
  final _name = TextEditingController();

  AppModel get app => AppScope.read(context);

  /// The tuning as stored, or the unsaved copy being created.
  Map<String, dynamic>? get _original {
    final stored = app.tunings.where((t) => t['id'] == widget.tuningId).firstOrNull;
    if (stored != null) return stored;
    final unsaved = app.unsavedTuning;
    return unsaved != null && unsaved['id'] == widget.tuningId ? unsaved : null;
  }

  bool get _isNew => !app.tunings.any((t) => t['id'] == widget.tuningId);

  @override
  void initState() {
    super.initState();
    // Canvas «Сохранить изменения?»: the 6th string E2 → D2.
    final original = _original;
    if (TuningsDebug.unsaved && original != null) {
      TuningsDebug.unsaved = false;
      final t = jsonCopy(original);
      final open = t['openCents'] as List;
      open[0] = [for (final s in open[0] as List) (s as num).toDouble() - 200];
      t['isTemplateCopy'] = false;
      _draft = t;
      _askSave = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _edit(void Function(Map<String, dynamic> t) change) {
    final base = _draft ?? _original;
    if (base == null) return;
    final t = jsonCopy(base);
    change(t);
    t['isTemplateCopy'] = false;
    setState(() => _draft = t);
  }

  void _setCents(int course, double cents) => _edit((t) {
    final open = t['openCents'] as List;
    var offsets = (t['offsetsCents'] as List?) ?? [];
    if (offsets.length != open.length) {
      offsets = [
        for (final c in open) [for (final _ in c as List) 0.0],
      ];
    }
    offsets[course] = [for (final _ in offsets[course] as List) cents];
    t['offsetsCents'] = offsets;
  });

  void _shift(int course, int semitones) => _edit((t) {
    final open = t['openCents'] as List;
    open[course] = [for (final s in open[course] as List) (s as num).toDouble() + semitones * 100];
  });

  void _save() {
    if (_isNew) {
      final tuning = _draft ?? _original;
      if (tuning == null) return;
      _addTuning(app, tuning);
      app.unsavedTuning = null;
      return;
    }
    final draft = _draft;
    if (draft == null) return;
    app.updateInstrument((i) {
      final tunings = i['tunings'] as List;
      final index = tunings.indexWhere((t) => (t as Map)['id'] == draft['id']);
      if (index >= 0) tunings[index] = draft;
    });
  }

  /// The edit as another tuning; the original stays as it was.
  void _saveAsNew(Map<String, dynamic> draft, String name, String? templateId) {
    final copy = jsonCopy(draft);
    copy['id'] = newUuid();
    copy['name'] = uniqueTuningName(app, name);
    if (templateId != null) {
      copy['templateId'] = templateId;
    } else {
      copy.remove('templateId');
    }
    _addTuning(app, copy);
    _exit();
  }

  void _close() {
    final draft = _draft;
    if (draft != null && jsonEncode(draft) != jsonEncode(_original)) {
      setState(() => _askSave = true);
    } else {
      _leave();
    }
  }

  /// Leaving without saving drops an unsaved copy.
  void _leave() {
    if (_isNew) app.unsavedTuning = null;
    _exit();
  }

  void _exit() {
    final fromTuner = app.tuningEditorFromTuner;
    app.tuningEditorFromTuner = false;
    app.sheet = fromTuner ? null : const AppSheet('tunings');
  }

  /// 60 pt: number 13 (14 wide), note 18, offset «0 ц» 12, − 40 · note 16 medium (46) · + 40.
  Widget _stringRow(Map<String, dynamic> tuning, List<String> spelled, int course) {
    final open = tuning['openCents'] as List;
    final offsets = (tuning['offsetsCents'] as List?) ?? const [];
    final offset = course < offsets.length && (offsets[course] as List).isNotEmpty ? ((offsets[course] as List).first as num).toDouble() : 0.0;
    // The tuning's own spelling (E♭ standard after lowering, not D♯), not the chromatic default.
    final note = course < spelled.length ? spelled[course] : app.chromaticName(((open[course] as List).first as num).toDouble());
    String centsText(double c) => c == 0 ? '0 ц' : '${c > 0 ? '+' : '−'}${c.abs().toInt()} ц';
    return Semantics(
      label: 'Струна ${open.length - course}, $note',
      container: true,
      child: _ruled(
        SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Row(
              children: [
                SizedBox(width: 14, child: Text('${open.length - course}', style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary))),
                const SizedBox(width: 12),
                Expanded(child: NoteText(note, style: Typo.inter(18, TypoWeight.regular, TruverColors.textPrimary))),
                const SizedBox(width: 12),
                // PR-3 «нота или центы»: the cents are their own control (± stays a semitone).
                MenuButton(
                  label: 'Отстройка в центах: ${offset.toInt()}',
                  items: () => [
                    for (final c in const [-50, -30, -20, -10, -5, 0, 5, 10, 20, 30, 50])
                      MenuItem(centsText(c.toDouble()), () => _setCents(course, c.toDouble())),
                  ],
                  child: Text(
                    centsText(offset),
                    style: Typo.inter(12, TypoWeight.regular, offset == 0 ? TruverColors.textTertiary : TruverColors.sharp),
                  ),
                ),
                const SizedBox(width: 12),
                RoundIconButton(icon: AppIcon.minus, size: 40, iconSize: 16, label: 'Ниже на полутон', onTap: () => _shift(course, -1)),
                const SizedBox(width: 2),
                SizedBox(
                  width: 46,
                  child: NoteText(note, textAlign: TextAlign.center, style: Typo.inter(16, TypoWeight.medium, TruverColors.textPrimary)),
                ),
                const SizedBox(width: 2),
                RoundIconButton(icon: AppIcon.plus, size: 40, iconSize: 16, label: 'Выше на полутон', onTap: () => _shift(course, 1)),
              ],
            ),
          ),
        ),
        true,
      ),
    );
  }

  Widget _fields(AppModel app, Map<String, dynamic> tuning) {
    final defaultA4 = app.settings.defaultA4.toInt();
    final frets = (app.instrument['fretCount'] as num).toInt(), capo = (app.instrument['capo'] as num).toInt();
    final spelled = spellTunings(app, [tuning]).first;
    final count = (tuning['openCents'] as List).length;
    final a4 = (tuning['a4'] as num?)?.toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption(text: 'Струны · от низкой · шаг — полутон'),
        Card(children: [for (var c = 0; c < count; c++) _stringRow(tuning, spelled, c)]),
        const SizedBox(height: 14),
        const SectionCaption(text: 'Строй'),
        Card(
          children: [
            // A4 of this tuning right here (it opened the Settings root and lost the editor — UX check).
            MenuButton(
              items: () => [
                MenuItem('Как в настройках · $defaultA4 Гц', () => _edit((t) => t.remove('a4'))),
                for (final hz in const [415, 430, 432, 435, 438, 440, 441, 442, 443, 444, 446])
                  MenuItem('$hz Гц', () => _edit((t) => t['a4'] = hz.toDouble())),
              ],
              child: _ruled(
                CardRow(showsDivider: false, title: 'A4', trailing: _valueChevron(a4 != null ? '$a4 Гц' : 'Как в настройках · $defaultA4 Гц')),
              ),
            ),
            _ruled(
              CardRow(
                showsDivider: false,
                title: 'Знаки',
                trailing: SizedBox(
                  width: 150,
                  child: Segments<String>(
                    options: const [('sharp', '♯'), ('flat', '♭'), ('auto', 'Авто')],
                    selection: tuning['accidentalPreference'] as String? ?? 'auto',
                    onChanged: (v) => _edit((t) => t['accidentalPreference'] = v),
                    size: SegmentsSize.compact,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Frets and capo belong to the instrument, but they are looked for here (user: «почему в редакторе
        // строя нету?») — they apply at once to every tuning of this instrument.
        const SectionCaption(text: 'Гриф · для всего инструмента'),
        Card(
          children: [
            MenuButton(
              items: () => [
                for (final n in ({20, 21, 22, 24, 27, frets}.toList()..sort()))
                  MenuItem('$n ${plural(n, 'лад', 'лада', 'ладов')}', () => app.updateInstrument((i) => i['fretCount'] = n)),
              ],
              child: _ruled(CardRow(showsDivider: false, title: 'Ладов', trailing: _valueChevron('$frets'))),
            ),
            MenuButton(
              items: () => _capoItems(app),
              child: _ruled(CardRow(showsDivider: false, title: 'Капо', trailing: _valueChevron(_capoText(capo)))),
            ),
          ],
        ),
      ],
    );
  }

  /// «Сохранить изменения?»: another library tuning → «Сохранить как «Drop D»» / «Заменить «Стандарт E»»;
  /// otherwise «Сохранить» / «Сохранить как новый»; «Не сохранять» last.
  Widget _saveAlert(Map<String, dynamic> original, Map<String, dynamic> draft) {
    final change = _map(_core(app, 'instrument.change', {'original': original, 'draft': draft})) ?? const {};
    final match = change['match'] as String?;
    void done() => setState(() => _askSave = false);
    final actions = <DesignAlertAction>[
      if (_isNew)
        DesignAlertAction('Сохранить', () {
          done();
          _save();
          _exit();
        }, role: DesignAlertRole.preferred)
      else if (match != null) ...[
        DesignAlertAction('Сохранить как «$match»', () {
          done();
          _saveAsNew(draft, match, change['matchId'] as String?);
        }, role: DesignAlertRole.preferred),
        DesignAlertAction('Заменить «${original['name']}»', () {
          done();
          _save();
          _exit();
        }),
      ] else ...[
        DesignAlertAction('Сохранить', () {
          done();
          _save();
          _exit();
        }, role: DesignAlertRole.preferred),
        DesignAlertAction('Сохранить как новый', () {
          done();
          _saveAsNew(draft, draft['name'] as String? ?? '', change['matchId'] as String?);
        }),
      ],
      DesignAlertAction('Не сохранять', () {
        done();
        _leave();
      }, role: DesignAlertRole.destructive),
    ];
    return DesignAlert(
      title: 'Сохранить изменения?',
      message: _isNew ? 'Строй «${draft['name']}» ещё не сохранён.' : change['message'] as String? ?? '',
      actions: actions,
      dismiss: done,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final original = _original;
    final tuning = _draft ?? original;

    Widget? overlay;
    if (_askSave && original != null && tuning != null) {
      overlay = _saveAlert(original, tuning);
    } else if (_naming) {
      overlay = TextFieldAlert(
        title: 'Название строя',
        controller: _name,
        cancel: () => setState(() => _naming = false),
        save: () {
          final trimmed = _name.text.trim();
          if (trimmed.isNotEmpty) _edit((t) => t['name'] = trimmed);
          setState(() => _naming = false);
        },
      );
    }

    final sheet = DesignSheet(
      title: '${tuning?['name'] ?? 'Строй'} · редактор',
      height: 790,
      close: _close,
      footer: [
        Expanded(
          child: SheetButton(
            title: 'Сохранить',
            onTap: () {
              _save();
              _exit();
            },
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Bleed(
            amount: 20,
            child: SizedBox(height: 1, child: ColoredBox(color: TruverColors.white(0.08))),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 560,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: tuning == null ? const SizedBox.shrink() : _fields(app, tuning),
                    ),
                  ),
                ),
                Positioned(
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
                          colors: [TruverColors.panel.withValues(alpha: 0), TruverColors.panel],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return _withOverlay(
      Stack(
        children: [
          sheet,
          // The title renames the tuning (the canvas has no «Название» row any more).
          Positioned(
            left: 20,
            top: 28,
            width: 280,
            height: 40,
            child: Semantics(
              button: true,
              label: 'Переименовать строй',
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() {
                  _name.text = tuning?['name'] as String? ?? '';
                  _naming = true;
                }),
              ),
            ),
          ),
        ],
      ),
      overlay,
    );
  }
}

// MARK: «Библиотека строев»

/// «Библиотека строев» (top 60, over the tunings): search, kinds «Все / Drop / Open / Ниже / Альтернативные», templates
/// for this instrument with «+» or «добавлен»; a row opens the template card. Nothing found → generator or by hand.
class LibrarySheet extends StatefulWidget {
  const LibrarySheet({super.key});

  @override
  State<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<LibrarySheet> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  String? _category;

  static const _kinds = [(null, 'Все'), ('drop', 'Drop'), ('open', 'Open'), ('lower', 'Ниже'), ('alternative', 'Альтернативные')];

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    if (TuningsDebug.libraryCategory != null) {
      _category = TuningsDebug.libraryCategory;
      TuningsDebug.libraryCategory = null;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _templateRow(AppModel app, Map<String, dynamic> template) {
    final exists = template['exists'] == true;
    return Pressable(
      scale: 1,
      onTap: () => app.sheet = AppSheet('templateCard', template['id']),
      child: TuningListRow(
        name: template['name'] as String,
        notes: template['notes'] as String,
        trailing: exists
            ? ShapeBox(
                shape: const SwiftShape.rounded(10),
                strokes: [SwiftStroke(TruverColors.white(0.12), inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  child: SwiftText('добавлен', style: Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
                ),
              )
            : Pressable(
                key: ValueKey('add ${template['id']}'),
                scale: 1,
                label: 'Добавить ${template['name']}',
                onTap: () => app.addTemplate(template['id'] as String),
                child: const TouchArea(child: AppIconView(AppIcon.plus, size: 18, color: TruverColors.textPrimary)),
              ),
      ),
    );
  }

  Widget _empty(AppModel app) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ShapeBox(
        shape: const SwiftShape.rounded(18, continuous: true),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const SizedBox(
                width: 52,
                height: 52,
                child: ShapeBox(
                  shape: SwiftShape.circle,
                  fills: [SwiftFill(TruverColors.fill)],
                  strokes: [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                  child: Center(child: AppIconView(AppIcon.search, size: 22, color: TruverColors.textTertiary)),
                ),
              ),
              const SizedBox(height: 12),
              SwiftText('Ничего не найдено', style: Typo.inter(17, TypoWeight.medium, TruverColors.textBody)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: SwiftText(
                  'Строя «${_query.text}» нет. Соберите его сами',
                  textAlign: TextAlign.center,
                  style: Typo.caption.copyWith(color: TruverColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _OutlineCapsule(title: 'Сгенерировать', height: 50, onTap: () => app.sheet = const AppSheet('generator')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _OutlineCapsule(
              title: 'Вручную',
              height: 50,
              onTap: () {
                final copy = jsonCopy(app.tuning);
                copy['id'] = newUuid();
                copy['name'] = _query.text.isEmpty ? 'Свой строй' : _query.text;
                copy['isTemplateCopy'] = false;
                copy.remove('templateId');
                app.unsavedTuning = copy;
                app.sheet = AppSheet('tuningEditor', copy['id']);
              },
            ),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final result = _core(app, 'instrument.library', {'category': _category, 'query': _query.text});
    final groups = result is List ? [for (final g in result) Map<String, dynamic>.from(g as Map)] : <Map<String, dynamic>>[];
    final n = _courses(app.instrument).length;

    return OverTunings(
      child: DesignSheet(
        title: 'Библиотека строев',
        height: 784,
        close: () => app.sheet = const AppSheet('tunings'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _focus.requestFocus,
              child: SizedBox(
                height: 44,
                child: ShapeBox(
                  shape: const SwiftShape.rounded(12),
                  fills: [SwiftFill(TruverColors.white(0.07))],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const AppIconView(AppIcon.search, size: 16, color: TruverColors.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              if (_query.text.isEmpty)
                                IgnorePointer(
                                  child: Text('Поиск: Drop, Open, ноты…', style: Typo.inter(15, TypoWeight.regular, TruverColors.textTertiary)),
                                ),
                              EditableText(
                                controller: _query,
                                focusNode: _focus,
                                style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary),
                                cursorColor: TruverColors.flat,
                                backgroundCursorColor: TruverColors.textTertiary,
                                selectionColor: TruverColors.flat.withValues(alpha: 0.35),
                                textInputAction: TextInputAction.search,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Bleed(
              amount: 20,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (var i = 0; i < _kinds.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Pressable(
                        scale: 1,
                        selected: _category == _kinds[i].$1,
                        onTap: () => setState(() => _category = _kinds[i].$1),
                        child: Chip(text: _kinds[i].$2, style: _category == _kinds[i].$1 ? ChipStyle.emphasized : ChipStyle.plain),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              _empty(app)
            else ...[
              for (var g = 0; g < groups.length; g++) ...[
                if (g > 0) const SizedBox(height: 12),
                SectionCaption(text: groups[g]['title'] as String),
                Card(children: [for (final t in (groups[g]['templates'] as List).cast<Map>()) _templateRow(app, Map<String, dynamic>.from(t))]),
              ],
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.15), // + CSS line-height 1.4 half-leading
                child: SwiftText(
                  'Показаны строи для $n ${n % 10 == 1 && n % 100 != 11 ? 'струны' : 'струн'}. Другие инструменты — сменить вверху списка строёв.',
                  style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary),
                  lineSpacing: 2.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// MARK: Template card

/// Template card (top 150): read-only; strings with Hz, intervals, where it is used, A4; «Добавить в мои строи».
class TemplateCardSheet extends StatelessWidget {
  const TemplateCardSheet({super.key, required this.templateId});
  final String templateId;

  static String hz(double f) => f < 100 ? f.toStringAsFixed(1) : '${f.round()}';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final card = _map(_core(app, 'instrument.templateCard', {'id': templateId}));
    final a4 = app.settings.defaultA4.toInt();
    final caption = Typo.caption.copyWith(color: TruverColors.textTertiary);
    return DesignSheet(
      title: card?['name'] as String? ?? 'Шаблон',
      height: 694,
      close: () => app.sheet = const AppSheet('library'),
      footer: [
        Expanded(
          child: SheetButton(
            title: 'Добавить в мои строи',
            icon: AppIcon.plus,
            onTap: () {
              if (card != null) app.addTemplate(templateId);
              app.sheet = const AppSheet('tunings');
            },
          ),
        ),
      ],
      child: card == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Chip(text: 'Шаблон', icon: AppIcon.lock, style: ChipStyle.muted),
                    const SizedBox(width: 8),
                    Chip(text: card['chip'] as String),
                  ],
                ),
                const SizedBox(height: 14),
                SwiftText('Струны · от низкой · Гц', style: caption),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final (i, s) in (card['strings'] as List).cast<Map>().indexed) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          children: [
                            SwiftText('${s['number']}', style: Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
                            const SizedBox(height: 4),
                            ShapeBox(
                              shape: const SwiftShape.rounded(10, continuous: true),
                              fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                              strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 40, minWidth: double.infinity),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: NoteText(
                                      s['note'] as String,
                                      maxLines: 1,
                                      style: Typo.inter(14, TypoWeight.semibold, TruverColors.textPrimary),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            SwiftText(hz((s['hz'] as num).toDouble()), style: Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Card(
                  children: [
                    _MultilineRow(title: 'Интервалы', value: card['intervals'] as String, notes: true),
                    _MultilineRow(title: 'Где встречается', value: card['usage'] as String),
                    CardRow(title: 'A4', showsDivider: false, trailing: Text('$a4 Гц')),
                  ],
                ),
                const SizedBox(height: 14),
                SwiftText('Шаблон не редактируется. После добавления — обычный строй, его можно менять', style: caption),
              ],
            ),
    );
  }
}

/// A [CardRow] whose trailing text wraps, right-aligned (`.multilineTextAlignment(.trailing)`): SwiftUI's HStack
/// gives the title and the value about half of the row each.
class _MultilineRow extends StatelessWidget {
  const _MultilineRow({required this.title, required this.value, this.notes = false});
  final String title;
  final String value;
  final bool notes;

  @override
  Widget build(BuildContext context) {
    final style = Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary);
    return _divided(
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, box) {
              // HStack(spacing 10) { title; Spacer(minLength 8); value }: the title takes its own width, the value
              // the rest less both spacings and the spacer (it wraps at «8-» on iOS: 168 of 173 pt).
              final titlePainter = TextPainter(
                text: TextSpan(text: title, style: Typo.row),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final titleWidth = titlePainter.width;
              titlePainter.dispose();
              final valueWidth = (box.maxWidth - titleWidth - 28).clamp(0.0, box.maxWidth);
              return Row(
                children: [
                  SwiftText(title, style: Typo.row.copyWith(color: TruverColors.textBody)),
                  const Spacer(),
                  const SizedBox(width: 18),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: valueWidth),
                    child: notes
                        ? SwiftText.rich(Typo.notes(value, style), style: style, textAlign: TextAlign.right)
                        : SwiftText(value, style: style, textAlign: TextAlign.right),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      true,
    );
  }
}

// MARK: «Генератор строя»

/// «Генератор строя» (top 150, over the tunings): from the current tuning — Drop (the lowest string down by N, the
/// others by M), everything lower, Open (a major chord); «Получится» with a slack warning; «Добавить «Drop C»» or,
/// when such a tuning is already saved, «Переключиться на …». The core builds it (`instrument.recipe`).
class GeneratorSheet extends StatefulWidget {
  const GeneratorSheet({super.key});

  @override
  State<GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<GeneratorSheet> {
  String _mode = 'drop';
  int _dropLowest = 2;
  int _dropRest = 0;
  int _lower = 1;
  int _openRoot = 7;

  static const _roots = [7, 2, 4, 9, 0, 5, 11];

  @override
  void initState() {
    super.initState();
    final demo = TuningsDebug.generator;
    if (demo != null) {
      TuningsDebug.generator = null;
      _mode = 'drop';
      _dropLowest = demo.$1;
      _dropRest = demo.$2;
    }
  }

  Map<String, dynamic> get _params => {'mode': _mode, 'lowest': _dropLowest, 'rest': _dropRest, 'semitones': _lower, 'root': _openRoot};

  /// «без изменений», «на полтона ниже», «на 1 тон ниже»…
  static String restText(int semitones) => semitones == 0 ? 'без изменений' : 'на ${semitones == 1 ? 'полтона' : tonesText(semitones)} ниже';

  List<Widget> _parameters(AppModel app, int n, List<String> roots) {
    String rootName(int pc) {
      final i = _roots.indexOf(pc);
      return '${i >= 0 && i < roots.length ? roots[i] : ''} мажор';
    }

    switch (_mode) {
      case 'lower':
        return [
          _ruled(
            _StepperRow(
              title: 'Опустить все струны на',
              stepper: _NarrowStepper(
                value: tonesText(_lower),
                canDecrement: _lower > 1,
                canIncrement: _lower < 12,
                decrement: () => setState(() => _lower--),
                increment: () => setState(() => _lower++),
              ),
            ),
          ),
        ];
      case 'open':
        return [
          MenuButton(
            items: () => [for (final pc in _roots) MenuItem(rootName(pc), () => setState(() => _openRoot = pc))],
            child: _ruled(CardRow(showsDivider: false, title: 'Аккорд', minHeight: 52, trailing: _valueChevron(rootName(_openRoot), notes: true))),
          ),
        ];
      default:
        return [
          _ruled(
            _StepperRow(
              title: 'Опустить $n-ю струну\nна', // «на» alone on the second line, as on the canvas and iOS
              stepper: _NarrowStepper(
                value: tonesText(_dropLowest),
                canDecrement: _dropLowest > _dropRest + 1,
                canIncrement: _dropLowest < 12,
                decrement: () => setState(() => _dropLowest--),
                increment: () => setState(() => _dropLowest++),
              ),
            ),
          ),
          MenuButton(
            items: () => [
              for (var s = 0; s <= 5; s++)
                MenuItem(
                  restText(s),
                  () => setState(() {
                    _dropRest = s;
                    if (_dropLowest < s + 1) _dropLowest = s + 1;
                  }),
                ),
            ],
            child: _ruled(CardRow(showsDivider: false, title: 'Остальные струны', minHeight: 52, trailing: _valueChevron(restText(_dropRest)))),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final r = _map(_core(app, 'instrument.recipe', _params)) ?? const {};
    final name = r['name'] as String? ?? '';
    final same = _map(r['same']);
    final warning = r['warning'] as String?;
    final roots = ((r['roots'] as List?) ?? const []).cast<String>();
    final n = _courses(app.instrument).length;

    return OverTunings(
      child: DesignSheet(
        title: 'Генератор строя',
        height: 694,
        close: () => app.sheet = const AppSheet('tunings'),
        footer: [
          Expanded(
            child: same != null
                ? SheetButton(
                    title: 'Переключиться на «${same['name']}»',
                    onTap: () {
                      app.selectTuning(same['id'] as String);
                      app.sheet = const AppSheet('tunings');
                    },
                  )
                : SheetButton(
                    title: 'Добавить «$name»',
                    onTap: () {
                      _replaceInstrument(app, _core(app, 'instrument.recipe', {..._params, 'add': true}));
                      app.sheet = const AppSheet('tunings');
                    },
                  ),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionCaption(text: 'Что сделать'),
            Card(
              children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Segments<String>(
                    options: const [('drop', 'Drop'), ('lower', 'Ниже всё'), ('open', 'Open')],
                    selection: _mode,
                    onChanged: (v) => setState(() => _mode = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionCaption(text: 'Параметры'),
            Card(children: _parameters(app, n, roots)),
            const SizedBox(height: 14),
            const SectionCaption(text: 'Получится'),
            Card(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _notes(name, 20, weight: TypoWeight.semibold, color: TruverColors.textPrimary),
                      const SizedBox(height: 8),
                      _notes(r['notes'] as String? ?? '', 15, color: TruverColors.textBody, tracking: 1.2),
                      if (warning != null) ...[
                        const SizedBox(height: 8),
                        SwiftText(warning, style: Typo.inter(12, TypoWeight.regular, TruverColors.sharp)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: «Инструмент»

/// Scale length without a set one: bass 864, ukulele 330, mandolin 350, guitars 648 / 686 (8+).
int defaultScale(Map<String, dynamic> i) => switch (i['type']) {
  'bass' => 864,
  'ukulele' => 330,
  'mandolin' => 350,
  _ => _courses(i).length >= 8 ? 686 : 648,
};

/// «Инструмент» (top 150): name, type, strings (with rebuild), paired courses, frets, capo; strings and scale.
class InstrumentSheet extends StatefulWidget {
  const InstrumentSheet({super.key});

  @override
  State<InstrumentSheet> createState() => _InstrumentSheetState();
}

class _InstrumentSheetState extends State<InstrumentSheet> {
  bool _naming = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _scaleText(Map<String, dynamic> i) {
    final m = _map(i['multiscale']);
    if (m != null) return '${(m['bassScaleLength'] as num).round()}–${(m['trebleScaleLength'] as num).round()} мм';
    for (final c in _courses(i)) {
      final strings = (c['strings'] as List).cast<Map>();
      final l = strings.isEmpty ? null : strings.first['scaleLength'] as num?;
      if (l != null) return '${l.toInt()} мм';
    }
    return '${defaultScale(i)} мм';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final i = app.instrument;
    final courses = _courses(i);
    final n = courses.length;
    final frets = (i['fretCount'] as num).toInt(), capo = (i['capo'] as num).toInt();
    final paired = courses.any((c) => c['pairing'] != 'single');

    return _withOverlay(
      DesignSheet(
        title: 'Инструмент',
        height: 694,
        close: () => app.sheet = const AppSheet('tunings'),
        footer: [
          Expanded(
            child: SheetButton(title: 'Готово', onTap: () => app.sheet = const AppSheet('tunings')),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              children: [
                Pressable(
                  scale: 1,
                  onTap: () => setState(() {
                    _name.text = i['name'] as String? ?? '';
                    _naming = true;
                  }),
                  child: _ruled(CardRow(showsDivider: false, title: 'Название', minHeight: 52, trailing: Text(i['name'] as String? ?? ''))),
                ),
                _ruled(
                  CardRow(
                    showsDivider: false,
                    title: 'Тип',
                    minHeight: 52,
                    trailing: _valueChevron(capitalizedFirst(instrumentTypeName(i['type'] as String? ?? ''))),
                  ),
                ),
                _ruled(
                  CardRow(
                    showsDivider: false,
                    title: 'Число струн',
                    subtitle: 'строи пересоберутся',
                    minHeight: 62,
                    trailing: ValueStepper(
                      value: '$n',
                      canDecrement: n > 1,
                      canIncrement: n < 12,
                      decrement: () => app.sheet = AppSheet('instrumentRebuild', n - 1),
                      increment: () => app.sheet = AppSheet('instrumentRebuild', n + 1),
                    ),
                  ),
                ),
                _ruled(
                  CardRow(
                    showsDivider: false,
                    title: 'Сдвоенные курсы',
                    minHeight: 52,
                    trailing: ToggleSwitch(
                      isOn: paired,
                      onChanged: (on) => _replaceInstrument(app, _core(app, 'instrument.setPaired', {'on': on})),
                      label: 'Сдвоенные курсы',
                    ),
                  ),
                ),
                _ruled(
                  CardRow(
                    showsDivider: false,
                    title: 'Число ладов',
                    subtitle: 'обычно 21–27',
                    minHeight: 62,
                    trailing: ValueStepper(
                      value: '$frets',
                      canDecrement: frets > 12,
                      canIncrement: frets < 30,
                      decrement: () => app.updateInstrument((i) => i['fretCount'] = frets - 1),
                      increment: () => app.updateInstrument((i) => i['fretCount'] = frets + 1),
                    ),
                  ),
                ),
                MenuButton(
                  items: () => _capoItems(app),
                  child: _ruled(CardRow(showsDivider: false, title: 'Капо', minHeight: 52, trailing: _valueChevron(_capoText(capo)))),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionCaption(text: 'Струны'),
            Card(
              children: [
                Pressable(
                  scale: 1,
                  onTap: () => app.sheet = const AppSheet('instrumentStrings'),
                  child: _ruled(CardRow(showsDivider: false, title: 'Калибры и мензура', minHeight: 52, trailing: _valueChevron(_scaleText(i)))),
                ),
              ],
            ),
          ],
        ),
      ),
      !_naming
          ? null
          : TextFieldAlert(
              title: 'Название инструмента',
              controller: _name,
              cancel: () => setState(() => _naming = false),
              save: () {
                final trimmed = _name.text.trim();
                if (trimmed.isNotEmpty) app.updateInstrument((i) => i['name'] = trimmed);
                setState(() => _naming = false);
              },
            ),
    );
  }
}

// MARK: «N струн вместо M»

/// «9 струн вместо 8» (top 230): side, affected tunings with the added note, low-range warning.
class InstrumentRebuildSheet extends StatefulWidget {
  const InstrumentRebuildSheet({super.key, required this.newCount});
  final int newCount;

  @override
  State<InstrumentRebuildSheet> createState() => _InstrumentRebuildSheetState();
}

class _InstrumentRebuildSheetState extends State<InstrumentRebuildSheet> {
  bool _high = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final n = widget.newCount;
    final old = app.courseCount;
    final r = _map(_core(app, 'instrument.rebuild', {'count': n, 'high': _high})) ?? {};
    final rows = (r['rows'] as List? ?? const []).cast<Map>();
    final warning = r['warning'] as String?;

    return DesignSheet(
      title: '$n ${plural(n, 'струна', 'струны', 'струн')} вместо $old',
      height: 614,
      close: () => app.sheet = const AppSheet('instrument'),
      footer: [
        Expanded(
          child: _OutlineCapsule(
            title: 'Отмена',
            height: 54,
            style: Typo.button.copyWith(color: TruverColors.textBody),
            onTap: () => app.sheet = const AppSheet('instrument'),
          ),
        ),
        Expanded(
          child: SheetButton(
            title: 'Пересобрать',
            onTap: () {
              _replaceInstrument(app, _core(app, 'instrument.rebuild', {'count': n, 'high': _high})?['instrument']);
              app.sheet = const AppSheet('instrument');
            },
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwiftText(
            n > old
                ? 'Строи пересоберутся: в каждом появится новая струна на кварту от крайней.'
                : 'Строи пересоберутся: крайняя струна уйдёт из каждого строя.',
            style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SwiftText('С какой стороны', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
          const SizedBox(height: 8),
          Segments<bool>(options: const [(false, 'Снизу'), (true, 'Сверху')], selection: _high, onChanged: (v) => setState(() => _high = v)),
          const SizedBox(height: 14),
          const SectionCaption(text: 'Затронутые строи'),
          Card(
            children: [
              for (final (i, row) in rows.indexed)
                CardRow(
                  title: row['name'] as String,
                  showsDivider: i < rows.length - 1,
                  trailing: NoteText(row['change'] as String, style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
                ),
            ],
          ),
          if (warning != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const AppIconView(AppIcon.warning, size: 14, color: TruverColors.sharp),
                const SizedBox(width: 8),
                Expanded(child: _notes(warning, 13, color: TruverColors.sharp)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// MARK: «Струны»

enum _FanField { bass, treble }

/// «Струны» (top 60): scale length (one for all, fan frets — v1.x), string set, gauges per string.
class InstrumentStringsSheet extends StatefulWidget {
  const InstrumentStringsSheet({super.key});

  @override
  State<InstrumentStringsSheet> createState() => _InstrumentStringsSheetState();
}

class _InstrumentStringsSheetState extends State<InstrumentStringsSheet> {
  int? _editing;
  bool _editingScale = false;
  _FanField? _editingFan;
  final _text = TextEditingController();

  AppModel get app => AppScope.read(context);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _scale {
    final courses = _courses(app.instrument);
    final strings = courses.isEmpty ? const [] : (courses.first['strings'] as List);
    final l = strings.isEmpty ? null : (strings.first as Map)['scaleLength'] as num?;
    return l?.toInt() ?? defaultScale(app.instrument);
  }

  /// `String(format: "%.2f″")` without trailing zeros, as on iOS.
  static String inches(double mm) => '${(mm / 25.4).toStringAsFixed(2)}″'.replaceAll('.00″', '″').replaceAll('0″', '″');

  void _setStrings(Map<String, dynamic> inst, void Function(Map<String, dynamic> string, int course) change) {
    for (final (c, course) in _courses(inst).indexed) {
      for (final s in (course['strings'] as List).cast<Map<String, dynamic>>()) {
        change(s, c);
      }
    }
  }

  /// PR-7: on — a typical fan for this instrument; off — one scale (the treble one, as on most single-scale twins).
  void _setFanned(bool on) {
    if (on) {
      _replaceInstrument(app, _core(app, 'instrument.applyFan', {'preset': 0}));
    } else {
      final m = _map(app.instrument['multiscale']);
      final treble = m != null ? (m['trebleScaleLength'] as num).round() : _scale;
      app.updateInstrument((inst) {
        inst.remove('multiscale');
        _setStrings(inst, (s, _) => s['scaleLength'] = treble.toDouble());
      });
    }
  }

  void _applyFan(Map<String, dynamic> m) => _replaceInstrument(app, _core(app, 'instrument.applyFan', {'multiscale': m}));

  void _updateFan(void Function(Map<String, dynamic> m) change) {
    final m = _map(app.instrument['multiscale']);
    if (m == null) return;
    change(m);
    _applyFan(m);
  }

  void _setScale(int value) => app.updateInstrument((inst) => _setStrings(inst, (s, _) => s['scaleLength'] = value.toDouble()));

  /// Gauges listed from the lowest string.
  void _applySet(List<double> gauges) => app.updateInstrument((inst) {
    _setStrings(inst, (s, c) {
      if (c < gauges.length) s['gauge'] = gauges[c];
    });
  });

  /// 44 pt rows: number, note, gauge field «.074», «оплётка / гладкая», scale.
  Widget _stringRow(int course, int scale, bool last) {
    final courses = _courses(app.instrument);
    final strings = (courses[course]['strings'] as List).cast<Map>();
    final gauge = strings.isEmpty ? null : (strings.first['gauge'] as num?)?.toDouble();
    final open = app.tuning['openCents'] as List;
    final note = course < open.length ? app.chromaticName(((open[course] as List).first as num).toDouble()) : '';
    final caption = Typo.caption.copyWith(color: TruverColors.textTertiary);
    return _divided(
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(width: 16, child: Text('${courses.length - course}', style: caption)),
              const SizedBox(width: 10),
              SizedBox(width: 36, child: NoteText(note, maxLines: 1, style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary))),
              const SizedBox(width: 10),
              Pressable(
                scale: 1,
                onTap: () => setState(() {
                  _text.text = gauge?.toStringAsFixed(3) ?? '';
                  _editing = course;
                }),
                child: ShapeBox(
                  shape: const SwiftShape.rounded(8),
                  fills: [SwiftFill(TruverColors.white(0.06))],
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: SizedBox(
                      width: 70,
                      height: 32,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          gauge == null ? '—' : '.${(gauge * 1000).round().toString().padLeft(3, '0')}',
                          style: Typo.inter(14, TypoWeight.regular, TruverColors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(gauge == null ? 'калибр не задан' : (gauge >= 0.02 ? 'оплётка' : 'гладкая'), style: caption),
              const Spacer(),
              const SizedBox(width: 10),
              Text('$scale', style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary)),
            ],
          ),
        ),
      ),
      !last,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final i = app.instrument;
    final m = _map(i['multiscale']);
    final info = _map(_core(app, 'instrument.strings', const {})) ?? {};
    final presets = (info['fanPresets'] as List? ?? const []).cast<Map>();
    final sets = (info['sets'] as List? ?? const []).cast<Map>();
    final scales = (info['scales'] as List? ?? const []).cast<num>();
    final courseCount = _courses(i).length;
    final scale = _scale;

    Widget? overlay;
    final field = _editingFan;
    if (field != null) {
      overlay = TextFieldAlert(
        title: field == _FanField.bass ? 'Мензура басовой струны, мм' : 'Мензура высокой струны, мм',
        controller: _text,
        cancel: () => setState(() => _editingFan = null),
        save: () {
          final value = double.tryParse(_text.text.trim());
          if (value != null && value >= 300 && value <= 1000) {
            _updateFan((m) => m[field == _FanField.bass ? 'bassScaleLength' : 'trebleScaleLength'] = value);
          }
          setState(() => _editingFan = null);
        },
      );
    } else if (_editingScale) {
      overlay = TextFieldAlert(
        title: 'Мензура, мм',
        controller: _text,
        cancel: () => setState(() => _editingScale = false),
        save: () {
          final value = int.tryParse(_text.text.trim());
          if (value != null && value >= 300 && value <= 1000) _setScale(value);
          setState(() => _editingScale = false);
        },
      );
    } else if (_editing != null) {
      final course = _editing!;
      overlay = TextFieldAlert(
        title: 'Калибр, дюймы',
        controller: _text,
        cancel: () => setState(() => _editing = null),
        save: () {
          final value = double.tryParse(_text.text.replaceAll(',', '.'));
          app.updateInstrument((inst) {
            for (final s in (_courses(inst)[course]['strings'] as List).cast<Map<String, dynamic>>()) {
              if (value == null) {
                s.remove('gauge');
              } else {
                s['gauge'] = value;
              }
            }
          });
          setState(() => _editing = null);
        },
      );
    }

    return _withOverlay(
      DesignSheet(
        title: 'Струны',
        height: 784,
        close: () => app.sheet = const AppSheet('instrument'),
        footer: [
          Expanded(
            child: SheetButton(title: 'Готово', onTap: () => app.sheet = const AppSheet('instrument')),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              children: [
                CardRow(
                  title: 'Веерные лады',
                  subtitle: m == null ? 'одна мензура на все струны' : 'своя мензура у каждой струны',
                  trailing: ToggleSwitch(isOn: m != null, onChanged: _setFanned, label: 'Веерные лады'),
                ),
                if (m != null) ...[
                  for (final f in _FanField.values)
                    Builder(
                      builder: (context) {
                        final mm = ((f == _FanField.bass ? m['bassScaleLength'] : m['trebleScaleLength']) as num).toDouble();
                        return Pressable(
                          scale: 1,
                          onTap: () => setState(() {
                            _text.text = '${mm.round()}';
                            _editingFan = f;
                          }),
                          child: CardRow(
                            title: f == _FanField.bass ? 'Басовая струна' : 'Высокая струна',
                            subtitle: inches(mm),
                            trailing: _valueChevron('${mm.round()} мм'),
                          ),
                        );
                      },
                    ),
                  MenuButton(
                    items: () => [
                      for (var fret = 0; fret <= 14; fret++)
                        MenuItem(fret == 0 ? 'Порожек' : '$fret-й лад', () => _updateFan((m) => m['neutralFret'] = fret)),
                    ],
                    child: CardRow(
                      title: 'Нейтральный лад',
                      subtitle: 'лад под прямым углом к струнам',
                      trailing: _valueChevron((m['neutralFret'] as num).toInt() == 0 ? 'Порожек' : '${(m['neutralFret'] as num).toInt()}-й'),
                    ),
                  ),
                  MenuButton(
                    items: () => [
                      for (final p in presets) MenuItem(p['name'] as String, () => _applyFan(Map<String, dynamic>.from(p['multiscale'] as Map))),
                    ],
                    child: CardRow(title: 'Типовой веер', trailing: _valueChevron(info['fanPresetName'] as String? ?? 'Свой')),
                  ),
                ] else
                  Pressable(
                    scale: 1,
                    onTap: () => setState(() {
                      _text.text = '$scale';
                      _editingScale = true;
                    }),
                    child: CardRow(title: 'Мензура', subtitle: 'одна на все струны', trailing: _valueChevron('$scale мм')),
                  ),
                CardRow(
                  title: 'Комплект',
                  subtitle: 'подставит калибры',
                  showsDivider: false,
                  trailing: MenuButton(
                    items: () => [
                      for (final s in sets)
                        MenuItem(s['name'] as String, () => _applySet([for (final g in s['gauges'] as List) (g as num).toDouble()])),
                    ],
                    child: _valueChevron(info['currentSet'] as String? ?? 'Свой'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionCaption(text: 'Калибр струн'),
            Card(
              children: [for (var c = 0; c < courseCount; c++) _stringRow(c, c < scales.length ? scales[c].toInt() : scale, c == courseCount - 1)],
            ),
          ],
        ),
      ),
      overlay,
    );
  }
}

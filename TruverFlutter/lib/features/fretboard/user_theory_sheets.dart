/// Port of Truver/Sources/Features/Fretboard/UserTheorySheets.swift
///
/// TH-8 «Своя гамма» and «Свой аккорд»: the user's own scales and chords (stored in the settings, sent to the core's
/// `UserLibrary` by `AppModel`). Labels, spelling and the built-in twins come from the core (`fretboard.*Draft`).
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'fret_modes.dart';
import 'fretboard_controller.dart';

String _shortId() => newUuid().substring(0, 8).toLowerCase();

/// A 44 pt text field of the sheets.
class NameField extends StatefulWidget {
  const NameField({super.key, required this.prompt, required this.controller});
  final String prompt;
  final TextEditingController controller;

  @override
  State<NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<NameField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ShapeBox(
          shape: const SwiftShape.rounded(12, continuous: true),
          fills: [SwiftFill(TruverColors.white(0.06))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ValueListenableBuilder(
                  valueListenable: widget.controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? IgnorePointer(
                          child: Text.rich(Typo.notes(widget.prompt, Typo.inter(15, TypoWeight.regular, TruverColors.textTertiary)), maxLines: 1),
                        )
                      : const SizedBox.shrink(),
                ),
                EditableText(
                  controller: widget.controller,
                  focusNode: _focus,
                  style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary),
                  cursorColor: TruverColors.flat,
                  backgroundCursorColor: TruverColors.textTertiary,
                  selectionColor: TruverColors.flat.withValues(alpha: 0.35),
                  autocorrect: false,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
      );
}

Widget _toggleCell({required String label, required String note, required bool on, required VoidCallback onTap}) => Pressable(
      selected: on,
      label: '$label, $note',
      onTap: onTap,
      child: ShapeBox(
        shape: const SwiftShape.rounded(12, continuous: true),
        fills: [SwiftFill(on ? TruverColors.textPrimary.withValues(alpha: 0.12) : TruverColors.white(0.04))],
        strokes: [SwiftStroke(on ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true)],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52, minWidth: double.infinity),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            notesText(label, Typo.inter(15, TypoWeight.semibold, on ? TruverColors.textPrimary : TruverColors.textMuted)),
            const SizedBox(height: 2),
            notesText(note, Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
          ]),
        ),
      ),
    );

Widget _disabled(bool off, Widget child) => Opacity(opacity: off ? 0.4 : 1, child: IgnorePointer(ignoring: off, child: child));

/// TH-8 «Своя гамма»: name, 12 semitone toggles from the current tonic (degree + note), the built-in scale with the
/// same notes if there is one, «Прослушать», save / delete. Opened from «Гамма → Мои» and, prefilled with the neck
/// edits, from «Сохранить как свою».
class ScaleBuilderSheet extends StatefulWidget {
  const ScaleBuilderSheet({super.key, this.editingId});
  final String? editingId;

  @override
  State<ScaleBuilderSheet> createState() => _ScaleBuilderSheetState();
}

class _ScaleBuilderSheetState extends State<ScaleBuilderSheet> {
  final _name = TextEditingController();
  Set<int> _steps = {0};
  late final String _newId = 'user-scale-${_shortId()}';

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final existing = app.settings.customScales.where((s) => s['id'] == widget.editingId).firstOrNull;
    if (existing != null) {
      _name.text = ((existing['names'] as Map?)?['ru'] as String?) ?? '';
      _steps = {
        for (final d in (existing['degrees'] as List? ?? const [])) (((d as Map)['cents'] as num).toDouble() / 100).round() % 12,
      };
    } else {
      _steps = app.fretboard.editedSemitones.toSet();
    }
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _resolvedName(AppModel app) {
    final t = _name.text.trim();
    return t.isEmpty ? 'Моя гамма ${app.settings.customScales.length + 1}' : t;
  }

  Map<String, dynamic> _draft(AppModel app) {
    final r = coreCall(app, 'fretboard.scaleDraft', {
      'id': widget.editingId ?? _newId,
      'name': _resolvedName(app),
      'semitones': (_steps.toList()..sort()),
      'tonic': app.fretboard.settings.tonic,
    });
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  void _play(AppModel app) {
    final tonic = notePitchClass(app.fretboard.settings.tonic);
    final base = (48 + tonic - 69) * 100.0;
    final steps = [...(_steps.toList()..sort()), 12];
    app.audio.ensurePlayback();
    app.audio.call('audio.playNotes', {
      'notes': [for (var i = 0; i < steps.length; i++) {'cents': base + steps[i] * 100, 'offset': i * 0.22}],
    });
  }

  void _save(AppModel app, Map<String, dynamic> draft) {
    final scale = draft['scale'];
    if (scale is! Map) return;
    final json = Map<String, dynamic>.from(scale);
    app.updateSettings((s) {
      final i = s.customScales.indexWhere((x) => x['id'] == json['id']);
      if (i >= 0) {
        s.customScales[i] = json;
      } else {
        s.customScales.add(json);
      }
    });
    app.fretboard.setScale(json['id'] as String);
    app.sheet = null;
  }

  void _delete(AppModel app) {
    final id = widget.editingId;
    if (id == null) return;
    app.updateSettings((s) => s.customScales.removeWhere((x) => x['id'] == id));
    if (app.fretboard.settings.scaleId == id) app.fretboard.setScale('major');
    app.sheet = const AppSheet('fretScale');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final draft = _draft(app);
    final steps = [for (final s in (draft['steps'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
    final twin = draft['twin'] as String?;
    final n = _steps.length;
    return DesignSheet(
      title: widget.editingId == null ? 'Своя гамма' : 'Изменить гамму',
      height: 700,
      close: () => app.sheet = const AppSheet('fretScale'),
      footer: [
        Expanded(child: _disabled(n < 3, SheetButton(title: 'Сохранить и показать', onTap: () => _save(app, draft)))),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NameField(prompt: 'Моя гамма ${app.settings.customScales.length + 1}', controller: _name),
          const SizedBox(height: 14),
          SectionCaption(text: 'Ступени от ${app.fretboard.data?.tonicText ?? ''} · $n ${ruPlural(n, 'нота', 'ноты', 'нот')}'),
          const SizedBox(height: 6),
          for (var row = 0; row < 3; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(children: [
              for (var col = 0; col < 4; col++) ...[
                if (col > 0) const SizedBox(width: 6),
                Expanded(
                  child: () {
                    final semis = row * 4 + col;
                    final step = semis < steps.length ? steps[semis] : const <String, dynamic>{};
                    return _toggleCell(
                      label: step['label'] as String? ?? '',
                      note: step['note'] as String? ?? '',
                      on: _steps.contains(semis),
                      onTap: () {
                        if (semis == 0) return;
                        setState(() => _steps.contains(semis) ? _steps.remove(semis) : _steps.add(semis));
                      },
                    );
                  }(),
                ),
              ],
            ]),
          ],
          if (twin != null) ...[
            const SizedBox(height: 14),
            SwiftText('Те же ноты, что у «$twin»', style: Typo.caption.copyWith(color: TruverColors.textSecondary)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Pressable(onTap: () => _play(app), child: const Chip(text: '▶ Прослушать', style: ChipStyle.muted)),
            if (widget.editingId != null) ...[
              const SizedBox(width: 8),
              Pressable(onTap: () => _delete(app), child: const Chip(text: 'Удалить', style: ChipStyle.muted)),
            ],
          ]),
        ],
      ),
    );
  }
}

/// TH-8 «Свой аккорд»: degree toggles (♭3 3 4 … ♯11 13), symbol written after the root, the built-in chord with the
/// same notes, «Прослушать», save / delete. Opened from the chord library («+ Свой»).
class ChordBuilderSheet extends StatefulWidget {
  const ChordBuilderSheet({super.key, this.editingId});
  final String? editingId;

  @override
  State<ChordBuilderSheet> createState() => _ChordBuilderSheetState();
}

class _ChordBuilderSheetState extends State<ChordBuilderSheet> {
  final _symbol = TextEditingController();
  late final String _newId = 'user-chord-${_shortId()}';

  /// Selected degrees as «number:accidental».
  Set<String> _degrees = {'3:0', '5:0'};

  static const choices = [
    [(2, 0), (3, -1), (3, 0), (4, 0)],
    [(5, -1), (5, 0), (5, 1), (6, 0)],
    [(7, -2), (7, -1), (7, 0), (9, -1)],
    [(9, 0), (9, 1), (11, 0), (11, 1)],
    [(13, -1), (13, 0)],
  ];

  static String _key(int n, int a) => '$n:$a';
  static String _labelText(int n, int a) => '${a > 0 ? '♯' * a : (a == -1 ? '♭' : (a == -2 ? '𝄫' : ''))}$n';

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final existing = app.settings.customChords.where((c) => c['id'] == widget.editingId).firstOrNull;
    if (existing != null) {
      _symbol.text = existing['symbol'] as String? ?? '';
      _degrees = {
        for (final d in (existing['degrees'] as List? ?? const []))
          if (((d as Map)['label'] as Map)['number'] != 1 || (d['label'] as Map)['accidental'] != 0)
            _key(((d['label'] as Map)['number'] as num).toInt(), ((d['label'] as Map)['accidental'] as num).toInt()),
      };
    }
    _symbol.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _symbol.dispose();
    super.dispose();
  }

  List<Map<String, int>> get _labels => [
        for (final k in _degrees) {'number': int.parse(k.split(':')[0]), 'accidental': int.parse(k.split(':')[1])},
      ];

  Map<String, dynamic> _draft(AppModel app) {
    final r = coreCall(app, 'fretboard.chordDraft', {
      'id': widget.editingId ?? _newId,
      'symbol': _symbol.text,
      'labels': _labels,
      'root': app.fretboard.chordRoot,
      'choices': [
        for (final row in choices)
          for (final (n, a) in row) {'number': n, 'accidental': a},
      ],
    });
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  void _play(AppModel app, Map<String, dynamic> draft) {
    final root = notePitchClass(app.fretboard.chordRoot);
    final base = (48 + root - 69) * 100.0;
    final degrees = ((draft['chord'] as Map?)?['degrees'] as List?) ?? const [];
    app.audio.ensurePlayback();
    app.audio.call('audio.playNotes', {
      'notes': [
        for (var i = 0; i < degrees.length; i++) {'cents': base + ((degrees[i] as Map)['cents'] as num).toDouble(), 'offset': i * 0.03},
      ],
    });
  }

  void _save(AppModel app, Map<String, dynamic> draft) {
    final chord = draft['chord'];
    if (chord is! Map) return;
    final json = Map<String, dynamic>.from(chord);
    app.updateSettings((s) {
      final i = s.customChords.indexWhere((x) => x['id'] == json['id']);
      if (i >= 0) {
        s.customChords[i] = json;
      } else {
        s.customChords.add(json);
      }
    });
    final fretboard = app.fretboard;
    fretboard.chordId = json['id'] as String;
    if (fretboard.mode != FretMode.chord && fretboard.mode != FretMode.progression) fretboard.mode = FretMode.chord;
    app.sheet = null;
  }

  void _delete(AppModel app) {
    final id = widget.editingId;
    if (id == null) return;
    app.updateSettings((s) => s.customChords.removeWhere((x) => x['id'] == id));
    if (app.fretboard.chordId == id) app.fretboard.chordId = 'maj';
    app.sheet = null;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final draft = _draft(app);
    final notes = (draft['choiceNotes'] as List? ?? const []).cast<String>();
    final rootText = draft['rootText'] as String? ?? '';
    final symbol = _symbol.text.trim().isEmpty ? draft['autoSymbol'] as String? ?? '' : _symbol.text.trim();
    final twin = draft['twin'] is Map ? Map<String, dynamic>.from(draft['twin'] as Map) : null;
    var noteIndex = 0;
    return DesignSheet(
      title: widget.editingId == null ? 'Свой аккорд' : 'Изменить аккорд',
      height: 700,
      close: () => app.sheet = null,
      footer: [
        Expanded(child: _disabled(_degrees.length < 2, SheetButton(title: 'Сохранить и показать', onTap: () => _save(app, draft)))),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NameField(prompt: 'Обозначение, например maj7♯11no3', controller: _symbol),
          const SizedBox(height: 14),
          SectionCaption(text: 'Ступени от $rootText · 1 всегда звучит'),
          const SizedBox(height: 6),
          for (var r = 0; r < choices.length; r++) ...[
            if (r > 0) const SizedBox(height: 6),
            Row(children: [
              for (var c = 0; c < 4; c++) ...[
                if (c > 0) const SizedBox(width: 6),
                Expanded(
                  child: c < choices[r].length
                      ? () {
                          final (n, a) = choices[r][c];
                          final note = noteIndex < notes.length ? notes[noteIndex] : '';
                          noteIndex += 1;
                          final key = _key(n, a);
                          return _toggleCell(
                            label: _labelText(n, a),
                            note: note,
                            on: _degrees.contains(key),
                            onTap: () => setState(() => _degrees.contains(key) ? _degrees.remove(key) : _degrees.add(key)),
                          );
                        }()
                      : const SizedBox(height: 52),
                ),
              ],
            ]),
          ],
          const SizedBox(height: 14),
          notesText('$rootText$symbol · ${draft['spelled'] ?? ''}', Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
          if (twin != null) ...[
            const SizedBox(height: 14),
            notesText('Уже есть в библиотеке: $rootText${twin['symbol']} · ${twin['name']}',
                Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Pressable(onTap: () => _play(app, draft), child: const Chip(text: '▶ Прослушать', style: ChipStyle.muted)),
            if (widget.editingId != null) ...[
              const SizedBox(width: 8),
              Pressable(onTap: () => _delete(app), child: const Chip(text: 'Удалить', style: ChipStyle.muted)),
            ],
          ]),
        ],
      ),
    );
  }
}

/// Port of Truver/Sources/Features/Fretboard/ProgressionController.swift
///
/// «Прогрессия» (FB-11, FB-22, FB-24): a progression from the library in a key, voiced with voice leading over the
/// whole neck or inside a hand window around a chosen note; the ribbon shows the chords, the neck the current chord
/// and the next one faintly; playback strums on the metronome's tempo with a count-in and loops. Voicing and the
/// strum schedule come from the core (`progression.*`).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import 'fretboard_controller.dart';
import 'neck_portrait.dart';

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final e in v) _map(e)] : const [];
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Core `ProgressionChord`: degree 1…7, accidental, chord type, bars.
class ProgressionChord {
  ProgressionChord({required this.degree, this.accidental = 0, required this.chordId, this.bars = 1});
  factory ProgressionChord.fromJson(Map<String, dynamic> j) =>
      ProgressionChord(degree: _i(j['degree']), accidental: _i(j['accidental']), chordId: j['chordId'] as String? ?? 'maj', bars: math.max(1, _i(j['bars'])));
  int degree;
  int accidental;
  String chordId;
  int bars;

  Map<String, dynamic> toJson() => {'degree': degree, 'accidental': accidental, 'chordId': chordId, 'bars': bars};
  ProgressionChord copy() => ProgressionChord.fromJson(toJson());
}

/// A chord row of the shown progression (numeral and name in the key).
class ProgressionRow {
  ProgressionRow(Map<String, dynamic> j)
      : chord = ProgressionChord.fromJson(j),
        numeral = j['numeral'] as String? ?? '',
        root = _map(j['root']),
        name = j['name'] as String? ?? '',
        isMinor = j['isMinor'] == true;
  final ProgressionChord chord;
  final String numeral;
  final Map<String, dynamic> root;
  final String name;
  final bool isMinor;
}

/// A chord of a voiced progression: the chosen voicing, or null when the chord does not fit the instrument at all;
/// `outOfWindow` — the nearest voicing outside the hand window («вне позиции», FB-22).
class VoicedChord {
  VoicedChord(Map<String, dynamic> j)
      : root = _map(j['root']),
        chordId = j['chordId'] as String? ?? 'maj',
        name = j['name'] as String? ?? '',
        letterName = j['letterName'] as String? ?? '',
        chord = ChordData(_map(j['chord'])),
        voicing = j['voicing'] is Map ? ChordVoicing(_map(j['voicing'])) : null,
        outOfWindow = j['outOfWindow'] == true;
  final Map<String, dynamic> root;
  final String chordId;
  final String name;

  /// In letters also in solfège (`chordFormatter`).
  final String letterName;
  final ChordData chord;
  ChordVoicing? voicing;
  bool outOfWindow;
}

/// A progression the user saved under a name.
class SavedProgression {
  SavedProgression({String? id, required this.name, required this.key, required this.chords, this.bpm, this.note}) : id = id ?? newUuid();
  factory SavedProgression.fromJson(Map<String, dynamic> j) => SavedProgression(
        id: j['id'] as String?,
        name: j['name'] as String? ?? '',
        key: _map(j['key']),
        chords: [for (final c in _maps(j['chords'])) ProgressionChord.fromJson(c)],
        bpm: (j['bpm'] as num?)?.toInt(),
        note: j['note'] as String?,
      );
  final String id;
  String name;
  Map<String, dynamic> key;
  List<ProgressionChord> chords;

  /// «♩=92» in «Мои прогрессии»: the tempo it was saved with.
  int? bpm;

  /// Subtitle in «Мои прогрессии» («поп», «рок-баллада»); null — the number of chords.
  String? note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': key,
        'chords': [for (final c in chords) c.toJson()],
        if (bpm != null) 'bpm': bpm,
        if (note != null) 'note': note,
      };
}

/// Strum rhythms of the «Ритм» sheet (core `StrumRhythm`).
enum StrumRhythm { perBar, perBeat, downUpEighths }

class ProgressionController extends ChangeNotifier {
  late AppModel _app;
  AppModel get app => _app;
  set app(AppModel value) {
    _app = value;
    final s = value.store;
    _templateId = s.getString('pr.template') ?? 'pop';
    final custom = s.getString('pr.custom');
    if (custom != null) {
      try {
        _custom = [for (final c in jsonDecode(custom) as List) ProgressionChord.fromJson(_map(c))];
      } catch (_) {}
    }
    final saved = s.getString('pr.saved');
    if (saved != null) {
      try {
        _saved = [for (final p in jsonDecode(saved) as List) SavedProgression.fromJson(_map(p))];
      } catch (_) {}
    }
    _showsDegrees = s.getString('pr.degrees') == 'true';
    barsPerChordValue = int.tryParse(s.getString('pr.bars') ?? '');
    _rhythm = StrumRhythm.values.where((r) => r.name == s.getString('pr.rhythm')).firstOrNull ?? StrumRhythm.perBar;
    _loop = s.getString('pr.loop') != 'false';
    _click = s.getString('pr.click') == 'true';
  }

  dynamic _core(String method, Map<String, dynamic> params) {
    try {
      return app.core?.call(method, params);
    } catch (e) {
      debugPrint('$method: $e');
      return null;
    }
  }

  bool _pendingNotify = false;

  void changed() {
    if (inBuildPhase) {
      if (_pendingNotify) return;
      _pendingNotify = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _pendingNotify = false;
        // A sheet that closed together with the whole app (tests) notifies an already disposed model.
        try {
          notifyListeners();
          app.changed();
        } on FlutterError catch (_) {}
      });
      return;
    }
    notifyListeners();
    app.changed();
  }

  FretboardController get _fretboard => app.fretboard;

  String _templateId = 'pop';
  String get templateId => _templateId;
  set templateId(String v) {
    _templateId = v;
    app.store.setString('pr.template', v);
    _activeSavedId = null;
    _setCustom(null);
    recompute();
  }

  /// The user's own progression (chords replaced, added or removed); null = the template as is.
  List<ProgressionChord>? _custom;
  List<ProgressionChord>? get custom => _custom;
  void _setCustom(List<ProgressionChord>? v) {
    _custom = v;
    if (v != null) {
      app.store.setString('pr.custom', jsonEncode([for (final c in v) c.toJson()]));
    } else {
      app.store.remove('pr.custom');
    }
  }

  /// «Мои прогрессии»: kept by name; the open one follows every edit.
  List<SavedProgression> _saved = [];
  List<SavedProgression> get saved => _saved;
  void _storeSaved() => app.store.setString('pr.saved', jsonEncode([for (final p in _saved) p.toJson()]));

  String? _activeSavedId;
  SavedProgression? get activeSaved => _saved.where((p) => p.id == _activeSavedId).firstOrNull;

  /// The bar's beat while playing (0-based), for the dots on the current chord.
  int? playingBeat;

  /// Voicings the user picked for single chords (index → index into that chord's alternatives).
  final Map<int, int> _overrides = {};
  final Map<int, List<ChordVoicing>> _alternatives = {};

  /// Neck labels: note names or degrees of the chord.
  bool _showsDegrees = false;
  bool get showsDegrees => _showsDegrees;
  set showsDegrees(bool v) {
    _showsDegrees = v;
    app.store.setString('pr.degrees', '$v');
    changed();
  }

  Map<String, dynamic> _key = {'letter': 2, 'accidental': 0};
  Map<String, dynamic> get key => _key;
  set key(Map<String, dynamic> v) {
    _key = v;
    _overrides.clear();
    final active = activeSaved;
    if (active != null) {
      active.key = v;
      _storeSaved();
    }
    recompute();
  }

  /// FB-22 «Прогрессия отсюда»: the first chord's lowest note, and the window's lowest fret (null = whole neck).
  NeckSpot? anchor;
  int? windowStart;

  // «Ритм» sheet (FB-24).
  /// null = each chord's own bars (the 12-bar blues keeps its form).
  int? barsPerChordValue;
  int? get barsPerChord => barsPerChordValue;
  set barsPerChord(int? v) {
    barsPerChordValue = v;
    if (v == null) {
      app.store.remove('pr.bars');
    } else {
      app.store.setString('pr.bars', '$v');
    }
    changed();
  }

  StrumRhythm _rhythm = StrumRhythm.perBar;
  StrumRhythm get rhythm => _rhythm;
  set rhythm(StrumRhythm v) {
    _rhythm = v;
    app.store.setString('pr.rhythm', v.name);
    changed();
  }

  bool _loop = true;
  bool get loop => _loop;
  set loop(bool v) {
    _loop = v;
    app.store.setString('pr.loop', '$v');
    changed();
  }

  /// Metronome click with a bar of count-in. Off by default (user: «нажимаю сыграть — метроном включается»).
  bool _click = false;
  bool get click => _click;
  set click(bool v) {
    _click = v;
    app.store.setString('pr.click', '$v');
    changed();
  }

  List<VoicedChord> voiced = [];
  List<ProgressionRow> rows = [];
  List<({String id, String name})> templates = [];
  String _name = '';
  String keyText = '';

  /// The chord shown (selected, or sounding while playing).
  int current = 0;
  bool isPlaying = false;
  int _generation = 0;

  bool get isCustom => _custom != null;

  /// The template's name, or the saved one's, or «Своя · по «…»».
  String get name {
    if (_custom == null) return _name;
    return activeSaved?.name ?? 'Своя · по «$_name»';
  }

  String get templateName => _name;

  /// «G мажор» / «G минор»: by the first chord of the progression.
  bool get isMinor => rows.firstOrNull?.isMinor ?? false;

  List<ProgressionChord> get chords => _custom ?? [for (final r in rows) r.chord];

  /// Entering from «Гамма»: the scale's tonic and a progression that fits its mode (an edited one stays).
  void syncFromScale(ScaleInfo? scale, Map<String, dynamic> tonic) {
    if (_custom != null || _activeSavedId != null || scale == null) return;
    final semitones = scale.semitones.map((s) => (s % 12 + 12) % 12).toSet();
    final minorThird = semitones.contains(3) && !semitones.contains(4);
    _loadNames();
    if (semitones.contains(1) && !semitones.contains(2)) {
      if (_templateId != 'phrygian') _templateId = 'phrygian';
    } else if (minorThird != isMinor) {
      _templateId = minorThird ? 'aeolian' : 'pop';
    }
    app.store.setString('pr.template', _templateId);
    key = tonic;
  }

  // MARK: Editing

  void _edit(void Function(List<ProgressionChord> chords) change) {
    final list = [for (final c in chords) c.copy()];
    change(list);
    if (list.isEmpty) return;
    _setCustom(list);
    _overrides.clear();
    final active = activeSaved;
    if (active != null) {
      active.chords = list;
      _storeSaved();
    }
    recompute();
  }

  void insertChord(ProgressionChord chord, int index) {
    _edit((c) => c.insert(index.clamp(0, c.length), chord));
    current = index.clamp(0, chords.length - 1);
    _strumCurrent();
  }

  /// Moves a chord to another place in the ribbon; the shown chord stays the moved one.
  void moveChord(int from, int to) {
    final count = chords.length;
    if (from == to || from < 0 || from >= count || to < 0 || to >= count) return;
    _edit((c) => c.insert(to, c.removeAt(from)));
    current = to;
    changed();
  }

  // MARK: My progressions

  void saveAs(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final item = SavedProgression(name: trimmed, key: _key, chords: [for (final c in chords) c.copy()], bpm: _fretboard.bpm.round());
    _saved.add(item);
    _storeSaved();
    _setCustom(item.chords);
    _activeSavedId = item.id;
    changed();
  }

  void renameActive(String name) {
    final trimmed = name.trim();
    final active = activeSaved;
    if (trimmed.isEmpty || active == null) return;
    active.name = trimmed;
    _storeSaved();
    changed();
  }

  void open(SavedProgression item) {
    _activeSavedId = item.id;
    _setCustom([for (final c in item.chords) c.copy()]);
    _overrides.clear();
    current = 0;
    anchor = null;
    windowStart = null;
    key = item.key;
  }

  /// «Прогрессия от A» / «Новая прогрессия»: these chords in this key, as the user's own progression.
  void useChords(List<ProgressionChord> chords, Map<String, dynamic> newKey) {
    _activeSavedId = null;
    _setCustom(chords);
    _overrides.clear();
    current = 0;
    key = newKey;
    recompute();
  }

  /// The chords of numerals in a key (core `progression.palette`): chord and name.
  List<({ProgressionChord chord, String name})> chordsIn(Map<String, dynamic> inKey, List<String> numerals) {
    final r = _core('progression.palette', {'key': inKey, 'numerals': numerals});
    return [for (final m in _maps(r)) (chord: ProgressionChord.fromJson(_map(m['chord'])), name: m['name'] as String? ?? '')];
  }

  /// The pressed note as a key (simple spelling, flats for D♭ E♭ A♭ B♭ as `start`).
  Map<String, dynamic>? spotKey(NeckSpot spot) {
    final cell = _fretboard.coreCell(spot.course, spot.fret);
    if (cell == null) return null;
    final pc = centsPitchClass(cell.cents);
    final names = _core('fretboard.spellings', {
      'items': [
        {'pc': pc, 'flats': const [1, 3, 8, 10].contains(pc)},
      ],
    });
    final name = _maps(names).firstOrNull;
    return name == null ? null : _map(name['name']);
  }

  /// Debug `-progressionsDemo`: the three saved progressions of the canvas «Прогрессии».
  void injectSavedDemo() {
    SavedProgression make(String name, Map<String, dynamic> k, String numerals, int bpm, String? note) => SavedProgression(
          name: name,
          key: k,
          chords: [for (final c in chordsIn(k, numerals.split(' '))) c.chord],
          bpm: bpm,
          note: note,
        );
    const a = {'letter': 5, 'accidental': 0}, e = {'letter': 2, 'accidental': 0};
    _saved = [
      make('A · I–V–vi–IV', a, 'I V vi IV', 92, 'поп · 4 аккорда'),
      make('Am · i–VI–III–VII', a, 'i ♭VI ♭III ♭VII', 70, 'рок-баллада'),
      make('Блюз в E · 12 тактов', e, 'I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7', 110, 'I–IV–V'),
    ];
    _storeSaved();
    open(_saved.first);
  }

  void deleteActive() {
    final id = _activeSavedId;
    if (id == null) return;
    _saved.removeWhere((p) => p.id == id);
    _storeSaved();
    _activeSavedId = null;
    _setCustom(null);
    _overrides.clear();
    recompute();
  }

  void replaceChord(int index, ProgressionChord chord) {
    _edit((c) => c[index] = ProgressionChord(degree: chord.degree, accidental: chord.accidental, chordId: chord.chordId, bars: c[index].bars));
    if (index < voiced.length && !isPlaying) {
      final v = voiced[index].voicing;
      if (v != null) _fretboard.playVoicing(v);
    }
  }

  void addChord(ProgressionChord chord) {
    _edit((c) => c.add(chord));
    current = chords.length - 1;
    _strumCurrent();
  }

  void removeChord(int index) {
    if (chords.length <= 1) return;
    _edit((c) => c.removeAt(index));
    current = math.min(current, chords.length - 1);
    changed();
  }

  void setBars(int index, int bars) => _edit((c) => c[index].bars = bars.clamp(1, 8));

  void resetToTemplate() {
    _activeSavedId = null;
    _setCustom(null);
    _overrides.clear();
    recompute();
  }

  void _strumCurrent() {
    if (current < voiced.length && !isPlaying) {
      final v = voiced[current].voicing;
      if (v != null) _fretboard.playVoicing(v);
    }
  }

  /// Other voicings of one chord (inside the window when there is one), most comfortable first; the one on the
  /// neck now comes first, so it is always visible and marked.
  List<ChordVoicing> alternatives(int index) {
    if (index >= voiced.length) return const [];
    final v = voiced[index];
    final w = window;
    final r = _core('progression.alternatives', {
      'index': index,
      'root': v.root,
      'chordId': v.chordId,
      if (w != null) 'window': [w.$1, w.$2],
    });
    final list = [for (final m in _maps(r)) ChordVoicing(m)];
    _alternatives[index] = list;
    final shown = v.voicing;
    if (shown == null) return list;
    return [shown, ...list.where((x) => x != shown)];
  }

  void chooseVoicing(ChordVoicing voicing, int index) {
    if (index >= voiced.length) return;
    final alt = _alternatives[index]?.indexOf(voicing) ?? -1;
    if (alt >= 0) _overrides[index] = alt;
    voiced[index].voicing = voicing;
    voiced[index].outOfWindow = false;
    current = index;
    if (!isPlaying) _fretboard.playVoicing(voicing);
    changed();
  }

  /// Chords to add or put in place (in this key): the key's triads and sevenths, borrowed and secondary chords.
  static const palette = <(String, List<String>)>[
    ('Аккорды тональности', ['I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii°']),
    ('Септаккорды', ['Imaj7', 'ii7', 'iii7', 'IVmaj7', 'V7', 'vi7', 'viiø7']),
    ('Из минора и заимствованные', ['i', '♭II', '♭III', 'iv', 'v', '♭VI', '♭VII']),
    ('Доминанты к ступеням и другие', ['I7', 'II7', 'III7', 'VI7', 'VII7', 'Isus4', 'I5', 'V5']),
  ];

  /// The palette in the current key: numeral, chord, name.
  List<({String numeral, ProgressionChord chord, String name})> paletteChords(List<String> numerals) {
    final r = _core('progression.palette', {'key': _key, 'numerals': numerals});
    return [
      for (final m in _maps(r)) (numeral: m['numeral'] as String? ?? '', chord: ProgressionChord.fromJson(_map(m['chord'])), name: m['name'] as String? ?? ''),
    ];
  }

  /// «Любой аккорд»: a chord by root and type in the key.
  ({ProgressionChord chord, String name})? anyChord(Map<String, dynamic> root, String chordId) {
    final r = _core('progression.anyChord', {'root': root, 'key': _key, 'chordId': chordId});
    return r is Map ? (chord: ProgressionChord.fromJson(_map(r['chord'])), name: _map(r)['name'] as String? ?? '') : null;
  }

  int get _fretCount => _i(app.instrument['fretCount']);

  (int, int)? get window {
    final start = windowStart;
    if (start == null) return null;
    return (start, math.min(_fretCount, start + 4));
  }

  // MARK: Building

  /// Strings, tuning and frets the voicings were found for: re-voice only when they change.
  String _boardSignature = '';
  String _signature() => jsonEncode([app.tuning['openCents'], app.instrument['fretCount'], app.instrument['capo'], app.settings.notation]);

  void instrumentMayHaveChanged() {
    if (voiced.isEmpty || _signature() == _boardSignature) return;
    anchor = null;
    final start = windowStart;
    if (start != null) windowStart = math.min(start, math.max(1, _fretCount - 4));
    recompute();
  }

  void _loadNames() {
    final r = _core('progression.state', _stateParams(voice: false));
    _apply(_map(r), voice: false);
  }

  Map<String, dynamic> _stateParams({required bool voice}) {
    final w = window;
    final a = anchor;
    return {
      'templateId': _templateId,
      if (_custom != null) 'custom': [for (final c in _custom!) c.toJson()],
      'key': _key,
      if (w != null) 'window': [w.$1, w.$2],
      if (a != null) 'anchor': {'course': a.course, 'fret': a.fret},
      'loop': loop,
      'voice': voice,
    };
  }

  void _apply(Map<String, dynamic> m, {required bool voice}) {
    templates = [for (final t in _maps(m['templates'])) (id: t['id'] as String? ?? '', name: t['name'] as String? ?? '')];
    _name = m['name'] as String? ?? '';
    keyText = m['keyText'] as String? ?? '';
    rows = [for (final r in _maps(m['chords'])) ProgressionRow(r)];
    if (voice) voiced = [for (final v in _maps(m['voiced'])) VoicedChord(v)];
  }

  void recompute() {
    _boardSignature = _signature();
    if (isPlaying) stop();
    final r = _core('progression.state', _stateParams(voice: true));
    _apply(_map(r), voice: true);
    _alternatives.clear();
    // Picks survive only while the chords stay (cleared by edits and key changes).
    final overrides = Map.of(_overrides);
    _overrides.clear();
    for (final e in overrides.entries) {
      if (e.key < voiced.length) {
        final list = alternativesQuiet(e.key);
        if (e.value < list.length) {
          voiced[e.key].voicing = list[e.value];
          voiced[e.key].outOfWindow = false;
          _overrides[e.key] = e.value;
        }
      }
    }
    current = math.min(current, math.max(0, voiced.length - 1));
    changed();
  }

  List<ChordVoicing> alternativesQuiet(int index) {
    alternatives(index);
    return _alternatives[index] ?? const [];
  }

  /// FB-22: the note becomes the key and the first chord's bass; the hand window is a fret below and three above.
  void start(NeckSpot spot) {
    final cell = _fretboard.coreCell(spot.course, spot.fret);
    if (cell == null) return;
    // The key is the note itself: «i» and «I» are both built on it, so the first chord starts on the pressed note.
    final pc = centsPitchClass(cell.cents);
    final names = _core('fretboard.spellings', {
      'items': [
        {'pc': pc, 'flats': const [1, 3, 8, 10].contains(pc)},
      ],
    });
    final name = _maps(names).firstOrNull;
    if (name != null) _key = _map(name['name']);
    _overrides.clear();
    anchor = spot;
    final w = _core('progression.window', {'fret': spot.fret, 'fretCount': _fretCount});
    windowStart = w is List && w.isNotEmpty ? _i(w.first) : math.max(1, spot.fret - 1);
    current = 0;
    recompute();
    _fretboard.mode = FretMode.progression;
  }

  /// «‹ ›» around the window (FB-22): the progression is voiced again.
  void shiftWindow(int delta) {
    final start = windowStart;
    if (start == null) return;
    windowStart = (start + delta).clamp(1, math.max(1, _fretCount - 4));
    anchor = null; // the first chord is no longer tied to the original note
    recompute();
  }

  void useWholeNeck() {
    windowStart = null;
    anchor = null;
    recompute();
  }

  /// Key with a simple spelling (TH-7): the progression moves as a whole.
  void transpose(int semitones) {
    final r = _core('progression.transpose', {
      'templateId': _templateId,
      if (_custom != null) 'custom': [for (final c in _custom!) c.toJson()],
      'key': _key,
      'semitones': semitones,
    });
    if (r is Map) key = _map(r);
  }

  // MARK: Neck

  /// The current chord full, the next one faint («что дальше», FB-24): only its notes not shared with the current.
  List<NeckCell> cells() {
    if (current >= voiced.length) return [];
    final chord = voiced[current];
    final v = chord.voicing;
    if (v == null) return [];
    NeckCell cell(VoicingNote n, VoicedChord c, bool faint) {
      final rootPC = notePitchClass(c.root);
      final degree = c.chord.degrees.where((d) => (rootPC + d.semitones) % 12 == n.pc).firstOrNull;
      final role = n.pc == rootPC
          ? DegreeRole.tonic
          : (degree != null && (degree.number == 3 || degree.number == 5) ? DegreeRole.chordTone : DegreeRole.other);
      final name = c.chord.tones.where((t) => t.pc == n.pc).firstOrNull?.text ?? n.chroma;
      final label = showsDegrees ? (degree?.label ?? '') : name;
      return NeckCell(
        course: n.course,
        fret: n.fret,
        cents: n.cents,
        label: faint ? '' : label,
        role: role,
        emphasis: faint ? NeckEmphasis.faint : NeckEmphasis.full,
      );
    }

    final result = [for (final n in v.notes) cell(n, chord, false)];
    final nextIndex = current + 1 < voiced.length ? current + 1 : (loop ? 0 : null);
    if (nextIndex != null && nextIndex != current) {
      final next = voiced[nextIndex];
      final nv = next.voicing;
      if (nv != null) {
        final taken = {for (final n in v.notes) '${n.course}:${n.fret}'};
        result.addAll([for (final n in nv.notes) if (!taken.contains('${n.course}:${n.fret}')) cell(n, next, true)]);
      }
    }
    return result;
  }

  /// Frets on screen: the window, or the span of the current and next chords with a fret of air.
  (int, int) get visibleFrets {
    final maxFret = _fretCount;
    final w = window;
    if (w != null) return (math.max(0, w.$1 - 1), w.$2);
    final shown = [
      if (current < voiced.length) voiced[current].voicing,
      if (voiced.isNotEmpty) voiced[(current + 1) % math.max(1, voiced.length)].voicing,
    ].whereType<ChordVoicing>().toList();
    final fretted = [for (final v in shown) ...v.notes.map((n) => n.fret)].where((f) => f > 0).toList();
    final open = shown.any((v) => v.usesOpenStrings);
    final lo = open ? 0 : math.max(1, (fretted.isEmpty ? 1 : fretted.reduce(math.min)) - 1);
    return (lo, math.min(maxFret, math.max(lo + 4, (fretted.isEmpty ? lo : fretted.reduce(math.max)) + 1)));
  }

  /// Strings that do not sound in the current chord («×»).
  Set<int> get mutedCourses {
    if (current >= voiced.length) return {};
    final v = voiced[current].voicing;
    if (v == null) return {};
    return {for (var i = 0; i < v.frets.length; i++) if (v.frets[i] == null) i};
  }

  // MARK: Sound

  /// Tap on a chord in the ribbon: show it and strum it (FB-23).
  void select(int index) {
    if (index < 0 || index >= voiced.length) return;
    current = index;
    if (!isPlaying) {
      final v = voiced[index].voicing;
      if (v != null) _fretboard.playVoicing(v);
    }
    changed();
  }

  void toggle() => isPlaying ? stop() : play();

  bool _clickByPlayback = false;

  /// FB-24: count-in a bar (unless the metronome already plays — then from its next bar), the strokes of the
  /// rhythm on the metronome's tempo, the current chord follows the sound; with «По кругу» the next pass is
  /// scheduled one pass ahead at an exact sample.
  void play() {
    if (voiced.isEmpty) return;
    final meter = app.settings.metronome.meter;
    final bpm = _d(meter['bpm']);
    final numerator = _i(meter['numerator']);
    final wasPlaying = app.metronome.isPlaying;
    final startsClick = !wasPlaying && click;
    if (startsClick) {
      // TODO(android): `app.metronome.start(byPlayback: true)` once the metronome port has it.
      app.audio.call('audio.startMetronome', {'settings': meter});
      _clickByPlayback = true;
    }
    final r = _core('progression.schedule', {
      'overrides': [for (final e in _overrides.entries) [e.key, e.value]],
      'chordBars': [for (final c in chords) c.bars],
      'barsPerChord': ?barsPerChord,
      'beatsPerBar': numerator,
      'bpm': bpm,
      'rhythm': rhythm.name,
      'countInBars': startsClick ? 1 : 0,
    });
    final t = _map(r);
    final countIn = _d(t['countIn']), cycle = _d(t['cycle']);
    final chordStarts = [for (final s in (t['chordStarts'] as List? ?? const [])) _d(s)];
    List<Map<String, dynamic>> notes(double shift) => [
          for (final e in _maps(t['events']))
            for (final n in _maps(e['notes']))
              {'cents': _d(n['cents']), 'offset': _d(e['time']) - countIn + shift + _d(n['offset']), 'string': _i(n['course'])},
        ];
    app.audio.ensurePlayback();
    // With the metronome running (or just started for the count-in) — from its next bar; alone — at once.
    final res = app.audio.call('audio.playNotes', {
      'notes': notes(countIn),
      'start': wasPlaying || startsClick ? 'nextBar' : 'now',
      'delay': 0.1,
      'velocity': 0.75,
    });
    final lead = res is Map ? _d(res['lead']) : 0.1;
    final firstSample = res is Map ? _d(res['startSample']) : 0.0;
    final rate = res is Map ? _d(res['sampleRate']) : 48000.0;
    final looping = loop;
    isPlaying = true;
    current = 0;
    final generation = ++_generation;
    final clock = Stopwatch()..start();
    Future<void> sleepUntil(double seconds) async {
      final wait = seconds - clock.elapsedMicroseconds / 1e6;
      if (wait > 0) await Future<void>.delayed(Duration(microseconds: (wait * 1e6).round()));
    }

    // The beat of the bar, on the current chord's card (with or without the click).
    final beatLength = 60 / bpm;
    final beatsInBar = math.max(1, numerator);
    () async {
      var k = 0;
      while (generation == _generation) {
        await sleepUntil(lead + k * beatLength);
        if (generation != _generation) return;
        playingBeat = k % beatsInBar;
        k += 1;
        changed();
      }
    }();
    () async {
      var pass = 0;
      do {
        if (looping) {
          final next = firstSample + (countIn + (pass + 1) * cycle) * rate;
          app.audio.call('audio.playNotes', {'notes': notes(0), 'start': 'sample', 'sample': next.round(), 'velocity': 0.75});
        }
        for (var i = 0; i < chordStarts.length; i++) {
          await sleepUntil(lead + chordStarts[i] + pass * cycle);
          if (generation != _generation) return;
          current = i;
          changed();
        }
        await sleepUntil(lead + countIn + (pass + 1) * cycle);
        pass += 1;
      } while (looping && generation == _generation);
      if (generation != _generation) return;
      _finish();
    }();
    changed();
  }

  void stop() {
    _generation += 1;
    app.audio.call('audio.stopNotes');
    _finish();
  }

  void _finish() {
    _generation += 1;
    playingBeat = null;
    isPlaying = false;
    if (_clickByPlayback) {
      app.audio.call('audio.stopMetronome');
      _clickByPlayback = false;
    }
    changed();
  }
}

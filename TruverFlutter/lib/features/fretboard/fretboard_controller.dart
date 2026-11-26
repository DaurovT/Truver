/// Port of Truver/Sources/Features/Fretboard/FretboardController.swift
///
/// Fretboard screen state (6.2.5): scale, positions (FB-4…FB-6), labels and colours (FB-2, FB-3), edits (FB-7),
/// playback (FB-8), the key-chord strip (FB-17), modes (FB-26), chord (FB-9), search (FB-10), path (FB-20), the
/// note menu (FB-21, FB-25) and the drone (FB-13). The theory comes from the core (`fretboard.*` bridge commands);
/// this class keeps the screen logic of the Swift controller.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/typo.dart';
import 'neck_portrait.dart';
import 'progression_controller.dart';

// MARK: Core data

/// True while widgets are being built (notifications must wait for the end of the frame).
bool get inBuildPhase => SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks;

/// Pitch class of a core `NoteName` JSON (`{letter, accidental}`).
int notePitchClass(Map<String, dynamic> name) {
  const naturals = [0, 2, 4, 5, 7, 9, 11];
  return ((naturals[(name['letter'] as num).toInt()] + (name['accidental'] as num).toInt()) % 12 + 12) % 12;
}

/// Pitch class of a pitch in cents from A4.
int centsPitchClass(double cents) => ((69 + (cents / 100).round()) % 12 + 12) % 12;

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final e in v) _map(e)] : const [];
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// A note on the neck: course, fret, pitch and its degree in the shown scale.
class FretNote {
  FretNote(Map<String, dynamic> j)
      : course = _i(j['course']),
        fret = _i(j['fret']),
        cents = _d(j['cents']),
        degree = _i(j['degree']),
        plain = j['plain'] as String? ?? '';
  final int course;
  final int fret;
  final double cents;
  final int degree;

  /// `chromaticName` without the octave.
  final String plain;
}

class ScalePosition {
  ScalePosition(Map<String, dynamic> j)
      : number = _i(j['number']),
        notes = [for (final n in _maps(j['notes'])) FretNote(n)],
        fingers = [for (final f in (j['fingers'] as List? ?? const [])) _i(f)],
        lo = _i(j['lo']),
        hi = _i(j['hi']),
        isTruncated = j['isTruncated'] == true;
  final int number;
  final List<FretNote> notes;
  final List<int> fingers;
  final int lo;
  final int hi;
  final bool isTruncated;
}

class ScaleDegreeInfo {
  ScaleDegreeInfo(Map<String, dynamic> j)
      : label = j['label'] as String? ?? '',
        number = _i(j['number']),
        semitones = _i(j['semitones']),
        role = DegreeRole.parse(j['role']);
  final String label;
  final int number;
  final int semitones;
  final DegreeRole role;
}

class ScaleInfo {
  ScaleInfo(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        name = j['name'] as String? ?? '',
        category = j['category'] as String? ?? '',
        isUser = j['isUser'] == true,
        degrees = [for (final d in _maps(j['degrees'])) ScaleDegreeInfo(d)],
        semitones = [for (final s in (j['semitones'] as List? ?? const [])) _i(s)];
  final String id;
  final String name;
  final String category;
  final bool isUser;
  final List<ScaleDegreeInfo> degrees;
  final List<int> semitones;
}

/// One playable cell of the neck from the core.
class CoreCell {
  CoreCell(Map<String, dynamic> j)
      : course = _i(j['course']),
        fret = _i(j['fret']),
        cents = _d(j['cents']),
        degree = (j['degree'] as num?)?.toInt(),
        name = j['name'] as String? ?? '',
        plain = j['plain'] as String? ?? '';
  final int course;
  final int fret;
  final double cents;
  final int? degree;
  final String name;
  final String plain;
  String get key => '$course:$fret';
}

/// A chord of the key (FB-17).
class KeyChord {
  KeyChord(Map<String, dynamic> j)
      : name = j['name'] as String? ?? '',
        spoken = j['spoken'] as String? ?? '',
        roman = j['roman'] as String? ?? '',
        root = _map(j['root']),
        pitchClasses = [for (final p in (j['pitchClasses'] as List? ?? const [])) _i(p)],
        chordId = j['chordId'] as String?;
  final String name;
  final String spoken;
  final String roman;
  final Map<String, dynamic> root;
  final List<int> pitchClasses;
  final String? chordId;
}

class NamedNote {
  NamedNote(Map<String, dynamic> j)
      : name = _map(j['name']),
        text = j['text'] as String? ?? '';
  final Map<String, dynamic> name;
  final String text;
}

/// `fretboard.scale`.
class ScaleData {
  ScaleData(Map<String, dynamic> j)
      : scale = ScaleInfo(_map(j['scale'])),
        tonic = _map(j['tonic']),
        tonicText = j['tonicText'] as String? ?? '',
        title = j['title'] as String? ?? '',
        spelledText = (j['spelledText'] as List? ?? const []).cast<String>(),
        spelledShort = (j['spelledShort'] as List? ?? const []).cast<String>(),
        flats = j['flats'] == true,
        positions = [for (final p in _maps(j['positions'])) ScalePosition(p)],
        cells = [for (final c in _maps(j['cells'])) CoreCell(c)],
        triads = j['triads'] == null ? null : [for (final c in _maps(j['triads'])) KeyChord(c)],
        sevenths = j['sevenths'] == null ? null : [for (final c in _maps(j['sevenths'])) KeyChord(c)],
        triadIds = (j['triadIds'] as List?)?.cast<String?>(),
        tonics = [for (final t in _maps(j['tonics'])) NamedNote(t)],
        fan = NeckFan.fromJson(j['fan']);
  final ScaleInfo scale;
  final Map<String, dynamic> tonic;
  final String tonicText;
  final String title;
  final List<String> spelledText;
  final List<String> spelledShort;
  final bool flats;
  final List<ScalePosition> positions;
  final List<CoreCell> cells;
  final List<KeyChord>? triads;
  final List<KeyChord>? sevenths;
  final List<String?>? triadIds;
  final List<NamedNote> tonics;
  final NeckFan? fan;
}

class ChordTone {
  ChordTone(Map<String, dynamic> j)
      : pc = _i(j['pc']),
        text = j['text'] as String? ?? '',
        name = _map(j['name']);
  final int pc;
  final String text;
  final Map<String, dynamic> name;
}

class ChordDegree {
  ChordDegree(Map<String, dynamic> j)
      : label = j['label'] as String? ?? '',
        number = _i(j['number']),
        semitones = _i(j['semitones']),
        json = _map(j['labelJSON']);
  final String label;
  final int number;
  final int semitones;
  final Map<String, dynamic> json;
}

/// `ChordDTO`: a chord type on a root, spelled.
class ChordData {
  ChordData(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        symbol = j['symbol'] as String? ?? '',
        name = j['name'] as String? ?? '',
        rootText = j['rootText'] as String? ?? '',
        degrees = [for (final d in _maps(j['degrees'])) ChordDegree(d)],
        tones = [for (final t in _maps(j['tones'])) ChordTone(t)];
  final String id;
  final String symbol;
  final String name;
  final String rootText;
  final List<ChordDegree> degrees;
  final List<ChordTone> tones;
}

class VoicingNote {
  VoicingNote(Map<String, dynamic> j)
      : course = _i(j['course']),
        fret = _i(j['fret']),
        cents = _d(j['cents']),
        pc = _i(j['pc']),
        chroma = j['chroma'] as String? ?? '',
        plain = j['plain'] as String? ?? '';
  final int course;
  final int fret;
  final double cents;
  final int pc;
  final String chroma;
  final String plain;
}

/// One playable shape: a fret or null (muted) per course, from the bass side.
class ChordVoicing {
  ChordVoicing(Map<String, dynamic> j)
      : frets = [for (final f in (j['frets'] as List? ?? const [])) (f as num?)?.toInt()],
        notes = [for (final n in _maps(j['notes'])) VoicingNote(n)],
        fingers = _i(j['fingers']),
        barreFret = (j['barreFret'] as num?)?.toInt(),
        span = _i(j['span']),
        lowestFret = _i(j['lowestFret']),
        usesOpenStrings = j['usesOpenStrings'] == true,
        isStretch = j['isStretch'] == true,
        cost = _d(j['cost']),
        fingerNumbers = [for (final f in (j['fingerNumbers'] as List? ?? const [])) _i(f)];
  final List<int?> frets;
  final List<VoicingNote> notes;
  final int fingers;
  final int? barreFret;
  final int span;
  final int lowestFret;
  final bool usesOpenStrings;
  final bool isStretch;
  final double cost;
  final List<int> fingerNumbers;

  VoicingNote get bass => notes.first;
  String get id => frets.map((f) => f ?? -1).join(',');

  @override
  bool operator ==(Object other) => other is ChordVoicing && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ChordMatch {
  ChordMatch(Map<String, dynamic> j)
      : name = j['name'] as String? ?? '',
        root = _map(j['root']),
        chordId = j['chordId'] as String? ?? 'maj',
        bass = (j['bass'] as num?)?.toInt(),
        tones = j['tones'] as String? ?? '',
        chordOnly = j['chordOnly'] as String? ?? '',
        bassName = j['bassName'] as String?,
        toneList = [for (final t in _maps(j['toneList'])) (name: t['name'] as String? ?? '', pc: _i(t['pc']), missing: t['missing'] == true)];
  final String name;
  final Map<String, dynamic> root;
  final String chordId;
  final int? bass;
  final String tones;

  /// Sheet «Отмечено 4 ноты»: the chord name without the bass, the bass, the tones with the missing ones.
  final String chordOnly;
  final String? bassName;
  final List<({String name, int pc, bool missing})> toneList;
}

class ScaleMatch {
  ScaleMatch(Map<String, dynamic> j)
      : tonic = _map(j['tonic']),
        scaleId = j['scaleId'] as String? ?? 'major',
        title = j['title'] as String? ?? '';
  final Map<String, dynamic> tonic;
  final String scaleId;
  final String title;
}

/// `fretboard.search`.
class SearchData {
  SearchData(Map<String, dynamic> j)
      : pitches = [for (final p in _maps(j['pitches'])) (cents: _d(p['cents']), plain: p['plain'] as String? ?? '')],
        distinct = _i(j['distinct']),
        chords = [for (final c in _maps(j['chords'])) ChordMatch(c)],
        scales = [for (final s in _maps(j['scales'])) ScaleMatch(s)],
        nearest = j['nearest'] is Map ? (match: ChordMatch(_map(_map(j['nearest'])['match'])), matched: _i(_map(j['nearest'])['matched'])) : null;
  SearchData.empty()
      : pitches = const [],
        distinct = 0,
        chords = const [],
        scales = const [],
        nearest = null;
  final List<({double cents, String plain})> pitches;
  final int distinct;
  final List<ChordMatch> chords;
  final List<ScaleMatch> scales;
  final ({ChordMatch match, int matched})? nearest;
}

/// `fretboard.noteInfo`.
class NoteInfo {
  NoteInfo(Map<String, dynamic> j)
      : cents = _d(j['cents']),
        pc = _i(j['pc']),
        chroma = j['chroma'] as String? ?? '',
        plain = j['plain'] as String? ?? '',
        degree = (j['degree'] as num?)?.toInt(),
        degreeLabel = j['degreeLabel'] as String?,
        short = j['short'] as String? ?? '',
        majorRoot = _map(j['majorRoot']),
        majorRootText = j['majorRootText'] as String? ?? '',
        modeId = j['modeId'] as String?,
        modeName = j['modeName'] as String?,
        triadId = j['triadId'] as String?;
  final double cents;
  final int pc;
  final String chroma;
  final String plain;
  final int? degree;
  final String? degreeLabel;
  final String short;
  final Map<String, dynamic> majorRoot;
  final String majorRootText;
  final String? modeId;
  final String? modeName;
  final String? triadId;
}

// MARK: Enums

/// FB-26: «Гамма · Аккорд · Поиск · Прогрессия».
enum FretMode { scale, chord, search, progression }

enum PathKind { threePerString, fourDiagonal, oneString }

/// Playback pattern (FB-8).
enum PlaybackChoice {
  up('Подряд'),
  thirds('Терции'),
  seq3('По 3'),
  seq4('По 4');

  const PlaybackChoice(this.title);
  final String title;
}

enum PlaybackDirection { up, down, upDown }

@immutable
class NeckSpot {
  const NeckSpot(this.course, this.fret);
  final int course;
  final int fret;
  String get key => '$course:$fret';

  @override
  bool operator ==(Object other) => other is NeckSpot && other.course == course && other.fret == fret;

  @override
  int get hashCode => Object.hash(course, fret);
}

/// «Гамма от ноты» while the sheet is open: this scale from this note stands on the neck (canvas «превью»).
class ScaleNotePreview {
  ScaleNotePreview({required this.position, required this.scale, required this.spelledText, required this.spot});
  final ScalePosition position;
  final ScaleInfo scale;
  final List<String> spelledText;
  final NeckSpot spot;
}

/// Russian plural: 1 нота, 2 ноты, 5 нот.
String ruPlural(int n, String one, String few, String many) {
  final a = n.abs() % 100, b = a % 10;
  if (a >= 11 && a <= 14) return many;
  if (b == 1) return one;
  return b >= 2 && b <= 4 ? few : many;
}

/// Type chips: lone symbols («°», «+», «ø7») were too small to read.
String chordChipName(String id, String symbol) => switch (id) {
      'maj' => 'maj',
      'dim' => 'dim',
      'dim7' => 'dim7',
      'aug' => 'aug',
      _ => Typo.compactChordName(symbol),
    };

// MARK: Controller

class FretboardController extends ChangeNotifier {
  late AppModel _app;
  AppModel get app => _app;
  set app(AppModel value) {
    _app = value;
    progression.app = value;
    final s = value.store;
    playback = PlaybackChoice.values.where((p) => p.title == s.getString('fb.pattern')).firstOrNull ?? PlaybackChoice.up;
    direction = PlaybackDirection.values.where((d) => d.name == s.getString('fb.direction')).firstOrNull ?? PlaybackDirection.up;
    _loop = s.getString('fb.loop') == 'true';
    _showOutOfScale = s.getString('fb.outOfScale') == 'true';
    _fretsFromCapo = value.args.has('-fretsFromCapoOff') ? false : s.getString('fb.fretsFromCapo') != 'false';
  }

  /// «Прогрессия» (FB-11, FB-22, FB-24).
  final ProgressionController progression = ProgressionController();

  dynamic _core(String method, Map<String, dynamic> params) {
    try {
      return app.core?.call(method, params);
    } catch (e) {
      debugPrint('$method: $e');
      return null;
    }
  }

  bool _pendingNotify = false;

  /// Notifies the screen; during a build (a sheet starting its preview in `initState`) after the frame.
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

  // MARK: Scale data

  ScaleData? _data;
  String _dataKey = '';
  ScaleData? get data {
    _ensureFresh();
    return _data;
  }

  List<ScalePosition> get positions => data?.positions ?? const [];
  List<String> get spelled => data?.spelledText ?? const [];
  List<KeyChord> get keyChords => (showSevenths ? data?.sevenths : data?.triads) ?? const [];
  ScaleInfo? get scale => data?.scale;

  /// Cents of every playable cell («course:fret»).
  Map<String, CoreCell> _cellIndex = {};
  double? cellCents(int course, int fret) => _cellIndex['$course:$fret']?.cents;
  CoreCell? coreCell(int course, int fret) => _cellIndex['$course:$fret'];

  String _scaleKey() {
    final s = settings;
    return jsonEncode([
      app.settings.notation, s.scaleId, s.tonic, s.layout, s.allowOpenStrings, s.eightNotePattern,
      app.settings.customScales, app.instrument['capo'], app.instrument['fretCount'], app.tuning['openCents'],
      app.instrument['multiscale'], app.instrument['courses'],
    ]);
  }

  /// The notation or the user's scales changed without a recompute (iOS computes them live).
  void _ensureFresh() {
    if (_inRecompute) return;
    if (_scaleKey() != _dataKey) recompute();
  }

  // MARK: Drone (FB-13, SND-5)

  /// The tonic sounds as a steady organ-like tone until turned off; its level is the reference-tone slider.
  bool isDroning = false;

  /// The tonic between A2 and G♯3 (cents from A4): low enough to sit under the scale, high enough for the speaker.
  double get droneCents {
    final pc = notePitchClass(settings.tonic);
    final midi = 45 + (pc - 9 + 12) % 12; // A2 = 45
    return (midi - 69) * 100.0;
  }

  void toggleDrone() => isDroning ? stopDrone() : startDrone();

  void startDrone() {
    app.audio.ensurePlayback();
    app.audio.call('audio.drone', {'cents': droneCents});
    isDroning = true;
    changed();
  }

  /// 6.1 п. 5: the tuner must not hear the drone through the speaker.
  void stopDrone() {
    if (!isDroning) return;
    app.audio.call('audio.drone', {});
    isDroning = false;
    changed();
  }

  // MARK: Modes (FB-26)

  /// «Гриф | Таб» (canvas 2026-11-25): the tablature instead of the neck.
  bool _tabView = false;
  bool get tabView => _tabView;
  set tabView(bool value) {
    _tabView = value;
    changed();
  }

  /// Frets in view on the scrolling neck (canvas «Лады 1–12 из 24»): «Сыграть» plays the scale there.
  (int, int) playFrets = (1, 12);

  /// Canvas FlowNote1: the tapped note — every note of the neck dim, this one big.
  NeckSpot? _noteSpot;
  NeckSpot? get noteSpot => _noteSpot;
  set noteSpot(NeckSpot? value) {
    _noteSpot = value;
    notifyListeners();
  }

  /// The tab bar steps aside for the tablature and the note panel (root).
  bool get hidesTabBar => (tabView && mode == FretMode.scale) || (_noteSpot != null && mode == FretMode.scale);

  /// Legend of the canvas: «G тоника», «B D аккорд» (the scale's 3rd and 5th roles).
  ({String tonic, String chord}) get legendNames {
    final d = data;
    final sp = spelled;
    if (d == null || sp.isEmpty) return (tonic: '', chord: '');
    final degrees = d.scale.degrees;
    final chord = [
      for (var i = 1; i < sp.length && i < degrees.length; i++)
        if (degrees[i].role == DegreeRole.chordTone) sp[i],
    ];
    return (tonic: sp[0], chord: chord.join(' '));
  }

  /// Canvas FlowNote1: the scale's notes dim (12 pt) and the tapped note marked (`hasRing`, 38 pt ivory).
  List<NeckCell> allNoteCells() {
    final spot = _noteSpot;
    final result = [
      for (final c in _scaleCells())
        if (NeckSpot(c.course, c.fret) != spot) NeckCell(course: c.course, fret: c.fret, cents: c.cents, label: c.label, role: DegreeRole.other),
    ];
    if (spot != null) {
      final cell = coreCell(spot.course, spot.fret);
      if (cell != null) result.add(NeckCell(course: spot.course, fret: spot.fret, cents: cell.cents, label: cell.plain, role: DegreeRole.other, hasRing: true));
    }
    return result;
  }

  FretMode _mode = FretMode.scale;
  FretMode get mode => _mode;
  set mode(FretMode value) {
    final old = _mode;
    _mode = value;
    // FB-26: the modes share the tonic; a chord picked in the strip opens as that chord.
    if (value == FretMode.chord && old == FretMode.scale) _syncChordFromScale();
    if (value == FretMode.chord && voicings.isEmpty) recomputeVoicings();
    if (value == FretMode.progression) {
      if (old == FretMode.scale && progression.anchor == null) progression.syncFromScale(scale, settings.tonic);
      if (progression.voiced.isEmpty) progression.recompute();
    }
    if (old == FretMode.progression && value != FretMode.progression && progression.isPlaying) progression.stop();
    changed();
  }

  void _syncChordFromScale() {
    _chordAnchor = null;
    _chordBass = null;
    final chords = keyChords;
    final picked = selectedChord != null && selectedChord! < chords.length ? chords[selectedChord!] : chords.firstOrNull;
    if (picked != null && picked.chordId != null) {
      _chordRoot = picked.root;
      _setChordId(picked.chordId!);
    } else {
      _chordRoot = settings.tonic;
      _setChordId('maj');
    }
    recomputeVoicings();
  }

  // «Аккорды от ноты» (FB-21): works on the chord state, which is put back when the sheet closes.
  ({Map<String, dynamic> root, String id, int? bass})? _savedChord;

  /// The voicing picked in the sheet: stands on the neck, the scale dimmed behind it.
  ChordVoicing? _chordPreview;
  ChordVoicing? get chordPreview => _chordPreview;
  set chordPreview(ChordVoicing? v) {
    _chordPreview = v;
    changed();
  }

  void beginChordsFromNote(NeckSpot spot, Map<String, dynamic> root, {String? triadId}) {
    _savedChord ??= (root: _chordRoot, id: _chordId, bass: _chordBass);
    _chordBass = null;
    _chordAnchor = spot;
    _chordRoot = root;
    // The key's chord on this degree; major for a note outside the scale.
    _setChordId(triadId ?? 'maj');
    recomputeVoicings();
  }

  void endChordsFromNote() {
    _chordPreview = null;
    _chordAnchor = null;
    final saved = _savedChord;
    if (saved == null) {
      recomputeVoicings();
      return;
    }
    _savedChord = null;
    _chordRoot = saved.root;
    _setChordId(saved.id);
    _chordBass = saved.bass;
    recomputeVoicings();
  }

  Map<String, dynamic> _chordRoot = {'letter': 5, 'accidental': 0};
  Map<String, dynamic> get chordRoot => _chordRoot;
  set chordRoot(Map<String, dynamic> v) {
    _chordRoot = v;
    recomputeVoicings();
  }

  String _chordId = 'm7';
  String get chordId => _chordId;
  set chordId(String v) {
    _setChordId(v);
    recomputeVoicings();
  }

  void _setChordId(String v) {
    _chordId = v;
    _chordOmitted = [];
  }

  /// TH-3b: degrees dropped by «Опустить ступень N» (reset with the chord type); core `DegreeLabel` JSON.
  List<Map<String, dynamic>> _chordOmitted = [];
  List<Map<String, dynamic>> get chordOmitted => _chordOmitted;
  void omit(Map<String, dynamic> label) {
    if (_chordOmitted.any((l) => l['number'] == label['number'] && l['accidental'] == label['accidental'])) return;
    _chordOmitted = [..._chordOmitted, label];
    recomputeVoicings();
  }

  /// When nothing fits: the degree whose omission makes the chord playable.
  Map<String, dynamic>? omissionHint;

  /// Inversion: the pitch class in the bass (null = root).
  int? _chordBass;
  int? get chordBass => _chordBass;
  set chordBass(int? v) {
    _chordBass = v;
    recomputeVoicings();
  }

  /// «Аккорды от ноты»: voicings must start from this cell.
  NeckSpot? _chordAnchor;
  NeckSpot? get chordAnchor => _chordAnchor;
  set chordAnchor(NeckSpot? v) {
    _chordAnchor = v;
    recomputeVoicings();
  }

  List<ChordVoicing> voicings = [];
  ChordData? chordData;
  int _voicingIndex = 0;
  int get voicingIndex => _voicingIndex;
  set voicingIndex(int v) {
    _voicingIndex = v;
    changed();
  }

  LabelMode _chordLabels = LabelMode.notes;
  LabelMode get chordLabels => _chordLabels;
  set chordLabels(LabelMode v) {
    _chordLabels = v;
    changed();
  }

  /// «Поиск»: marked cells.
  List<NeckSpot> _marked = [];
  List<NeckSpot> get marked => _marked;
  set marked(List<NeckSpot> v) {
    _marked = v;
    _recomputeSearch();
    changed();
  }

  /// Note menu target (long press).
  NeckSpot? _menuSpot;
  NeckSpot? get menuSpot => _menuSpot;
  set menuSpot(NeckSpot? v) {
    _menuSpot = v;
    changed();
  }

  /// «Гамма от ноты»: the position that contains this cell with the tonic on it («позиция от ноты»).
  NeckSpot? positionAnchor;

  /// FB-25: the position built from that cell (the note is its lowest), until an arrow or another view is chosen.
  ScalePosition? anchoredPosition;

  ScaleNotePreview? fromNotePreview;
  bool get hasPreview => chordPreview != null || fromNotePreview != null;

  Map<String, dynamic> _layoutParams() => {
        'layout': settings.layout,
        'allowOpenStrings': settings.allowOpenStrings,
        'eightNotePattern': settings.eightNotePattern,
      };

  ({Map<String, dynamic> tonic, ScaleInfo scale, List<String> spelled, ScalePosition? position})? _positionFrom(NeckSpot spot, String scaleId, {Map<String, dynamic>? tonic}) {
    final r = _core('fretboard.positionFrom', {
      'scaleId': scaleId,
      'tonic': ?tonic,
      ..._layoutParams(),
      'course': spot.course,
      'fret': spot.fret,
    });
    if (r is! Map) return null;
    final m = _map(r);
    return (
      tonic: _map(m['tonic']),
      scale: ScaleInfo(_map(m['scale'])),
      spelled: (m['spelledText'] as List? ?? const []).cast<String>(),
      position: m['position'] is Map ? ScalePosition(_map(m['position'])) : null,
    );
  }

  void previewScale(NeckSpot spot, String scaleId) {
    final r = _positionFrom(spot, scaleId);
    fromNotePreview = r?.position == null
        ? null
        : ScaleNotePreview(position: r!.position!, scale: r.scale, spelledText: r.spelled, spot: spot);
    changed();
  }

  void endScalePreview() {
    fromNotePreview = null;
    changed();
  }

  List<NeckCell> _previewCells(ScaleNotePreview p) {
    final result = <NeckCell>[];
    for (var i = 0; i < p.position.notes.length; i++) {
      final n = p.position.notes[i];
      final finger = i < p.position.fingers.length ? p.position.fingers[i] : 0;
      final degree = n.degree < p.scale.degrees.length ? n.degree : 0;
      final d = p.scale.degrees.isEmpty ? null : p.scale.degrees[degree];
      final label = switch (settings.labels) {
        LabelMode.notes => degree < p.spelledText.length ? p.spelledText[degree] : '',
        LabelMode.degrees => d?.label ?? '',
        LabelMode.intervals => intervalName(d?.semitones ?? 0),
        LabelMode.fingers => '$finger',
        LabelMode.none => '',
      };
      result.add(NeckCell(
        course: n.course,
        fret: n.fret,
        cents: n.cents,
        label: label,
        role: d?.role ?? DegreeRole.other,
        hasRing: NeckSpot(n.course, n.fret) == p.spot,
      ));
    }
    return result;
  }

  // MARK: Path (FB-20)

  /// Path mode inside «Гамма»: null = off.
  PathKind? _pathKind;
  PathKind? get pathKind => _pathKind;
  set pathKind(PathKind? v) {
    _pathKind = v;
    recomputePath();
    changed();
  }

  NeckSpot? _pathStart;
  NeckSpot? get pathStart => _pathStart;
  set pathStart(NeckSpot? v) {
    _pathStart = v;
    recomputePath();
    changed();
  }

  List<FretNote> pathNotes = [];
  String _pathFirstName = '';

  /// The first path note's name with its octave («E2») — the tab's «от E2».
  String get pathFirstName => _pathFirstName;

  /// Index of the sounding path note while playing.
  int? get pathIndex {
    final p = playingNote;
    if (p == null) return null;
    final i = pathNotes.indexWhere((n) => n.course == p.course && n.fret == p.fret);
    return i < 0 ? null : i;
  }

  void recomputePath() {
    clearPause();
    final kind = pathKind;
    if (kind == null) {
      pathNotes = [];
      return;
    }
    final r = _core('fretboard.path', {
      'kind': kind.name,
      'scaleId': settings.scaleId,
      'tonic': settings.tonic,
      if (pathStart != null) 'start': {'course': pathStart!.course, 'fret': pathStart!.fret},
    });
    final m = _map(r);
    pathNotes = [for (final n in _maps(m['notes'])) FretNote(n)];
    _pathFirstName = m['firstName'] as String? ?? '';
  }

  /// Label inside a path note: what the neck shows (note, degree, interval); numbers are the badge.
  String pathLabel(FretNote n) {
    final degrees = scale?.degrees ?? const [];
    final d = n.degree < degrees.length ? degrees[n.degree] : null;
    switch (settings.labels) {
      case LabelMode.degrees:
        return d?.label ?? '';
      case LabelMode.intervals:
        return d == null ? '' : intervalName(d.semitones);
      default:
        return n.degree < spelled.length ? spelled[n.degree] : n.plain;
    }
  }

  /// «4 ноты наискосок · 24 ноты · от G2, 6-я стр.» — what the path is, before it plays.
  String get pathSummary {
    final kind = pathKind;
    if (pathNotes.isEmpty || kind == null) return '';
    final first = pathNotes.first;
    final kindText = switch (kind) {
      PathKind.threePerString => '3 на струну',
      PathKind.fourDiagonal => '4 наискосок',
      PathKind.oneString => 'по одной струне',
    };
    final n = pathNotes.length;
    final notes = n % 10 == 1 && n % 100 != 11 ? 'нота' : ((n % 10 >= 2 && n % 10 <= 4) && !(n % 100 >= 12 && n % 100 <= 14) ? 'ноты' : 'нот');
    return '$kindText · $n $notes · от $_pathFirstName, ${app.courseCount - first.course}-я стр.';
  }

  void startPath(NeckSpot? spot) {
    mode = FretMode.scale;
    _pathStart = spot;
    // «Путь отсюда» leads across the neck from the pressed note; the visible «Путь» keeps position by position.
    _pathKind ??= spot != null ? PathKind.fourDiagonal : PathKind.threePerString;
    recomputePath();
    changed();
  }

  // MARK: Chord

  void recomputeVoicings() {
    final a = chordAnchor;
    final r = _core('fretboard.voicings', {
      'chordId': chordId,
      'root': chordRoot,
      if (chordOmitted.isNotEmpty) 'omitted': chordOmitted,
      'bass': ?chordBass,
      if (a != null) 'anchor': {'course': a.course, 'fret': a.fret},
      'limit': 30,
    });
    final m = _map(r);
    chordData = m['chord'] is Map ? ChordData(_map(m['chord'])) : null;
    voicings = [for (final v in _maps(m['voicings'])) ChordVoicing(v)];
    omissionHint = m['omissionHint'] is Map ? _map(m['omissionHint']) : null;
    _voicingIndex = 0;
    changed();
  }

  ChordVoicing? get currentVoicing => voicingIndex < voicings.length ? voicings[voicingIndex] : null;

  /// «Am7», «C13♯11 без 11», «Am7/C».
  String chordName({int? bass}) {
    final c = chordData;
    if (c == null) return '';
    var name = Typo.compactChordName(c.name);
    if (chordOmitted.isNotEmpty) {
      final numbers = chordOmitted.map((l) => '${l['number']}').toList()..sort();
      name += ' без ${numbers.join(', ')}';
    }
    if (bass != null && bass != notePitchClass(chordRoot)) {
      final tone = c.tones.where((t) => t.pc == bass).firstOrNull;
      if (tone != null) name += '/${tone.text}';
    }
    return name;
  }

  /// «открытый», «вниз по грифу», «от 5-го лада» (canvas list rows).
  String voicingTitle(ChordVoicing v) {
    if (v.usesOpenStrings && v.lowestFret <= 4) return 'открытый';
    final anchor = chordAnchor;
    if (anchor != null && v.notes.any((n) => n.fret < anchor.fret && n.fret > 0)) return 'вниз по грифу';
    return 'от ${v.lowestFret}-го лада';
  }

  /// «тоника на 6-й · 5 стр. · 3 пальца», «бас B на 7-й · 5 стр. · баррэ».
  String voicingSubtitle(ChordVoicing v) {
    final n = app.courseCount;
    final parts = <String>[];
    final bassString = n - v.bass.course;
    if (v.bass.pc == notePitchClass(chordRoot)) {
      parts.add('тоника на $bassString-й');
    } else {
      parts.add('бас ${v.bass.plain} на $bassString-й');
    }
    parts.add('${v.notes.length} стр.');
    if (v.barreFret != null) {
      parts.add('баррэ');
    } else {
      parts.add('${v.fingers} ${ruPlural(v.fingers, 'палец', 'пальца', 'пальцев')}');
    }
    return parts.join(' · ');
  }

  void stepVoicing(int delta) {
    if (voicings.isEmpty) return;
    voicingIndex = (voicingIndex + delta + voicings.length) % voicings.length;
  }

  /// Strums the current voicing (FB-23): low to high, 12 ms per string, 2 s.
  void playVoicing([ChordVoicing? voicing, bool arpeggio = false]) {
    final v = voicing ?? currentVoicing;
    if (v == null) return;
    final step = arpeggio ? 60 / bpm / 2 : 0.012;
    _pauseTuner(2.15 + v.notes.length * step);
    app.audio.ensurePlayback();
    app.audio.call('audio.stopNotes');
    final r = app.audio.call('audio.playNotes', {
      'notes': [
        for (var i = 0; i < v.notes.length; i++) {'cents': v.notes[i].cents, 'offset': i * step, 'string': v.notes[i].course},
      ],
      'start': 'now',
      'delay': 0.02,
      'velocity': 0.75,
      if (!arpeggio) 'noteDuration': 2,
    });
    if (r == null && app.audio.available && app.core != null) app.show('Звук недоступен');
    _strum(v.notes.map((n) => n.course).toList());
  }

  // MARK: Search

  SearchData _search = SearchData.empty();
  SearchData get search => _search;

  void toggleMark(int course, int fret) {
    final spot = NeckSpot(course, fret);
    final list = List.of(marked);
    if (list.contains(spot)) {
      list.remove(spot);
    } else {
      // One note per string, as on a real neck.
      list.removeWhere((s) => s.course == course);
      list.add(spot);
    }
    marked = list;
  }

  void _recomputeSearch() {
    if (marked.isEmpty) {
      _search = SearchData.empty();
      return;
    }
    final r = _core('fretboard.search', {
      'marked': [for (final s in marked) {'course': s.course, 'fret': s.fret}],
      'preferFlats': data?.flats ?? false,
    });
    _search = r is Map ? SearchData(_map(r)) : SearchData.empty();
  }

  /// «Открыть в «Аккорде»».
  void openInChordMode(ChordMatch match) {
    _chordAnchor = null;
    _chordBass = match.bass;
    _chordRoot = match.root;
    _setChordId(match.chordId);
    recomputeVoicings();
    mode = FretMode.chord;
  }

  /// «Гамма от этой ноты» (FB-25): tonic = the note, position = the one that holds this cell.
  void buildScale(NeckSpot spot, String scaleId) {
    final from = _positionFrom(spot, scaleId);
    if (from == null) return;
    updateSettings((s) {
      s.scaleId = scaleId;
      s.tonic = from.tonic;
      s.hiddenCells = [];
      s.addedCells = [];
      s.neckView = NeckDisplay.position;
    });
    bool holds(ScalePosition p) => p.notes.any((n) => n.course == spot.course && n.fret == spot.fret);
    final number = positions.where((p) => holds(p) && p.notes.firstOrNull?.course == spot.course).firstOrNull?.number ??
        positions.where(holds).firstOrNull?.number;
    if (number != null) selectPosition(number);
    positionAnchor = spot;
    anchoredPosition = _positionFrom(spot, settings.scaleId, tonic: settings.tonic)?.position;
    mode = FretMode.scale;
  }

  bool _showSevenths = false;
  bool get showSevenths => _showSevenths;
  set showSevenths(bool v) {
    _showSevenths = v;
    selectedChord = null;
    changed();
  }

  int? selectedChord;

  /// Playback pattern, direction and loop (FB-8; user: «вверх-вниз, по кругу»). Kept in the settings store.
  PlaybackChoice _playback = PlaybackChoice.up;
  PlaybackChoice get playback => _playback;
  set playback(PlaybackChoice v) {
    _playback = v;
    app.store.setString('fb.pattern', v.title);
    changed();
  }

  PlaybackDirection _direction = PlaybackDirection.up;
  PlaybackDirection get direction => _direction;
  set direction(PlaybackDirection v) {
    _direction = v;
    app.store.setString('fb.direction', v.name);
    changed();
  }

  /// «Вид и подписи» → «Ноты вне гаммы»: the other notes of the neck, dimmed (canvas 2026-11-25).
  bool _showOutOfScale = false;
  bool get showOutOfScale => _showOutOfScale;
  set showOutOfScale(bool v) {
    _showOutOfScale = v;
    app.store.setString('fb.outOfScale', '$v');
    changed();
  }

  /// «Вид и подписи» → «Лады от капо»: fret numbers count from the capo.
  bool _fretsFromCapo = true;
  bool get fretsFromCapo => _fretsFromCapo;
  set fretsFromCapo(bool v) {
    _fretsFromCapo = v;
    app.store.setString('fb.fretsFromCapo', '$v');
    changed();
  }

  bool _loop = false;
  bool get loop => _loop;
  set loop(bool v) {
    _loop = v;
    app.store.setString('fb.loop', '$v');
    changed();
  }

  bool isPlaying = false;
  NeckSpot? playingNote;
  int _playGeneration = 0;

  /// «Пауза» keeps the place: the next start continues from `_resumeIndex` in the play order while the notes and
  /// the order are the same (`_resumeKey`).
  int? _resumeIndex;
  String _resumeKey = '';

  /// Position in the play order of the note being heard.
  int? _orderPosition;
  int _resumeOrderCount = 0;

  /// Paused in the middle: «Сыграть» continues.
  bool get canResume => !isPlaying && _resumeIndex != null;

  String _playKey(List<FretNote> notes, List<int> order) =>
      '${notes.map((n) => '${n.course},${n.fret}').join(';')}|${order.join(',')}';

  /// Forget the paused place (the scale, position or path changed).
  void clearPause() {
    if (isPlaying) return;
    _resumeIndex = null;
    playingNote = null;
  }

  FretboardSettings get settings => app.settings.fretboard;

  /// Changes the fretboard settings; the neck is rebuilt when the scale or the layout changed (`settings.set`).
  void updateSettings(void Function(FretboardSettings s) mutate) {
    final old = FretboardSettings.fromJson(settings.toJson());
    app.updateSettings((s) => mutate(s.fretboard));
    final now = settings;
    final tonicChanged = jsonEncode(now.tonic) != jsonEncode(old.tonic);
    if (tonicChanged && isDroning) startDrone(); // FB-13: the drone follows the tonic
    if (now.scaleId != old.scaleId ||
        tonicChanged ||
        now.layout != old.layout ||
        now.allowOpenStrings != old.allowOpenStrings ||
        now.eightNotePattern != old.eightNotePattern) {
      recompute();
    }
    changed();
  }

  String get scaleTitle => data?.title ?? '';

  ScalePosition? get currentPosition {
    if (settings.neckView != NeckDisplay.position) return null;
    if (positionAnchor != null && anchoredPosition != null) return anchoredPosition;
    final list = positions;
    return list.where((p) => p.number == settings.positionNumber).firstOrNull ?? list.firstOrNull;
  }

  // MARK: Recompute

  bool _inRecompute = false;

  /// Recomputes the neck after a scale, tuning, capo or fret-count change.
  void recompute({bool notifyPosition = false}) {
    if (_inRecompute) return;
    _inRecompute = true;
    try {
      clearPause();
      final previous = _data == null ? null : currentPosition;
      final r = _core('fretboard.scale', {
        'scaleId': settings.scaleId,
        'tonic': settings.tonic,
        ..._layoutParams(),
      });
      _dataKey = _scaleKey();
      if (r is Map) {
        _data = ScaleData(_map(r));
        _cellIndex = {for (final c in _data!.cells) c.key: c};
      }
      final list = positions;
      // 6.1 п. 18: keep the position whose window is closest to the previous one.
      if (previous != null && list.isNotEmpty && notifyPosition) {
        var best = list.first;
        for (final p in list.skip(1)) {
          final da = (p.lo - previous.lo).abs(), db = (best.lo - previous.lo).abs();
          if (da < db || (da == db && p.lo < best.lo)) best = p;
        }
        if (best.number != settings.positionNumber) showToast('Позиция пересчитана под новый строй');
        _silently((s) => s.positionNumber = best.number);
      } else if (settings.positionNumber > list.length) {
        _silently((s) => s.positionNumber = 1);
      }
      if (list.isEmpty && settings.neckView == NeckDisplay.position) _silently((s) => s.neckView = NeckDisplay.wholeNeck);
      selectedChord = null;
      if (pathKind != null) recomputePath();
      _refreshAnchoredPosition();
      if (marked.isNotEmpty) _recomputeSearch();
      if (mode == FretMode.chord || voicings.isNotEmpty) recomputeVoicings();
    } finally {
      _inRecompute = false;
    }
    progression.instrumentMayHaveChanged();
    changed();
  }

  void _silently(void Function(FretboardSettings s) mutate) {
    if (inBuildPhase) {
      mutate(app.settings.fretboard);
      app.settings.save(app.store);
      changed();
    } else {
      app.updateSettings((s) => mutate(s.fretboard));
    }
  }

  // MARK: Cells

  List<NeckCell> cells() {
    final preview = fromNotePreview;
    if (preview != null) return _previewCells(preview);
    final chordPreview = this.chordPreview;
    if (chordPreview != null) {
      // The picked voicing in full, the scale faint behind it (canvas «Аккорды от ноты — звучит»).
      final shown = _chordCells(chordPreview);
      final taken = shown.map((c) => c.id).toSet();
      final dim = _scaleCells().where((c) => !taken.contains(c.id)).toList();
      for (final c in dim) {
        c.emphasis = NeckEmphasis.faint;
        c.label = '';
      }
      return [...dim, ...shown];
    }
    if (_noteSpot != null && mode == FretMode.scale) return allNoteCells();
    return switch (mode) {
      FretMode.chord => currentVoicing == null ? <NeckCell>[] : _chordCells(currentVoicing!),
      FretMode.search => _searchCells(),
      FretMode.scale => _scaleCells(),
      FretMode.progression => progression.cells(),
    };
  }

  /// Chord mode: the voicing's notes; root ivory, 3rd and 5th blue, the rest dark (canvas «Режим «Аккорд»»).
  List<NeckCell> _chordCells(ChordVoicing v) {
    final c = chordData;
    final rootPC = notePitchClass(chordRoot);
    return [
      for (final n in v.notes)
        () {
          final degree = c?.degrees.where((d) => (rootPC + d.semitones) % 12 == n.pc).firstOrNull;
          final role = n.pc == rootPC
              ? DegreeRole.tonic
              : (degree != null && (degree.number == 3 || degree.number == 5) ? DegreeRole.chordTone : DegreeRole.other);
          final name = c?.tones.where((t) => t.pc == n.pc).firstOrNull?.text ?? n.chroma;
          final finger = n.course < v.fingerNumbers.length ? v.fingerNumbers[n.course] : -1;
          final label = switch (chordLabels) {
            LabelMode.degrees => degree?.label ?? '',
            LabelMode.fingers => '${finger < 0 ? 0 : finger}',
            _ => name,
          };
          return NeckCell(
            course: n.course,
            fret: n.fret,
            cents: n.cents,
            label: label,
            role: role,
            hasRing: chordAnchor == NeckSpot(n.course, n.fret),
          );
        }(),
    ];
  }

  /// Search mode: only the marked notes (purple).
  List<NeckCell> _searchCells() => [
        for (final spot in marked)
          if (coreCell(spot.course, spot.fret) case final cell?)
            NeckCell(course: spot.course, fret: spot.fret, cents: cell.cents, label: cell.plain, role: DegreeRole.other, isMarked: true),
      ];

  List<NeckCell> _scaleCells() {
    final d = data;
    if (d == null) return [];
    final s = settings;
    final hidden = s.hiddenCells.toSet(), added = s.addedCells.toSet();
    final position = currentPosition;
    final positionFingers = <String, int>{};
    if (position != null) {
      for (var i = 0; i < position.notes.length; i++) {
        positionFingers['${position.notes[i].course}:${position.notes[i].fret}'] = i < position.fingers.length ? position.fingers[i] : 0;
      }
    }
    final chords = keyChords;
    final chordPitchClasses = selectedChord != null && selectedChord! < chords.length ? chords[selectedChord!].pitchClasses.toSet() : null;
    final degrees = d.scale.degrees;
    final result = <NeckCell>[];
    for (final cell in d.cells) {
      final key = cell.key;
      if (hidden.contains(key)) continue;
      final degree = cell.degree;
      final isAdded = degree == null && added.contains(key);
      // «Ноты вне гаммы» (sheet «Вид и подписи»): the other notes stay, faint.
      final outside = degree == null && !isAdded && showOutOfScale && mode == FretMode.scale;
      if (degree == null && !isAdded && !outside) continue;
      var emphasis = NeckEmphasis.full;
      switch (s.neckView) {
        case NeckDisplay.wholeNeck:
          break;
        // Position view shows only the notes that the position plays; the whole scale is one tap away.
        // Canvas 2026-11-25: the whole neck scrolls; positions only narrow the notes while training.
        case NeckDisplay.position:
          if (isTraining && positionFingers[key] == null && !isAdded && pathKind == null) continue;
        case NeckDisplay.window:
          if ((cell.fret < s.windowStart || cell.fret > s.windowStart + s.windowLength - 1) && cell.fret != 0) emphasis = NeckEmphasis.faint;
      }
      if (chordPitchClasses != null) {
        emphasis = chordPitchClasses.contains(centsPitchClass(cell.cents)) ? NeckEmphasis.full : NeckEmphasis.faint;
      }
      if (outside) emphasis = NeckEmphasis.faint;
      String label;
      if (degree != null) {
        label = switch (s.labels) {
          LabelMode.notes => cell.name,
          LabelMode.degrees => degree < degrees.length ? degrees[degree].label : '',
          LabelMode.intervals => intervalName(degree < degrees.length ? degrees[degree].semitones : 0),
          LabelMode.fingers => positionFingers[key]?.toString() ?? '',
          LabelMode.none => '',
        };
      } else {
        label = s.labels == LabelMode.none ? '' : cell.name;
      }
      final role = degree != null && degree < degrees.length ? degrees[degree].role : DegreeRole.other;
      final spot = NeckSpot(cell.course, cell.fret);
      result.add(NeckCell(
        course: cell.course,
        fret: cell.fret,
        cents: cell.cents,
        label: label,
        role: role,
        emphasis: emphasis,
        isAdded: isAdded,
        isPlaying: playingNote == spot,
        hasRing: positionAnchor == spot || menuSpot == spot,
        isWrong: wrongSpots.contains(spot),
      ));
    }
    return result;
  }

  static String intervalName(int semitones) =>
      const ['ч1', 'м2', 'б2', 'м3', 'б3', 'ч4', 'тт', 'ч5', 'м6', 'б6', 'м7', 'б7'][(semitones % 12 + 12) % 12];

  // MARK: Interaction

  void _pauseTuner(double seconds) => app.audio.call('audio.pauseAnalysis', {'seconds': seconds});

  /// FB-7: a tap sounds the note.
  void tap(int course, int fret) {
    final cents = cellCents(course, fret);
    if (cents == null) return;
    _pauseTuner(2.15); // FB-23: the microphone ignores the phone's own note
    app.audio.playNote(cents, string: course);
  }

  /// FB-7: a long tap hides a scale note or adds a note that is not in the scale (6.1 п. 13).
  void toggle(int course, int fret) {
    final cell = coreCell(course, fret);
    if (cell == null) return;
    final key = cell.key;
    updateSettings((s) {
      if (cell.degree != null) {
        if (!s.hiddenCells.remove(key)) s.hiddenCells.add(key);
      } else {
        if (!s.addedCells.remove(key)) s.addedCells.add(key);
      }
    });
  }

  NoteInfo? noteInfo(NeckSpot spot) {
    final r = _core('fretboard.noteInfo', {'course': spot.course, 'fret': spot.fret, 'scaleId': settings.scaleId, 'tonic': settings.tonic});
    return r is Map ? NoteInfo(_map(r)) : null;
  }

  /// The note's name as the scale spells it (chromatic outside the scale), for the note menu.
  String noteName(NeckSpot spot) => noteInfo(spot)?.short ?? '';

  bool isHidden(NeckSpot spot) => settings.hiddenCells.contains(spot.key);

  bool get isEdited => settings.hiddenCells.isNotEmpty || settings.addedCells.isNotEmpty;

  void resetEdits() => updateSettings((s) {
        s.hiddenCells = [];
        s.addedCells = [];
      });

  /// The position from a note lives while that note is still the tonic (layout changes rebuild it).
  void _refreshAnchoredPosition() {
    final spot = positionAnchor;
    if (spot == null) return;
    final cell = coreCell(spot.course, spot.fret);
    if (cell == null || centsPitchClass(cell.cents) != notePitchClass(settings.tonic)) {
      positionAnchor = null;
      anchoredPosition = null;
      return;
    }
    final rebuilt = _positionFrom(spot, settings.scaleId, tonic: settings.tonic)?.position;
    if (rebuilt == null) {
      positionAnchor = null;
      anchoredPosition = null;
      return;
    }
    anchoredPosition = rebuilt;
  }

  void selectPosition(int? number) {
    positionAnchor = null;
    anchoredPosition = null;
    updateSettings((s) {
      if (number != null) {
        s.neckView = NeckDisplay.position;
        s.positionNumber = number;
      } else {
        s.neckView = NeckDisplay.wholeNeck;
      }
    });
  }

  void stepPosition(int delta) {
    final list = positions;
    if (list.isEmpty) return;
    final current = settings.neckView == NeckDisplay.position ? settings.positionNumber : 0;
    selectPosition(math.min(list.length, math.max(1, current + delta)));
  }

  void setTonic(int pitchClass) {
    final tonics = data?.tonics ?? const [];
    final name = pitchClass < tonics.length ? tonics[pitchClass].name : null;
    if (name == null) return;
    updateSettings((s) {
      s.tonic = name;
      s.hiddenCells = [];
      s.addedCells = [];
    });
  }

  /// Manual enharmonic switch (5.2.1 rule 6): G♯ ↔ A♭.
  void toggleEnharmonic() {
    final r = _core('fretboard.enharmonic', {'tonic': settings.tonic});
    if (r is! Map) return;
    updateSettings((s) => s.tonic = _map(r));
  }

  /// TH-8 «Сохранить как свою»: the scale's notes with the neck edits (added notes in, hidden notes out),
  /// as semitones above the tonic.
  List<int> get editedSemitones {
    final tonic = notePitchClass(settings.tonic);
    int? pc(String key) {
      final cell = _cellIndex[key];
      return cell == null ? null : ((centsPitchClass(cell.cents) - tonic) % 12 + 12) % 12;
    }

    final set = {...?scale?.semitones.map((s) => (s % 12 + 12) % 12)};
    final added = settings.addedCells.map(pc).whereType<int>().toSet();
    set.removeAll(settings.hiddenCells.map(pc).whereType<int>().toSet().difference(added));
    set.addAll(added);
    set.add(0);
    return set.toList()..sort();
  }

  void setScale(String id) {
    final r = _core('fretboard.preferredTonic', {'pitchClass': notePitchClass(settings.tonic), 'scaleId': id});
    updateSettings((s) {
      s.scaleId = id;
      s.hiddenCells = [];
      s.addedCells = [];
      if (r is Map) s.tonic = _map(_map(r)['name']);
    });
  }

  // MARK: Playback (FB-8, 6.1 п. 14)

  /// The shared tempo (metronome settings).
  double get bpm => _d(app.settings.metronome.meter['bpm']);
  set bpm(double v) => app.updateSettings((s) => s.metronome.meter['bpm'] = v.clamp(20, 400).roundToDouble());

  void togglePlayback() => isPlaying ? stopPlayback() : startPlayback();

  /// What «Сыграть» plays is what is on the screen: the path, the position, the notes of the custom window; from
  /// «Весь гриф» it moves to the first position and says so.
  List<FretNote> _notesToPlay() {
    if (pathKind != null && pathNotes.isNotEmpty) return pathNotes;
    switch (settings.neckView) {
      case NeckDisplay.window:
        final r = visibleFrets;
        return _notesIn(r.$1, r.$2);
      case NeckDisplay.position:
      case NeckDisplay.wholeNeck:
        // The frets in view on the scrolling neck, open strings included at the top.
        return _notesIn(playFrets.$1 <= 1 ? 0 : playFrets.$1, playFrets.$2);
    }
  }

  /// Scale notes inside the frets, low to high, each pitch once (on the lower string).
  List<FretNote> _notesIn(int lo, int hi) {
    final seen = <int>{};
    final list = _scaleCells().where((c) => c.fret >= lo && c.fret <= hi).toList()
      ..sort((a, b) => a.cents == b.cents ? a.course.compareTo(b.course) : a.cents.compareTo(b.cents));
    return [
      for (final c in list)
        if (seen.add(c.cents.round()))
          FretNote({'course': c.course, 'fret': c.fret, 'cents': c.cents, 'degree': coreCell(c.course, c.fret)?.degree ?? 0}),
    ];
  }

  List<int> _order(int count, bool loop) {
    final r = _core('fretboard.order', {'pattern': playback.name, 'direction': direction.name, 'loop': loop, 'count': count});
    return r is List ? [for (final i in r) _i(i)] : List.generate(count, (i) => i);
  }

  // MARK: FB-14 «Тренировать»

  bool isTraining = false;
  Set<NeckSpot> wrongSpots = {};

  void startTraining() {
    if (isPlaying) stopPlayback();
    final notes = _notesToPlay();
    if (notes.isEmpty) return;
    isTraining = true;
    wrongSpots = {};
    // TODO(android): app.playCheck.beginExercise(pitches, onNote:, onWrong:) + enable() when «Проверка игры» is
    // ported (metronome agent); until then the training shows the bar and keeps the click going.
    _startClick();
    changed();
  }

  /// Screenshot hook `-trainingDemo`: the training layout without the microphone.
  void trainingDemo() {
    isTraining = true;
    final notes = _notesToPlay();
    if (notes.length > 2) playingNote = NeckSpot(notes[2].course, notes[2].fret);
    if (notes.length > 4) wrongSpots = {NeckSpot(notes[4].course, notes[4].fret)};
    changed();
  }

  void stopTraining() {
    if (!isTraining) return;
    isTraining = false;
    playingNote = null;
    wrongSpots = {};
    _stopClick(force: true);
    changed();
  }

  // MARK: Metronome click with playback

  /// The click was started by the playback (`metronome.start(byPlayback:)` on iOS).
  bool _clickByPlayback = false;
  bool get _metronomePlaying => app.metronome.isPlaying || _clickByPlayback;

  // TODO(android): go through `app.metronome.start(byPlayback: true)` / `startedByPlayback` once the metronome port
  // has them; until then the click runs straight on the audio host with the shared meter.
  void _startClick() {
    if (_metronomePlaying) return;
    app.audio.ensurePlayback();
    app.audio.call('audio.startMetronome', {'settings': app.settings.metronome.meter});
    _clickByPlayback = true;
  }

  void _stopClick({bool force = false}) {
    if (!_clickByPlayback && !force) return;
    if (_clickByPlayback) app.audio.call('audio.stopMetronome');
    _clickByPlayback = false;
  }

  void startPlayback() {
    final notes = _notesToPlay();
    if (notes.isEmpty) return;
    final looping = loop; // a change applies to the next start
    final order = _order(notes.length, looping);
    if (order.isEmpty) return;
    final key = _playKey(notes, order);
    final startIndex = _resumeKey == key && _resumeIndex != null ? math.min(_resumeIndex!, order.length - 1) : 0;
    _resumeIndex = null;
    final meter = app.settings.metronome.meter;
    final bpm = _d(meter['bpm']);
    final subdivision = _i(meter['subdivision']);
    final step = 60 / bpm / math.max(1, subdivision == 1 ? 2 : subdivision);
    final bar = 60 / bpm * _i(meter['numerator']);

    var countIn = 0.0;
    final metronomeWasPlaying = _metronomePlaying;
    if (!metronomeWasPlaying && settings.clickWithPlayback) {
      _startClick();
      countIn = bar; // one bar of count-in
    }
    List<Map<String, dynamic>> sequence(List<int> indices, double offset) => [
          for (var i = 0; i < indices.length; i++)
            {'cents': notes[indices[i]].cents, 'offset': offset + i * step, 'string': notes[indices[i]].course},
        ];
    final first = order.sublist(startIndex);
    app.audio.ensurePlayback();
    // FB-8: each note on its own string and fret, one subdivision long, no overlap.
    final r = app.audio.call('audio.playNotes', {
      'notes': sequence(first, countIn),
      'start': _metronomePlaying ? 'nextBar' : 'now',
      'delay': 0.1,
      'noteDuration': step,
    });
    final lead = r is Map ? _d(r['lead']) : 0.1;
    final firstSample = r is Map ? _d(r['startSample']) : 0.0;
    final rate = r is Map ? _d(r['sampleRate']) : 48000.0;
    isPlaying = true;
    _resumeKey = key;
    _resumeOrderCount = order.length;
    final generation = ++_playGeneration;
    final clock = Stopwatch()..start();
    final t0 = lead + countIn;
    Future<void> sleepUntil(double seconds) async {
      final wait = seconds - clock.elapsedMicroseconds / 1e6;
      if (wait > 0) await Future<void>.delayed(Duration(microseconds: (wait * 1e6).round()));
    }

    () async {
      var passStart = 0.0;
      var pass = 0;
      do {
        final indices = pass == 0 ? first : order;
        final offset = pass == 0 ? startIndex : 0;
        final passLength = indices.length * step;
        // Loop: the next pass is scheduled one pass ahead, at an exact sample — no gap, no drift.
        if (looping) {
          final next = firstSample + (countIn + passStart + passLength) * rate;
          app.audio.call('audio.playNotes', {'notes': sequence(order, 0), 'start': 'sample', 'sample': next.round(), 'noteDuration': step});
        }
        for (var i = 0; i < indices.length; i++) {
          await sleepUntil(t0 + passStart + i * step);
          if (generation != _playGeneration) return;
          playingNote = NeckSpot(notes[indices[i]].course, notes[indices[i]].fret);
          _orderPosition = offset + i;
          changed();
        }
        passStart += passLength;
        pass += 1;
      } while (looping && generation == _playGeneration);
      await sleepUntil(t0 + passStart);
      if (generation != _playGeneration) return;
      _resumeIndex = null;
      _finishPlayback(keepNote: false);
    }();
    changed();
  }

  /// Screen toast (canvas «Гриф — позиция пересчитана»).
  String? toast;
  Timer? _toastTimer;

  void showToast(String text) {
    toast = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 3400), () {
      toast = null;
      changed();
    });
    changed();
  }

  // MARK: Chords (FB-17, FB-23)

  /// Strings sounding after a chord tap (the neck lights them for a moment).
  Set<int> strumming = {};

  /// Strings of the last stroke, low to high.
  List<int> strumOrder = [];
  int strumToken = 0;
  Timer? _strumTimer;

  void _strum(List<int> courses) {
    strumOrder = courses;
    strumming = courses.toSet();
    strumToken += 1;
    _strumTimer?.cancel();
    _strumTimer = Timer(const Duration(milliseconds: 700), () {
      strumming = {};
      changed();
    });
    changed();
  }

  int get _fretCount => _i(app.instrument['fretCount']);
  int get _capo => _i(app.instrument['capo']);

  /// Frets on screen: the current position, the custom window, or the whole neck.
  (int, int) get visibleFrets {
    final maxFret = _fretCount;
    if (mode == FretMode.progression) return progression.visibleFrets;
    final p = fromNotePreview;
    if (p != null) {
      final lo = math.max(0, p.position.lo - 1);
      return (lo, math.min(maxFret, math.max(lo + 9, p.position.hi + 4)));
    }
    final v = chordPreview;
    if (v != null) {
      // The sheet covers the lower half of the neck: the chord stands in the upper half.
      final fretted = v.notes.map((n) => n.fret).where((f) => f > 0).toList();
      final lo = v.usesOpenStrings ? 0 : math.max(1, (fretted.isEmpty ? 1 : fretted.reduce(math.min)) - 1);
      return (lo, math.min(maxFret, math.max(lo + 9, (fretted.isEmpty ? lo : fretted.reduce(math.max)) + 5)));
    }
    final cv = currentVoicing;
    if (mode == FretMode.chord && cv != null) {
      final fretted = cv.notes.map((n) => n.fret).where((f) => f > 0).toList();
      final lo = cv.usesOpenStrings ? 0 : math.max(1, (fretted.isEmpty ? 1 : fretted.reduce(math.min)) - 1);
      return (lo, math.min(maxFret, math.max(lo + 4, (fretted.isEmpty ? lo : fretted.reduce(math.max)) + 1)));
    }
    switch (settings.neckView) {
      case NeckDisplay.position:
        final range = currentPosition;
        if (range != null) {
          // With a capo the fret below it stays in view, dimmed (canvas «капо»).
          final capo = _capo;
          final lo = capo > 0 && range.lo <= capo ? math.max(1, capo - 1) : math.max(0, range.lo);
          return (lo, math.max(range.lo, range.hi));
        }
        return (0, math.min(maxFret, 12));
      case NeckDisplay.window:
        final end = math.min(maxFret, settings.windowStart + settings.windowLength - 1);
        return (settings.windowStart, math.max(settings.windowStart, end));
      case NeckDisplay.wholeNeck:
        return (0, maxFret);
    }
  }

  /// Tap on a chord: select it (or clear without sound) and strum it — a real shape near the visible frets, a
  /// downstroke 12 ms per string, ringing until the next chord or 2 s (FB-17, FB-23).
  void tapChord(int index) {
    final chords = keyChords;
    if (index >= chords.length) return;
    if (selectedChord == index) {
      selectedChord = null;
      changed();
      return;
    }
    selectedChord = index;
    final chord = chords[index];
    final range = visibleFrets;
    final r = _core('fretboard.strum', {
      'root': chord.root,
      'chordId': ?chord.chordId,
      'pitchClasses': chord.pitchClasses,
      'lo': range.$1,
      'hi': range.$2,
    });
    final notes = [for (final n in _maps(r)) (course: _i(n['course']), cents: _d(n['cents']))];
    if (notes.isEmpty) {
      changed();
      return;
    }
    _pauseTuner(2.15); // FB-23: the microphone ignores the phone's own sound (+150 ms)
    app.audio.ensurePlayback();
    app.audio.call('audio.stopNotes'); // the previous chord stops when the next one is struck
    app.audio.call('audio.playNotes', {
      'notes': [
        for (var i = 0; i < notes.length; i++) {'cents': notes[i].cents, 'offset': i * 0.012, 'string': notes[i].course},
      ],
      'start': 'now',
      'delay': 0.02,
      'velocity': 0.75,
      'noteDuration': 2,
    });
    _strum(notes.map((n) => n.course).toList());
  }

  /// «Пауза»: stops the sound and remembers the next note; the heard note stays lit so the place is visible.
  void stopPlayback() {
    final wasPlaying = isPlaying;
    _playGeneration += 1;
    app.audio.call('audio.stopNotes');
    final position = _orderPosition;
    if (wasPlaying && position != null) {
      final next = position + 1;
      _resumeIndex = next < _resumeOrderCount ? next : (loop ? 0 : null);
    }
    _finishPlayback(keepNote: _resumeIndex != null);
  }

  void _finishPlayback({required bool keepNote}) {
    isPlaying = false;
    _orderPosition = null;
    if (!keepNote) playingNote = null;
    _stopClick();
    changed();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _strumTimer?.cancel();
    _playGeneration += 1;
    super.dispose();
  }
}

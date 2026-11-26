/// Port of Truver/Sources/Persistence/Storage.swift
///
/// App settings as JSON with the Swift Codable field names. Core types (`MeterSettings`, `NoteName`,
/// `SongSection`, `Scale`, `Chord`, `Instrument`…) stay JSON maps exactly as the core encodes them — the Dart side
/// never re-models the core. Missing keys fall back to defaults field by field (a new field must not reset
/// everything the user set), as in `AppSettings.init(from:)`.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/truver_core.dart';

// MARK: Store

/// Key-value persistence: `shared_preferences` in the app, memory in tests (`TruverTestApp`).
abstract class SettingsStore {
  String? getString(String key);
  void setString(String key, String value);
  double? getDouble(String key);
  void setDouble(String key, double value);
  void remove(String key);
}

class PrefsStore implements SettingsStore {
  PrefsStore(this.prefs);
  final SharedPreferences prefs;

  static Future<PrefsStore> open() async => PrefsStore(await SharedPreferences.getInstance());

  @override
  String? getString(String key) => prefs.getString(key);
  @override
  void setString(String key, String value) => prefs.setString(key, value);
  @override
  double? getDouble(String key) => prefs.getDouble(key);
  @override
  void setDouble(String key, double value) => prefs.setDouble(key, value);
  @override
  void remove(String key) => prefs.remove(key);
}

class MemoryStore implements SettingsStore {
  MemoryStore([Map<String, Object>? initial]) : values = {...?initial};
  final Map<String, Object> values;

  @override
  String? getString(String key) => values[key] as String?;
  @override
  void setString(String key, String value) => values[key] = value;
  @override
  double? getDouble(String key) => (values[key] as num?)?.toDouble();
  @override
  void setDouble(String key, double value) => values[key] = value;
  @override
  void remove(String key) => values.remove(key);
}

// MARK: Helpers

/// A random UUID in Swift's uppercase form.
String newUuid() {
  final r = math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Deep copy of a JSON value.
T jsonCopy<T>(T value) => jsonDecode(jsonEncode(value)) as T;

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

double _d(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;
String _s(Object? v, String fallback) => v is String ? v : fallback;
Map<String, dynamic>? _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;
List<Map<String, dynamic>>? _ml(Object? v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : null;

/// Defaults of the core types inside the settings, encoded by the core (`shell.defaults`); the literal is the
/// same JSON for when the core is missing.
class CoreDefaults {
  CoreDefaults._(this.json);
  final Map<String, dynamic> json;

  static CoreDefaults? _cached;
  static CoreDefaults get instance {
    if (_cached != null) return _cached!;
    Map<String, dynamic>? fromCore;
    try {
      fromCore = _m(TruverCore.instance?.call('shell.defaults'));
    } catch (_) {}
    return _cached = CoreDefaults._(fromCore ?? _fallback);
  }

  static const _fallback = <String, dynamic>{
    'meter': {'bpm': 100, 'numerator': 4, 'denominator': 4, 'accents': [3, 2, 2, 2], 'subdivision': 1, 'swing': 0.5},
    'tonic': {'letter': 4, 'accidental': 0},
    'layout': 'threeNotesPerString',
    'eightNotePattern': 'threeThreeTwo',
    'clickPattern': 'backbeats',
    'song': [
      {'name': 'Вступление', 'bpm': 120, 'numerator': 4, 'denominator': 4, 'bars': 4},
      {'name': 'Куплет', 'bpm': 120, 'numerator': 4, 'denominator': 4, 'bars': 8},
      {'name': 'Припев', 'bpm': 128, 'numerator': 4, 'denominator': 4, 'bars': 8},
    ],
    'clickSound': 'click',
  };

  Map<String, dynamic> get meter => jsonCopy(_m(json['meter'])!);
  Map<String, dynamic> get tonic => jsonCopy(_m(json['tonic'])!);
  String get layout => json['layout'] as String;
  String get eightNotePattern => json['eightNotePattern'] as String;
  String get clickPattern => json['clickPattern'] as String;
  String get clickSound => json['clickSound'] as String;

  /// Fresh ids for every section, as `SongSection()` gives.
  List<Map<String, dynamic>> get song => [
        for (final s in _ml(json['song'])!) {...s, 'id': newUuid()},
      ];
}

// MARK: Enums

enum AppTab {
  tuner,
  fretboard,
  metronome,
  practice;

  static AppTab? byName(String? raw) => values.where((t) => t.name == raw).firstOrNull;
}

enum LabelMode {
  notes,
  degrees,
  intervals,
  fingers,
  none;

  String get title => switch (this) {
        LabelMode.notes => 'Ноты',
        LabelMode.degrees => 'Ступени',
        LabelMode.intervals => 'Интервалы',
        LabelMode.fingers => 'Пальцы',
        LabelMode.none => 'Без подписей',
      };
}

enum NeckDisplay { wholeNeck, position, window }

/// Where the beat flashes (6.1 п. 9): off, on the beat strip (default) or the whole screen.
enum FlashTarget { off, strip, screen }

// MARK: Fretboard

class FretboardSettings {
  FretboardSettings();

  String scaleId = 'major';

  /// Core `NoteName` JSON (`{"letter": 4, "accidental": 0}` = G).
  Map<String, dynamic> tonic = CoreDefaults.instance.tonic;

  /// Core `LayoutKind` raw value.
  String layout = CoreDefaults.instance.layout;
  NeckDisplay neckView = NeckDisplay.position;
  int positionNumber = 1;
  int windowStart = 0;
  int windowLength = 5;
  LabelMode labels = LabelMode.notes;
  bool lowStringOnTop = false;
  bool leftHanded = false;
  bool allowOpenStrings = true;

  /// Core `EightNotePattern` raw value.
  String eightNotePattern = CoreDefaults.instance.eightNotePattern;
  bool clickWithPlayback = true;

  /// FB-7 edits: cells hidden from or added to the scale, "course:fret".
  List<String> hiddenCells = [];
  List<String> addedCells = [];

  factory FretboardSettings.fromJson(Map<String, dynamic> j) {
    final d = FretboardSettings();
    return d
      ..scaleId = _s(j['scaleId'], d.scaleId)
      ..tonic = _m(j['tonic']) ?? d.tonic
      ..layout = _s(j['layout'], d.layout)
      ..neckView = _enumByName(NeckDisplay.values, j['neckView'], d.neckView)
      ..positionNumber = _i(j['positionNumber'], d.positionNumber)
      ..windowStart = _i(j['windowStart'], d.windowStart)
      ..windowLength = _i(j['windowLength'], d.windowLength)
      ..labels = _enumByName(LabelMode.values, j['labels'], d.labels)
      ..lowStringOnTop = _b(j['lowStringOnTop'], d.lowStringOnTop)
      ..leftHanded = _b(j['leftHanded'], d.leftHanded)
      ..allowOpenStrings = _b(j['allowOpenStrings'], d.allowOpenStrings)
      ..eightNotePattern = _s(j['eightNotePattern'], d.eightNotePattern)
      ..clickWithPlayback = _b(j['clickWithPlayback'], d.clickWithPlayback)
      ..hiddenCells = (j['hiddenCells'] as List?)?.cast<String>().toList() ?? d.hiddenCells
      ..addedCells = (j['addedCells'] as List?)?.cast<String>().toList() ?? d.addedCells;
  }

  Map<String, dynamic> toJson() => {
        'scaleId': scaleId,
        'tonic': tonic,
        'layout': layout,
        'neckView': neckView.name,
        'positionNumber': positionNumber,
        'windowStart': windowStart,
        'windowLength': windowLength,
        'labels': labels.name,
        'lowStringOnTop': lowStringOnTop,
        'leftHanded': leftHanded,
        'allowOpenStrings': allowOpenStrings,
        'eightNotePattern': eightNotePattern,
        'clickWithPlayback': clickWithPlayback,
        'hiddenCells': hiddenCells,
        'addedCells': addedCells,
      };
}

// MARK: Metronome

class MetronomePreset {
  MetronomePreset({String? id, required this.name, required this.settings, MetronomeModes? modes})
      : id = id ?? newUuid(),
        modes = modes ?? MetronomeModes();

  String id;
  String name;

  /// Core `MeterSettings` JSON.
  Map<String, dynamic> settings;
  MetronomeModes modes;

  static MetronomePreset? fromJson(Map<String, dynamic> j) {
    final name = j['name'], settings = _m(j['settings']);
    if (name is! String || settings == null) return null;
    final modes = _m(j['modes']);
    return MetronomePreset(
      id: j['id'] is String ? j['id'] as String : null,
      name: name,
      settings: settings,
      modes: modes == null ? null : MetronomeModes.fromJson(modes),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'settings': settings, 'modes': modes.toJson()};
}

enum ModeTempo { none, speedUp, twoForward, fastSlow, songMap }

enum ModeSubdivision { none, ladder }

enum ModeSound { none, displaced, gapBars, randomMute }

enum ModeInterval { bars, seconds }

/// Training modes in three groups — one per group (6.1 п. 7): tempo, subdivision, sound.
class MetronomeModes {
  MetronomeModes();

  ModeTempo tempo = ModeTempo.none;
  ModeSubdivision subdivision = ModeSubdivision.none;
  ModeSound sound = ModeSound.none;

  // Разгон / Два вперёд, один назад
  double start = 120;
  double target = 160;
  double step = 4;
  ModeInterval interval = ModeInterval.bars;
  int every = 4;
  int everySeconds = 30;

  /// Перенос щелчка: core `ClickPattern` raw value.
  String pattern = CoreDefaults.instance.clickPattern;
  // Пропадающие такты
  int gapOn = 4; // «Тренировка пропусков»: играет 4 такта, молчит 2 (canvas «Режимы»)
  int gapOff = 2;
  // Лесенка
  int ladderBarsPerStep = 2;
  // Быстро / медленно: `start` is the slow tempo (the knob sets it while stopped), `fast` the fast one.
  double fast = 160;
  int fastSlowBars = 4;
  // Случайный пропуск: chance in percent that a beat (not the first) drops.
  int muteChance = 30;

  /// Карта песни: core `SongSection` JSON maps in order, one-bar count-in, loop.
  List<Map<String, dynamic>> song = CoreDefaults.instance.song;
  bool songCountIn = true;
  bool songLoop = false;

  bool get isEmpty => tempo == ModeTempo.none && subdivision == ModeSubdivision.none && sound == ModeSound.none;

  factory MetronomeModes.fromJson(Map<String, dynamic> j) {
    final d = MetronomeModes();
    return d
      ..tempo = _enumByName(ModeTempo.values, j['tempo'], d.tempo)
      ..subdivision = _enumByName(ModeSubdivision.values, j['subdivision'], d.subdivision)
      ..sound = _enumByName(ModeSound.values, j['sound'], d.sound)
      ..start = _d(j['start'], d.start)
      ..target = _d(j['target'], d.target)
      ..step = _d(j['step'], d.step)
      ..interval = _enumByName(ModeInterval.values, j['interval'], d.interval)
      ..every = _i(j['every'], d.every)
      ..everySeconds = _i(j['everySeconds'], d.everySeconds)
      ..pattern = _s(j['pattern'], d.pattern)
      ..gapOn = _i(j['gapOn'], d.gapOn)
      ..gapOff = _i(j['gapOff'], d.gapOff)
      ..ladderBarsPerStep = _i(j['ladderBarsPerStep'], d.ladderBarsPerStep)
      ..fast = _d(j['fast'], d.fast)
      ..fastSlowBars = _i(j['fastSlowBars'], d.fastSlowBars)
      ..muteChance = _i(j['muteChance'], d.muteChance)
      ..song = _ml(j['song']) ?? d.song
      ..songCountIn = _b(j['songCountIn'], d.songCountIn)
      ..songLoop = _b(j['songLoop'], d.songLoop);
  }

  Map<String, dynamic> toJson() => {
        'tempo': tempo.name,
        'subdivision': subdivision.name,
        'sound': sound.name,
        'start': start,
        'target': target,
        'step': step,
        'interval': interval.name,
        'every': every,
        'everySeconds': everySeconds,
        'pattern': pattern,
        'gapOn': gapOn,
        'gapOff': gapOff,
        'ladderBarsPerStep': ladderBarsPerStep,
        'fast': fast,
        'fastSlowBars': fastSlowBars,
        'muteChance': muteChance,
        'song': song,
        'songCountIn': songCountIn,
        'songLoop': songLoop,
      };

  /// Names for chips, toasts and preset subtitles.
  static String tempoTitle(ModeTempo t) => switch (t) {
        ModeTempo.none => 'Нет',
        ModeTempo.speedUp => 'Разгон',
        ModeTempo.twoForward => 'Два вперёд, один назад',
        ModeTempo.fastSlow => 'Быстро / медленно',
        ModeTempo.songMap => 'Карта песни',
      };

  static String subdivisionTitle(ModeSubdivision s) => s == ModeSubdivision.ladder ? 'Лесенка делений' : 'Нет';

  static String soundTitle(ModeSound s) => switch (s) {
        ModeSound.none => 'Нет',
        ModeSound.displaced => 'Перенос щелчка',
        ModeSound.gapBars => 'Пропадающие такты',
        ModeSound.randomMute => 'Случайный пропуск',
      };

  /// Active mode names, tempo group first («Разгон», «Пропадающие такты»…).
  List<String> get activeTitles => [
        if (tempo != ModeTempo.none) tempoTitle(tempo),
        if (subdivision != ModeSubdivision.none) subdivisionTitle(subdivision),
        if (sound != ModeSound.none) soundTitle(sound),
      ];
}

class MetronomeSettingsState {
  MetronomeSettingsState();

  /// Core `MeterSettings` JSON (`MeterSettings(bpm: 100)` by default).
  Map<String, dynamic> meter = CoreDefaults.instance.meter;
  MetronomeModes modes = MetronomeModes();
  List<MetronomePreset> presets = [];

  /// The preset whose name is on the header chip; cleared when the settings drift from it.
  String? currentPresetId;
  bool timerEnabled = false;
  int timerMinutes = 20;

  /// Core `ClickSounds.Kind` raw value: click, wood, electronic, hiHat, voice.
  String sound = CoreDefaults.instance.clickSound;
  FlashTarget flash = FlashTarget.strip;

  /// «Громкость акцента»: the strong click over the normal one, dB (−3…+17).
  double accentDB = 6;

  MetronomePreset? get currentPreset => presets.where((p) => p.id == currentPresetId).firstOrNull;

  factory MetronomeSettingsState.fromJson(Map<String, dynamic> j) {
    final d = MetronomeSettingsState();
    final modes = _m(j['modes']);
    return d
      ..meter = _m(j['meter']) ?? d.meter
      ..modes = modes == null ? d.modes : MetronomeModes.fromJson(modes)
      ..presets = [for (final p in _ml(j['presets']) ?? const <Map<String, dynamic>>[]) ?MetronomePreset.fromJson(p)]
      ..currentPresetId = j['currentPresetId'] is String ? j['currentPresetId'] as String : null
      ..timerEnabled = _b(j['timerEnabled'], d.timerEnabled)
      ..timerMinutes = math.max(1, _i(j['timerMinutes'], d.timerMinutes))
      ..sound = _s(j['sound'], d.sound)
      ..flash = _enumByName(FlashTarget.values, j['flash'], d.flash)
      ..accentDB = _d(j['accentDB'], d.accentDB);
  }

  Map<String, dynamic> toJson() => {
        'meter': meter,
        'modes': modes.toJson(),
        'presets': [for (final p in presets) p.toJson()],
        if (currentPresetId != null) 'currentPresetId': currentPresetId,
        'timerEnabled': timerEnabled,
        'timerMinutes': timerMinutes,
        'sound': sound,
        'flash': flash.name,
        'accentDB': accentDB,
      };
}

// MARK: AppSettings

/// App settings (PRD 8 AppSettings), stored as JSON under the same key as iOS.
class AppSettings {
  AppSettings();

  /// Core `NoteNotation` raw value: international, german, solfege.
  String notation = 'international';
  double defaultA4 = 440;
  bool onboarded = false;
  AppTab lastTab = AppTab.tuner;
  bool tunerChromatic = false;
  bool vibration = false;
  FretboardSettings fretboard = FretboardSettings();
  MetronomeSettingsState metronome = MetronomeSettingsState();

  /// ME-9: manual output-latency correction in milliseconds, per output device name («Динамик»…).
  Map<String, double> latencyOffsets = {};

  /// TH-8: the user's own scales and chords (core `Scale` / `Chord` JSON).
  List<Map<String, dynamic>> customScales = [];
  List<Map<String, dynamic>> customChords = [];

  static const key = 'truver.settings.v1';

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final d = AppSettings();
    final fretboard = _m(j['fretboard']), metronome = _m(j['metronome']), latency = _m(j['latencyOffsets']);
    return d
      ..notation = _s(j['notation'], d.notation)
      ..defaultA4 = _d(j['defaultA4'], d.defaultA4)
      ..onboarded = _b(j['onboarded'], d.onboarded)
      ..lastTab = AppTab.byName(j['lastTab'] as String?) ?? d.lastTab
      ..tunerChromatic = _b(j['tunerChromatic'], d.tunerChromatic)
      ..vibration = _b(j['vibration'], d.vibration)
      ..fretboard = fretboard == null ? d.fretboard : FretboardSettings.fromJson(fretboard)
      ..metronome = metronome == null ? d.metronome : MetronomeSettingsState.fromJson(metronome)
      ..latencyOffsets = latency == null ? d.latencyOffsets : {for (final e in latency.entries) if (e.value is num) e.key: (e.value as num).toDouble()}
      ..customScales = _ml(j['customScales']) ?? d.customScales
      ..customChords = _ml(j['customChords']) ?? d.customChords;
  }

  Map<String, dynamic> toJson() => {
        'notation': notation,
        'defaultA4': defaultA4,
        'onboarded': onboarded,
        'lastTab': lastTab.name,
        'tunerChromatic': tunerChromatic,
        'vibration': vibration,
        'fretboard': fretboard.toJson(),
        'metronome': metronome.toJson(),
        'latencyOffsets': latencyOffsets,
        'customScales': customScales,
        'customChords': customChords,
      };

  String encode() => jsonEncode(toJson());

  AppSettings copy() => AppSettings.fromJson(toJson());

  static AppSettings load(SettingsStore store) {
    final raw = store.getString(key);
    if (raw == null) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  void save(SettingsStore store) => store.setString(key, encode());
}

// MARK: Instrument and journal

/// The instrument with its tunings (PR-1), stored as the core's Codable JSON (iOS: SwiftData `StoredInstrument`).
abstract final class StoredInstrument {
  static const key = 'truver.instrument.v1';

  static Map<String, dynamic>? load(SettingsStore store) {
    final raw = store.getString(key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (j['tunings'] as List?)?.isNotEmpty == true ? j : null;
    } catch (_) {
      return null;
    }
  }

  static void save(SettingsStore store, Map<String, dynamic> instrument) => store.setString(key, jsonEncode(instrument));
}

/// One practice session of the simple v1 journal (PL-0). Names are copied so the journal survives instrument
/// replacement (6.1 п. 19).
class PracticeEntry {
  PracticeEntry({required this.start, required this.instrumentName, required this.tuningName});

  DateTime start;
  double seconds = 0;
  String instrumentName;
  String tuningName;
  double lastBPM = 0;
  bool usedMetronome = false;
  bool tuned = false;

  /// The slowest tempo of the session (a speed trainer goes 142 → 150) and the preset that played.
  double minBPM = 0;
  String presetName = '';

  factory PracticeEntry.fromJson(Map<String, dynamic> j) => PracticeEntry(
        start: DateTime.fromMillisecondsSinceEpoch(_i(j['start'], 0)),
        instrumentName: _s(j['instrumentName'], ''),
        tuningName: _s(j['tuningName'], ''),
      )
        ..seconds = _d(j['seconds'], 0)
        ..lastBPM = _d(j['lastBPM'], 0)
        ..usedMetronome = _b(j['usedMetronome'], false)
        ..tuned = _b(j['tuned'], false)
        ..minBPM = _d(j['minBPM'], 0)
        ..presetName = _s(j['presetName'], '');

  Map<String, dynamic> toJson() => {
        'start': start.millisecondsSinceEpoch,
        'seconds': seconds,
        'instrumentName': instrumentName,
        'tuningName': tuningName,
        'lastBPM': lastBPM,
        'usedMetronome': usedMetronome,
        'tuned': tuned,
        'minBPM': minBPM,
        'presetName': presetName,
      };
}

/// The practice journal as a JSON list (iOS: SwiftData `PracticeEntry`).
abstract final class PracticeJournal {
  static const key = 'truver.practice.v1';

  static List<PracticeEntry> load(SettingsStore store) {
    final raw = store.getString(key);
    if (raw == null) return [];
    try {
      return [for (final e in jsonDecode(raw) as List) PracticeEntry.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      return [];
    }
  }

  static void save(SettingsStore store, List<PracticeEntry> entries) =>
      store.setString(key, jsonEncode([for (final e in entries) e.toJson()]));
}

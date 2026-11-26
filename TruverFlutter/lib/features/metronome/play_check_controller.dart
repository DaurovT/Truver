/// Port of Truver/Sources/Features/Metronome/PlayCheckController.swift
///
/// «Проверка игры» (stage SM): the microphone hears the attacks (SM-1), each is bound to the expected note of the
/// beat timeline (SM-2, ME-12) and graded (SM-3, SM-4); bars drive the tempo (SM-8) and the ceiling (SM-9).
///
/// Android: the attack analyser (`PlayCheckAnalyzer`, TruverAudio) is not in the Android core yet — the expected
/// notes are collected, but nothing is graded until the bridge exposes the onsets.
/// TODO(android): `audio.onsets` from an `OnsetDetector` on the AudioHost input + `RhythmGrader` / `RhythmStats` /
/// `AdaptiveTempo` through the bridge (grade a bar: expected notes + heard onsets → graded notes and bar stats).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../app/app_model.dart';
import '../../app/audio_services.dart';
import '../../design/icons.dart';
import '../../design/theme.dart';
import '../tuner/tuner_controller.dart';
import 'metronome_controller.dart';

/// One finished attempt of «Проверка игры» (PL-3 summary, PL-4 history).
class PlayAttempt {
  PlayAttempt({
    String? id,
    required this.date,
    this.preset,
    required this.seconds,
    required this.startBPM,
    required this.endBPM,
    this.ceiling,
    required this.accurateShare,
    required this.meanDeviation,
    required this.spread,
    this.weakestBeat,
    this.weakestBeatDeviation,
    required this.bars,
    this.silenceDrift,
    Map<int, double>? perBeat,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       perBeat = perBeat ?? {};

  final String id;
  final DateTime date;
  final String? preset;
  final double seconds;
  final double startBPM;
  final double endBPM;

  /// SM-9: the highest tempo with a clean step-up run.
  final double? ceiling;

  /// Share of «точно + хорошо» over counted bars.
  final double accurateShare;

  /// Mean signed deviation, ms (− rushes, + drags).
  final double meanDeviation;

  /// Spread, ms.
  final double spread;

  /// Beat with the largest mean deviation (0-based) and that deviation in ms.
  final int? weakestBeat;
  final double? weakestBeatDeviation;
  final int bars;

  /// SM-3: tempo drift over silent bars, ms.
  final double? silenceDrift;

  /// Per-beat mean deviation, ms (heat map, PL-4).
  final Map<int, double> perBeat;

  factory PlayAttempt.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    double? o(String k) => (j[k] as num?)?.toDouble();
    return PlayAttempt(
      id: j['id'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch((j['date'] as num?)?.toInt() ?? 0),
      preset: j['preset'] as String?,
      seconds: d('seconds'),
      startBPM: d('startBPM'),
      endBPM: d('endBPM'),
      ceiling: o('ceiling'),
      accurateShare: d('accurateShare'),
      meanDeviation: d('meanDeviation'),
      spread: d('spread'),
      weakestBeat: (j['weakestBeat'] as num?)?.toInt(),
      weakestBeatDeviation: o('weakestBeatDeviation'),
      bars: (j['bars'] as num?)?.toInt() ?? 0,
      silenceDrift: o('silenceDrift'),
      perBeat: {for (final e in (j['perBeat'] as Map? ?? const {}).entries) int.parse('${e.key}'): (e.value as num).toDouble()},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.millisecondsSinceEpoch,
    'preset': ?preset,
    'seconds': seconds,
    'startBPM': startBPM,
    'endBPM': endBPM,
    'ceiling': ?ceiling,
    'accurateShare': accurateShare,
    'meanDeviation': meanDeviation,
    'spread': spread,
    'weakestBeat': ?weakestBeat,
    'weakestBeatDeviation': ?weakestBeatDeviation,
    'bars': bars,
    'silenceDrift': ?silenceDrift,
    'perBeat': {for (final e in perBeat.entries) '${e.key}': e.value},
  };
}

/// `RhythmGrade` of the core.
enum RhythmGrade { exact, good, inaccurate, off, extra, missing, unrecognized }

/// A graded note on the deviation strip (`GradedNote`): deviation and the expected note's subdivision, seconds.
class GradedNote {
  const GradedNote({required this.grade, this.deviation, this.interval});
  final RhythmGrade grade;
  final double? deviation;

  /// The expected note's subdivision; null — an extra note without an expected one.
  final double? interval;
}

/// Statistics of one bar (`BarStats`).
class BarStats {
  const BarStats({
    required this.bar,
    required this.isCounted,
    required this.accurateShare,
    this.meanDeviation,
    this.spread,
    this.missing = 0,
  });
  final int bar;
  final bool isCounted;
  final double accurateShare;
  final double? meanDeviation;
  final double? spread;
  final int missing;
}

/// SM-6 states: «Нужна тишина» → progress → value / «Слишком шумно» / «Щелчки не слышны».
sealed class Calibration {
  const Calibration();
}

class CalibrationIdle extends Calibration {
  const CalibrationIdle();
}

class CalibrationRunning extends Calibration {
  const CalibrationRunning(this.progress);
  final double progress;
}

class CalibrationDone extends Calibration {
  const CalibrationDone(this.offset);
  final double offset;
}

class CalibrationFailed extends Calibration {
  const CalibrationFailed(this.reason);
  final String reason;
}

class PlayCheckSettings {
  PlayCheckSettings({this.adaptive = true, this.step = 4, this.cleanBars = 4});

  /// SM-8: tempo follows the result.
  bool adaptive;
  int step;
  int cleanBars;

  Map<String, dynamic> toJson() => {'adaptive': adaptive, 'step': step, 'cleanBars': cleanBars};
  factory PlayCheckSettings.fromJson(Map<String, dynamic> j) => PlayCheckSettings(
    adaptive: j['adaptive'] as bool? ?? true,
    step: (j['step'] as num?)?.toInt() ?? 4,
    cleanBars: (j['cleanBars'] as num?)?.toInt() ?? 4,
  );
}

class PlayCheckController extends ChangeNotifier {
  late AppModel _app;
  AppModel get app => _app;

  /// Set once by `AppModel` (after the tuner): tuner readings come in through [hearPitch].
  set app(AppModel value) {
    _app = value;
    value.tuner.readingListeners.add(hearPitch);
  }

  PlayCheckSettings? _settings;

  PlayCheckSettings get settings => _settings ??= _load('playcheck.settings', PlayCheckSettings.fromJson) ?? PlayCheckSettings();

  /// Changes the settings and stores them (Swift `didSet`).
  void updateSettings(void Function(PlayCheckSettings s) change) {
    change(settings);
    app.store.setString('playcheck.settings', jsonEncode(settings.toJson()));
    notifyListeners();
  }

  bool _isOn = false;

  /// «Проверка игры» is on: the microphone listens while the metronome plays.
  bool get isOn => _isOn;

  /// The newest graded notes, oldest first (deviation strip).
  List<GradedNote> recent = [];
  BarStats? lastBar;

  /// The subdivision is shorter than 40 ms: the metronome plays, the rhythm is not graded (SM-4).
  bool gradingUnavailable = false;

  /// The last bar had no attack at all: nobody plays yet — it is not graded and does not move the tempo.
  bool idle = false;

  /// Built-in speaker: the click reaches the microphone (SM-7).
  bool speakerMode = false;
  PlayAttempt? summary;
  List<PlayAttempt>? _history;

  List<PlayAttempt> get history => _history ??= [
    for (final e in (_loadRaw('playcheck.history') as List? ?? const [])) PlayAttempt.fromJson(Map<String, dynamic>.from(e as Map)),
  ];

  final List<Map<String, dynamic>> _expected = [];
  final List<BarStats> _barStats = [];
  DateTime? _attemptStart;
  double _startBPM = 0;

  // MARK: SM-6 latency calibration by loopback (speaker → microphone)

  Calibration calibration = const CalibrationIdle();
  bool _calibrating = false;

  /// Input + output pair the calibration belongs to.
  String get routeKey => 'playcheck.offset.?|${app.audio.outputName}';

  /// Residual delay of the microphone path measured by the loop (s), subtracted from attack times.
  double get routeOffset => app.store.getDouble(routeKey) ?? 0;

  /// «Нужна тишина» → clicks → median of attack − click. Built-in speaker only; headphones and interfaces use
  /// the system values (SM-6).
  Future<void> calibrate() async {
    if (_calibrating) return;
    final wasOn = isOn;
    if (!isOn) await enable();
    if (!isOn) return;
    if (!speakerMode) {
      calibration = const CalibrationFailed('Наушники или интерфейс: задержка берётся из системы, петля не нужна');
      notifyListeners();
      return;
    }
    _calibrating = true;
    calibration = const CalibrationRunning(0);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final wasPlaying = app.metronome.isPlaying;
    if (!wasPlaying) app.metronome.start();
    for (var i = 1; i <= 35; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      calibration = CalibrationRunning(i / 35);
      notifyListeners();
    }
    if (!wasPlaying) app.metronome.stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // TODO(android): onsets near each click from the analyser → median → `app.store.setDouble(routeKey, median)`.
    _calibrating = false;
    calibration = const CalibrationFailed('Щелчки не слышны — сделайте громче или поднесите телефон');
    if (!wasOn) disable();
    notifyListeners();
  }

  // MARK: Exercise (FB-14, SM-5): a note sequence played one per tick, pitches checked to a semitone.

  List<Object>? _exercisePitches;
  void Function(int)? _onNote;
  // ignore: unused_field — called by the grader on a wrong pitch (TODO(android) above).
  void Function(int)? _onWrong;
  int _exerciseCounter = 0;

  bool get hasExercise => _exercisePitches != null;

  /// `pitches`: whatever the caller identifies notes with (core `Pitch` JSON); `onNote(i)` fires when note i is due.
  void beginExercise({required List<Object> pitches, required void Function(int) onNote, required void Function(int) onWrong}) {
    _exercisePitches = pitches.isEmpty ? null : pitches;
    _onNote = onNote;
    _onWrong = onWrong;
    _exerciseCounter = 0;
    _pitchHistory.clear();
  }

  void endExercise() {
    _exercisePitches = null;
    _onNote = null;
    _onWrong = null;
  }

  /// (seconds, pitch) of steady tuner readings while an exercise runs, newest last (max 400).
  final List<(double, TunerPitch)> _pitchHistory = [];

  /// Tuner readings while an exercise runs: the pitch of each attack is the first steady reading after it.
  /// TODO(android): the grader picks `_pitchHistory` entries 30–300 ms after each onset (`pitch(after:)`).
  void hearPitch(TunerReading reading) {
    if (!isOn || _exercisePitches == null || reading.isProvisional) return;
    _pitchHistory.add((DateTime.now().microsecondsSinceEpoch / 1e6, reading.pitch));
    if (_pitchHistory.length > 400) _pitchHistory.removeRange(0, _pitchHistory.length - 400);
  }

  // MARK: On / off

  Future<void> enable() async {
    if (isOn) return;
    if (app.audio.micPermission == MicPermission.undetermined) await app.audio.requestMicPermission();
    if (app.audio.micPermission != MicPermission.granted) {
      app.show('Нужен доступ к микрофону — Настройки → Truver', icon: AppIcon.micOff, iconColor: TruverColors.sharp);
      return;
    }
    app.audio.ensureRecording();
    speakerMode = app.audio.outputName == 'Динамик';
    _isOn = true;
    _resetAttempt();
    // SM-9: a new session starts 10 % under the ceiling of this preset.
    final c = ceiling;
    if (settings.adaptive && !app.metronome.isPlaying && c != null && app.metronome.state.modes.tempo.name == 'none') {
      final start = nextSessionStart(c);
      if (start < app.metronome.bpm) {
        app.metronome.bpm = start;
        app.show('Старт на 10 % ниже потолка ${c.toInt()}: ${start.toInt()}', icon: AppIcon.metronome);
      }
    }
    // The input tap picks the observer up when it is installed.
    if (app.tuner.isListening) {
      app.tuner.handleAudioRestart();
    } else {
      app.updateListening();
    }
    notifyListeners();
    app.changed();
  }

  void disable() {
    if (!isOn) return;
    _finishAttempt();
    _isOn = false;
    if (app.tuner.isListening) app.tuner.handleAudioRestart();
    app.updateListening();
    notifyListeners();
    app.changed();
  }

  void toggle() => isOn ? disable() : unawaited(enable());

  String get _ceilingKey => 'playcheck.ceiling.${app.metronome.state.currentPresetId ?? 'free'}';

  double? get ceiling {
    final v = app.store.getDouble(_ceilingKey) ?? 0;
    return v > 0 ? v : null;
  }

  /// SM-9 `AdaptiveTempo.nextSessionStart` from the core.
  double nextSessionStart(double ceiling) {
    try {
      final r = app.core?.call('metronome.nextSessionStart', {'ceiling': ceiling});
      if (r is num) return r.toDouble();
    } catch (_) {}
    return (ceiling * 0.9).roundToDouble().clamp(20, 400);
  }

  void _resetAttempt() {
    _expected.clear();
    recent = [];
    lastBar = null;
    idle = false;
    _barStats.clear();
    gradingUnavailable = false;
    _attemptStart = null;
  }

  // MARK: Timeline in

  /// Every tick of the main track as it sounds (from the metronome's poll): an `audio.poll` tick map.
  void expect(Map<String, dynamic> tick) {
    if (!isOn) return;
    final bpm = (tick['bpm'] as num).toDouble();
    if (_attemptStart == null) {
      _attemptStart = DateTime.now();
      _startBPM = bpm;
    }
    if (_calibrating || tick['rest'] == true) return;
    final exercise = _exercisePitches;
    if (exercise != null) {
      if ((tick['bar'] as num) < 1) return; // bar 0 is the count-in
      final index = _exerciseCounter % exercise.length;
      _exerciseCounter += 1;
      _onNote?.call(index);
    }
    _expected.add({...tick, 'interval': 60 / bpm / ((tick['subdivision'] as num).toInt().clamp(1, 64))});
    if (_expected.length > 512) _expected.removeRange(0, _expected.length - 512);
  }

  /// Grades every bar the analyser has fully heard (called from the metronome's poll).
  /// TODO(android): needs the analyser's onsets (see the file comment); until then nothing is graded.
  void update() {}

  // MARK: Attempt summary (PL-3)

  /// The metronome stopped: the attempt ends (it continues if the metronome starts again while on).
  void metronomeStopped() {
    if (!isOn) return;
    _finishAttempt();
    _resetAttempt();
  }

  void _finishAttempt() {
    final start = _attemptStart;
    if (start == null) return;
    final counted = _barStats.where((b) => b.isCounted).toList();
    if (counted.length < 2) return;
    final attempt = PlayAttempt(
      date: DateTime.now(),
      preset: app.metronome.state.currentPreset?.name,
      seconds: DateTime.now().difference(start).inMilliseconds / 1000,
      startBPM: _startBPM,
      endBPM: app.metronome.bpm,
      accurateShare: counted.map((b) => b.accurateShare).reduce((a, b) => a + b) / counted.length,
      meanDeviation: 0,
      spread: 0,
      bars: counted.length,
    );
    history.add(attempt);
    if (history.length > 300) history.removeRange(0, history.length - 300);
    app.store.setString('playcheck.history', jsonEncode([for (final a in history) a.toJson()]));
    summary = attempt;
    if (!app.session.isRunning) app.sheet = const AppSheet('playCheckSummary'); // the session shows it in its own summary
    notifyListeners();
  }

  /// Screenshot hook: two weeks of attempts for the charts (not saved).
  void injectHistoryDemo() {
    final now = DateTime.now();
    _history = [
      for (var i = 0; i < 14; i++)
        PlayAttempt(
          date: now.subtract(Duration(days: 13 - i)),
          preset: 'Риф 7/8',
          seconds: 600,
          startBPM: 120,
          endBPM: 128 + i * 1.5,
          ceiling: 126 + i * 1.6,
          accurateShare: 0.8,
          meanDeviation: -5,
          spread: 16 - i * 0.6,
          weakestBeat: 3,
          weakestBeatDeviation: -12,
          bars: 40,
          perBeat: const {0: -2, 1: 4, 2: -6, 3: -13, 4: 3, 5: 8, 6: -1},
        ),
    ];
    notifyListeners();
  }

  /// Screenshot hook: a finished attempt.
  void injectDemo() {
    summary = PlayAttempt(
      date: DateTime.now(),
      preset: 'Риф 7/8',
      seconds: 312,
      startBPM: 132,
      endBPM: 148,
      ceiling: 144,
      accurateShare: 0.87,
      meanDeviation: -6.2,
      spread: 9.4,
      weakestBeat: 3,
      weakestBeatDeviation: -14,
      bars: 46,
    );
    notifyListeners();
  }

  Object? _loadRaw(String key) {
    final raw = app.store.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  T? _load<T>(String key, T Function(Map<String, dynamic>) decode) {
    final raw = _loadRaw(key);
    return raw is Map ? decode(Map<String, dynamic>.from(raw)) : null;
  }

  /// `MetronomeController.bars` for the summary.
  static String bars(int n) => MetronomeController.bars(n);
}

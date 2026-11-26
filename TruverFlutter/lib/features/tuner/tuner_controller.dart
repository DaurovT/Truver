/// Port of Truver/Sources/Features/Tuner/TunerController.swift
///
/// Tuner screen state (6.2.4) on top of the core pitch tracker. The tracker runs in the core (`audio.startTuner`);
/// its updates arrive once per frame through `audio.poll` (DTOs of TruverBridge/AudioCommands.swift, note labels
/// already formatted by the core).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/app_model.dart';
import '../../app/audio_services.dart';
import 'tuner_demo.dart';

// MARK: Core values (TruverDSP TunerReading / TunerDisplay as the bridge sends them)

/// A string of the tuning: course (0 = lowest) and the string inside the course.
@immutable
class StringRef {
  const StringRef(this.course, [this.string = 0]);
  final int course;
  final int string;

  static StringRef? fromJson(Object? json) =>
      json is Map ? StringRef((json['course'] as num).toInt(), (json['string'] as num?)?.toInt() ?? 0) : null;

  @override
  bool operator ==(Object other) => other is StringRef && other.course == course && other.string == string;

  @override
  int get hashCode => Object.hash(course, string);

  @override
  String toString() => 'StringRef($course, $string)';
}

/// `PitchDTO`: cents from A4 = 440 and the core's labels («A2», «A», 2).
@immutable
class TunerPitch {
  const TunerPitch({required this.cents, required this.label, required this.name, required this.octave});
  final double cents;
  final String label;
  final String name;
  final int octave;

  factory TunerPitch.fromJson(Map json) => TunerPitch(
        cents: (json['cents'] as num).toDouble(),
        label: json['label'] as String? ?? '',
        name: json['name'] as String? ?? '',
        octave: (json['octave'] as num?)?.toInt() ?? 0,
      );

  /// `Pitch.frequency(a4:)`.
  double frequency(double a4) => a4 * math.pow(2, cents / 1200).toDouble();
}

/// `TunerTarget`: a string of the tuning, or the nearest note (chromatic) with an optional nearest-string hint.
@immutable
class TunerTarget {
  const TunerTarget({
    required this.isString,
    this.string,
    required this.target,
    required this.deviationCents,
    this.hintString,
    this.hintTarget,
    this.hintDeviation,
  });
  final bool isString;
  final StringRef? string;
  final TunerPitch target;

  /// played − target; negative: flat, tighten.
  final double deviationCents;
  final StringRef? hintString;
  final TunerPitch? hintTarget;
  final double? hintDeviation;

  factory TunerTarget.fromJson(Map json) => TunerTarget(
        isString: json['kind'] == 'string',
        string: StringRef.fromJson(json['string']),
        target: TunerPitch.fromJson(json['target'] as Map),
        deviationCents: (json['deviation'] as num).toDouble(),
        hintString: StringRef.fromJson(json['hintString']),
        hintTarget: json['hintTarget'] is Map ? TunerPitch.fromJson(json['hintTarget'] as Map) : null,
        hintDeviation: (json['hintDeviation'] as num?)?.toDouble(),
      );
}

@immutable
class TunerReading {
  const TunerReading({required this.frequency, required this.pitch, required this.target, this.isProvisional = false, this.isInTune = false});
  final double frequency;
  final TunerPitch pitch;
  final TunerTarget target;
  final bool isProvisional;
  final bool isInTune;

  factory TunerReading.fromJson(Map json) => TunerReading(
        frequency: (json['frequency'] as num).toDouble(),
        pitch: TunerPitch.fromJson(json['pitch'] as Map),
        target: TunerTarget.fromJson(json['target'] as Map),
        isProvisional: json['provisional'] == true,
        isInTune: json['inTune'] == true,
      );
}

enum TunerDisplayKind { idle, listening, outOfRange, reading }

@immutable
class TunerDisplay {
  const TunerDisplay(this.kind, [this.reading]);
  static const idle = TunerDisplay(TunerDisplayKind.idle);
  final TunerDisplayKind kind;
  final TunerReading? reading;
}

/// TU-10 `StrobeReading`.
@immutable
class StrobeReading {
  const StrobeReading({required this.cents, required this.angle, required this.isStable, required this.harmonic});
  final double cents;
  final double angle;
  final bool isStable;
  final int harmonic;
}

// MARK: Controller

enum TunerModeKind { auto, chromatic, manual }

@immutable
class TunerMode {
  const TunerMode._(this.kind, [this.ref]);
  static const auto = TunerMode._(TunerModeKind.auto);
  static const chromatic = TunerMode._(TunerModeKind.chromatic);
  const TunerMode.manual(StringRef ref) : this._(TunerModeKind.manual, ref);

  final TunerModeKind kind;

  /// The selected string in manual mode.
  final StringRef? ref;

  @override
  bool operator ==(Object other) => other is TunerMode && other.kind == kind && other.ref == ref;

  @override
  int get hashCode => Object.hash(kind, ref);
}

/// Last known state of each string, shown as the coloured bar under its button (design: green = in tune,
/// blue = flat, orange = sharp, neutral = not played yet).
enum StringStatus { unknown, flat, sharp, inTune }

/// Segmented control «Авто / Ручной / Хром.».
enum TunerChoice { auto, manual, chromatic }

/// TU-11 «Проверка мензуры» step.
@immutable
class IntonationStep {
  const IntonationStep._(this.kind, [this.cents = 0]);
  static const open = IntonationStep._(0);
  static const twelfth = IntonationStep._(1);
  const IntonationStep.result(double cents) : this._(2, cents);
  final int kind;
  final double cents;
  bool get isResult => kind == 2;

  @override
  bool operator ==(Object other) => other is IntonationStep && other.kind == kind && other.cents == cents;

  @override
  int get hashCode => Object.hash(kind, cents);
}

/// One course of the current tuning as the core describes it (`tuner.strings`).
@immutable
class TunerCourse {
  const TunerCourse({required this.name, required this.short, required this.octave, required this.strings, required this.scaleLength});
  final String name;
  final String short;
  final int octave;

  /// (label, frequency) of each string of the course.
  final List<(String, double)> strings;
  final double scaleLength;
}

class TunerController extends ChangeNotifier {
  late AppModel app;

  TunerMode _mode = TunerMode.auto;
  TunerMode get mode => _mode;
  set mode(TunerMode value) {
    if (value == _mode) return;
    _mode = value;
    if (isListening) _restartPipeline();
    _changed();
  }

  /// Noise threshold of the pro panel (TU-3).
  double _noiseGate = -55;
  double get noiseGate => _noiseGate;
  set noiseGate(double value) {
    if (value == _noiseGate) return;
    _noiseGate = value;
    if (isListening) _restartPipeline();
    _changed();
  }

  /// TU-10: strobe view — the ring follows the signal phase, cents to a tenth (stored as `tuner.strobe`).
  bool get strobeView => app.store.getString('tuner.strobe') == 'true';
  set strobeView(bool value) {
    app.store.setString('tuner.strobe', value ? 'true' : 'false');
    strobe = null;
    if (isListening) _restartPipeline();
    _changed();
  }

  StrobeReading? strobe;

  /// Range of the «Порог шума» slider (canvas «Тюнер — дополнительно»: −55 дБ sits at 45 % of the track).
  static const noiseGateMin = -73.0, noiseGateMax = -33.0;

  // MARK: Route notices (canvas «Тюнер — Bluetooth», «Интерфейс отключён», «Вход переключён»)

  RouteNotice? _notice;
  RouteNotice? get notice => _notice;
  set notice(RouteNotice? value) {
    _notice = value;
    _noticeTimer?.cancel();
    // The card with buttons stays until «Понятно»; the others leave by themselves.
    if (value != null && value.kind != RouteNoticeKind.bluetooth) {
      _noticeTimer = Timer(Duration(seconds: value.kind == RouteNoticeKind.disconnected ? 6 : 3), () => notice = null);
    }
    _changed();
  }

  Timer? _noticeTimer;

  /// «Звук в динамик»: the output goes to the built-in speaker.
  /// TODO(android): AudioManager.setSpeakerphoneOn / setCommunicationDevice once the host reports routes.
  void routeToSpeaker() {}

  // MARK: TU-11 «Проверка мензуры»

  int? intonationCourse;
  IntonationStep intonationStep = IntonationStep.open;

  /// Results of this session by course (cents, 12th fret − octave).
  final Map<int, double> intonationResults = {};
  double intonationProgress = 0;

  /// «Слышу A2 — сыграйте струну 6»: a note that does not belong to the step.
  String? intonationHint;
  List<double> _intonationReadings = [];
  double? _intonationOpen;
  TunerMode? _modeBeforeCheck;

  void beginIntonation(int course) {
    _modeBeforeCheck ??= mode;
    if (mode != TunerMode.chromatic) mode = TunerMode.chromatic; // any note gives a reading
    intonationCourse = course;
    intonationStep = IntonationStep.open;
    _intonationOpen = null;
    _intonationReadings = [];
    intonationProgress = 0;
    intonationHint = null;
    _changed();
  }

  void repeatIntonationStep() {
    _intonationReadings = [];
    intonationProgress = 0;
    intonationHint = null;
    final course = intonationCourse;
    if (intonationStep.isResult && course != null) {
      beginIntonation(course);
    } else {
      _changed();
    }
  }

  /// Debug (`-intonationDemo`, canvas «Проверка мензуры»): step 1 on the lowest string, a wrong note heard, the
  /// first readings in.
  void injectIntonationDemo(String hint) {
    beginIntonation(0);
    intonationHint = hint;
    intonationProgress = 0.06;
    _changed();
  }

  void endIntonation() {
    intonationCourse = null;
    final previous = _modeBeforeCheck;
    if (previous != null) mode = previous;
    _modeBeforeCheck = null;
    _changed();
  }

  void _feedIntonation(TunerReading reading) {
    final course = intonationCourse;
    if (course == null || reading.isProvisional) return;
    final f = reading.frequency;
    double expected;
    switch (intonationStep.kind) {
      case 0:
        expected = openFrequency(StringRef(course));
      case 1:
        expected = 2 * (_intonationOpen ?? 0);
      default:
        return;
    }
    final off = (1200 * _log2(f / expected)).abs();
    if (!(off < (intonationStep == IntonationStep.open ? 150 : 100))) {
      // The other note still rings (the open string under the 12th fret) — ignore quietly near the octave.
      if (intonationStep == IntonationStep.open || (1200 * _log2(f / (expected / 2))).abs() > 100) {
        intonationHint = 'Слышу ${reading.pitch.label}';
      }
      return;
    }
    intonationHint = null;
    _intonationReadings.add(f);
    intonationProgress = math.min(1, _intonationReadings.length / 16);
    final steady = _steadyFrequency(_intonationReadings);
    if (steady == null) return;
    if (intonationStep == IntonationStep.open) {
      _intonationOpen = steady;
      intonationStep = IntonationStep.twelfth;
      _intonationReadings = [];
      intonationProgress = 0;
      HapticFeedback.lightImpact();
    } else if (_intonationOpen != null) {
      final result = app.core?.call('tuner.intonation', {'open': _intonationOpen, 'twelfth': steady, 'course': course});
      final cents = result is Map ? (result['cents'] as num).toDouble() : 1200 * _log2(steady / (2 * _intonationOpen!));
      intonationResults[course] = cents;
      intonationStep = IntonationStep.result(cents);
      // iOS `UINotificationFeedbackGenerator.success`; Android has no notification haptic.
      HapticFeedback.mediumImpact();
    }
  }

  double? _steadyFrequency(List<double> readings) {
    if (readings.length < 16) return null;
    try {
      final r = app.core?.call('tuner.steadyFrequency', {'readings': readings.sublist(readings.length - 16)});
      return r is Map ? (r['frequency'] as num?)?.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  static double _log2(double x) => math.log(x) / math.ln2;

  // MARK: Live state

  TunerDisplay display = TunerDisplay.idle;
  double level = -160;
  final Set<StringRef> tuned = {};
  bool allTuned = false;
  bool _listening = false;
  bool get isListening => _listening;
  MicPermission permission = MicPermission.undetermined;
  DateTime? referenceUntil;
  String? error;
  final Map<StringRef, StringStatus> stringStatus = {};

  /// The last reading, kept for the waiting state (the dial shows the last note) and the reference button.
  TunerReading? lastReading;
  StringRef? lastString;
  StringRef? referenceString;

  /// `-tunerDemo …` (debug): freezes the screen on a reading of the canvas (no guitar in the simulator / tests).
  TunerDemo? demo;

  /// Modules hearing the tuner's readings: the fret trainer (`trainer.hear`), «Проверка игры»
  /// (`playCheck.hearPitch`). They subscribe here so the tuner does not depend on their controllers.
  final List<void Function(TunerReading reading)> readingListeners = [];

  /// Practice tracker (`practice.activity(tuned:)`): `false` on every reading, `true` when all strings are tuned.
  final List<void Function(bool tuned)> activityListeners = [];

  /// FB-23: while the app's own notes ring, the tuner does not take them for the player's string.
  void pauseForPlayback(double seconds) {
    if (_listening) app.audio.call('audio.pauseAnalysis', {'seconds': seconds});
  }

  bool get isReferencePlaying => referenceUntil != null && referenceUntil!.isAfter(DateTime.now());

  /// State 1 of 6.2.4: on iOS the metronome is playing and switching the audio session to record would interrupt
  /// its click for a moment, so the tuner waits for «Включить микрофон». Android's AAudio input opens next to the
  /// running output stream without a gap, so this state never comes up here.
  bool get needsMicrophoneButton => false;

  bool _wanted = false;

  /// Opens the microphone and starts listening (AU-4): called by `AppModel.updateListening` when the tab opens
  /// (6.1 п. 1).
  Future<void> start({bool confirmedGap = false}) async {
    _wanted = true;
    if (_listening) return;
    permission = await app.audio.requestMicPermission();
    // Android has no profile restriction: «restricted» from AudioServices is «don't ask again», which the user can
    // still lift in the app's settings — the «Нужен микрофон / Открыть Настройки» state, not «Доступ ограничен».
    if (defaultTargetPlatform == TargetPlatform.android && permission == MicPermission.restricted) permission = MicPermission.denied;
    _changed();
    if (permission != MicPermission.granted || !_wanted || _listening) return;
    if (needsMicrophoneButton && !confirmedGap) return;
    app.audio.ensureRecording();
    if (_installPipeline()) {
      _listening = true;
      error = null;
      app.audio.addPollListener(_poll);
    }
    _changed();
  }

  void stop() {
    _wanted = false;
    if (_listening) app.audio.call('audio.stopTuner');
    app.audio.removePollListener(_poll);
    _listening = false;
    display = TunerDisplay.idle;
    _changed();
  }

  /// The current tuning or its strings changed.
  void tuningChanged() {
    _courses = null;
    tuned.clear();
    allTuned = false;
    stringStatus.clear();
    lastReading = null;
    lastString = null;
    if (mode.kind == TunerModeKind.manual) _mode = TunerMode.auto;
    if (_listening) _restartPipeline();
    _changed();
  }

  /// The audio route or configuration changed; restart the input if listening.
  void handleAudioRestart() {
    if (_listening) _restartPipeline();
  }

  /// 6.2.4 #9: tap on a string selects it (manual mode); tap again returns to auto.
  void tapString(StringRef ref) {
    mode = mode == TunerMode.manual(ref) ? TunerMode.auto : TunerMode.manual(ref);
  }

  /// TU-9: reference tone of the selected (or given) string for 3 s; analysis pauses meanwhile (6.1 п. 5).
  /// A second tap while it sounds stops it.
  void playReference(StringRef ref) {
    if (isReferencePlaying) {
      stopReference();
      if (referenceString == ref) return;
    }
    referenceString = ref;
    app.audio.ensurePlayback();
    app.audio.call('audio.playNotes', {
      'notes': [
        {'frequency': openFrequency(ref)},
      ],
      'kind': 'reference',
      'duration': 3,
    });
    referenceUntil = DateTime.now().add(const Duration(seconds: 3));
    referenceSecondsLeft = 3;
    display = TunerDisplay.idle;
    // Live countdown «3 → 2 → 1 с».
    _referenceTimer?.cancel();
    _referenceTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final until = referenceUntil;
      if (until != null && until.isAfter(DateTime.now())) {
        referenceSecondsLeft = math.max(1, (until.difference(DateTime.now()).inMilliseconds / 1000).ceil());
      } else {
        timer.cancel();
        referenceSecondsLeft = 0;
        referenceUntil = null;
      }
      _changed();
    });
    _changed();
  }

  void stopReference() {
    _referenceTimer?.cancel();
    app.audio.call('audio.stopNotes');
    referenceUntil = null;
    referenceSecondsLeft = 0;
    _changed();
  }

  /// Whole seconds left of the reference tone, updated live.
  int referenceSecondsLeft = 0;
  Timer? _referenceTimer;

  /// The string the reference button plays: the manual one, else the last heard, else the lowest.
  StringRef get referenceTarget => mode.ref ?? lastString ?? const StringRef(0);

  /// Segmented control «Авто / Ручной / Хром.»; «Ручной» takes the last heard string (or the lowest).
  TunerChoice get choice => switch (mode.kind) {
        TunerModeKind.auto => TunerChoice.auto,
        TunerModeKind.manual => TunerChoice.manual,
        TunerModeKind.chromatic => TunerChoice.chromatic,
      };
  set choice(TunerChoice value) {
    switch (value) {
      case TunerChoice.auto:
        mode = TunerMode.auto;
      case TunerChoice.chromatic:
        mode = TunerMode.chromatic;
      case TunerChoice.manual:
        if (mode.kind != TunerModeKind.manual) mode = TunerMode.manual(lastString ?? const StringRef(0));
    }
  }

  void resetMarks() {
    tuned.clear();
    allTuned = false;
    stringStatus.clear();
    if (_listening) _restartPipeline();
    _changed();
  }

  // MARK: Tuning facts from the core

  List<TunerCourse>? _courses;

  /// Courses of the current tuning (names, octaves, open frequencies), cached until the tuning changes.
  List<TunerCourse> get courses {
    final cached = _courses;
    if (cached != null && cached.length == app.courseCount) return cached;
    final result = <TunerCourse>[];
    Object? raw;
    try {
      raw = app.core?.call('tuner.strings');
    } catch (_) {}
    if (raw is Map && raw['courses'] is List) {
      for (final c in (raw['courses'] as List).cast<Map>()) {
        result.add(TunerCourse(
          name: c['name'] as String,
          short: c['short'] as String,
          octave: (c['octave'] as num).toInt(),
          strings: [for (final s in (c['strings'] as List).cast<Map>()) (s['label'] as String, (s['frequency'] as num).toDouble())],
          scaleLength: (c['scaleLength'] as num).toDouble(),
        ));
      }
    } else {
      // Older core without `tuner.strings`: names from the shell commands.
      final open = (app.tuning['openCents'] as List?) ?? const [];
      for (var c = 0; c < open.length; c++) {
        final label = app.stringName(c);
        final split = RegExp(r'^(.*?)(-?\d+)$').firstMatch(label);
        final cents = ((open[c] as List).first as num).toDouble();
        result.add(TunerCourse(
          name: split?.group(1) ?? label,
          short: split?.group(1) ?? label,
          octave: int.tryParse(split?.group(2) ?? '') ?? 0,
          strings: [(label, app.a4 * math.pow(2, cents / 1200).toDouble())],
          scaleLength: 648,
        ));
      }
    }
    _courses = result;
    return result;
  }

  /// Open frequency of a string at the tuning's A4 (`tuning.openPitch(course:string:).frequency(a4:)`).
  double openFrequency(StringRef ref) {
    final c = courses;
    if (ref.course < 0 || ref.course >= c.length) return 0;
    final strings = c[ref.course].strings;
    return strings[ref.string.clamp(0, strings.length - 1)].$2;
  }

  /// `app.stringName(ref)`.
  String stringName(StringRef ref) {
    final c = courses;
    if (ref.course < 0 || ref.course >= c.length) return '';
    final strings = c[ref.course].strings;
    return strings[ref.string.clamp(0, strings.length - 1)].$1;
  }

  // MARK: Pipeline

  void _restartPipeline() {
    app.audio.call('audio.stopTuner');
    if (!_installPipeline()) _changed();
  }

  bool _installPipeline() {
    final channel = app.store.getDouble('tuner.inputChannel')?.toInt() ?? int.tryParse(app.store.getString('tuner.inputChannel') ?? '') ?? 0;
    final result = app.audio.call('audio.startTuner', {
      'mode': mode.kind.name,
      if (mode.ref != null) 'course': mode.ref!.course,
      if (mode.ref != null) 'string': mode.ref!.string,
      'noiseGate': noiseGate,
      'strobe': strobeView,
      'channel': channel,
    });
    if (result == null) {
      error = app.audio.available ? 'audio.startTuner' : 'Звук недоступен';
      return false;
    }
    return true;
  }

  /// Feeds one `audio.poll` result as if it came from the core (tests).
  @visibleForTesting
  void applyPoll(AudioPoll poll) => _poll(poll);

  void _poll(AudioPoll poll) {
    final updates = poll['tuner'];
    if (updates is! List || updates.isEmpty) return;
    for (final u in updates) {
      if (u is Map) _apply(u);
    }
    _changed();
  }

  void _apply(Map update) {
    level = (update['level'] as num?)?.toDouble() ?? level;
    if (isReferencePlaying) return;
    final kind = switch (update['display']) {
      'listening' => TunerDisplayKind.listening,
      'outOfRange' => TunerDisplayKind.outOfRange,
      'reading' => TunerDisplayKind.reading,
      _ => TunerDisplayKind.idle,
    };
    final reading = update['reading'] is Map ? TunerReading.fromJson(update['reading'] as Map) : null;
    display = kind == TunerDisplayKind.reading && reading != null ? TunerDisplay(kind, reading) : TunerDisplay(kind == TunerDisplayKind.reading ? TunerDisplayKind.idle : kind);
    final s = update['strobe'];
    strobe = s is Map
        ? StrobeReading(
            cents: (s['cents'] as num).toDouble(),
            angle: (s['angle'] as num).toDouble(),
            isStable: s['stable'] == true,
            harmonic: (s['harmonic'] as num?)?.toInt() ?? 1,
          )
        : null;
    if (reading != null) {
      if (intonationCourse != null) _feedIntonation(reading);
      for (final l in List.of(readingListeners)) {
        l(reading);
      }
      for (final l in List.of(activityListeners)) {
        l(false);
      }
      lastReading = reading;
      final ref = reading.target.string;
      if (reading.target.isString && ref != null) {
        lastString = ref;
        final deviation = reading.target.deviationCents;
        if (reading.isInTune || (tuned.contains(ref) && deviation.abs() <= 5)) {
          stringStatus[ref] = StringStatus.inTune;
        } else {
          stringStatus[ref] = deviation < 0 ? StringStatus.flat : StringStatus.sharp;
        }
      }
    }
    final justTuned = update['tuned'];
    if (justTuned is List) {
      for (final t in justTuned) {
        final ref = StringRef.fromJson(t);
        if (ref == null) continue;
        tuned.add(ref);
        HapticFeedback.lightImpact();
      }
    }
    if (update['allTuned'] == true) {
      allTuned = true;
      for (final l in List.of(activityListeners)) {
        l(true);
      }
      HapticFeedback.mediumImpact();
    }
  }

  void _changed() {
    notifyListeners();
    app.changed();
  }

  @override
  void dispose() {
    _referenceTimer?.cancel();
    _noticeTimer?.cancel();
    app.audio.removePollListener(_poll);
    super.dispose();
  }
}

/// Port of Truver/Sources/Features/Practice/FretTrainerController.swift
///
/// FB-12 state: the series, timing, feedback and — for «Сыграй ноту» — the tuner's readings (chromatic mode while
/// the trainer is open; the microphone is on only then, AU-4). The series itself (questions, retries, summary) is
/// the core's `FretTrainer`, run through the bridge (`practice.trainer*`, TruverBridge/PracticeCommands.swift).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../app/app_model.dart';
import '../tuner/tuner_controller.dart';

enum TrainerKind { nameNote, playNote }

enum TrainerStrings { all, low, high }

enum TrainerFrets { first12, whole, upper }

/// Right / wrong feedback of the last answer.
@immutable
class TrainerFeedback {
  const TrainerFeedback._(this.kind, [this.expected, this.heard]);
  static const none = TrainerFeedback._(0);
  static const correct = TrainerFeedback._(1);
  const TrainerFeedback.wrong({required int expected, int? heard}) : this._(2, expected, heard);

  final int kind;
  final int? expected;
  final int? heard;

  bool get isNone => kind == 0;
  bool get isCorrect => kind == 1;
  bool get isWrong => kind == 2;

  @override
  bool operator ==(Object other) => other is TrainerFeedback && other.kind == kind && other.expected == expected && other.heard == heard;

  @override
  int get hashCode => Object.hash(kind, expected, heard);
}

class TrainerSettings {
  TrainerSettings({
    this.kind = TrainerKind.nameNote,
    this.strings = TrainerStrings.all,
    this.frets = TrainerFrets.first12,
    this.naturalsOnly = false,
    this.count = 20,
    this.showString = true,
  });

  TrainerKind kind;
  TrainerStrings strings;
  TrainerFrets frets;
  bool naturalsOnly;
  int count;
  bool showString;

  TrainerSettings copy() =>
      TrainerSettings(kind: kind, strings: strings, frets: frets, naturalsOnly: naturalsOnly, count: count, showString: showString);

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) => values.where((v) => v.name == name).firstOrNull ?? fallback;

  factory TrainerSettings.fromJson(Map<String, dynamic> j) => TrainerSettings(
    kind: _enum(TrainerKind.values, j['kind'], TrainerKind.nameNote),
    strings: _enum(TrainerStrings.values, j['strings'], TrainerStrings.all),
    frets: _enum(TrainerFrets.values, j['frets'], TrainerFrets.first12),
    naturalsOnly: j['naturalsOnly'] as bool? ?? false,
    count: (j['count'] as num?)?.toInt() ?? 20,
    showString: j['showString'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'strings': strings.name,
    'frets': frets.name,
    'naturalsOnly': naturalsOnly,
    'count': count,
    'showString': showString,
  };
}

class TrainerLastResult {
  TrainerLastResult({required this.correct, required this.total, required this.averageSeconds, required this.kind});
  final int correct;
  final int total;
  final double averageSeconds;
  final TrainerKind kind;

  static TrainerLastResult? fromJson(Map<String, dynamic> j) {
    if (j['correct'] is! num || j['total'] is! num) return null;
    return TrainerLastResult(
      correct: (j['correct'] as num).toInt(),
      total: (j['total'] as num).toInt(),
      averageSeconds: (j['averageSeconds'] as num?)?.toDouble() ?? 0,
      kind: TrainerKind.values.where((k) => k.name == j['kind']).firstOrNull ?? TrainerKind.nameNote,
    );
  }

  Map<String, dynamic> toJson() => {'correct': correct, 'total': total, 'averageSeconds': averageSeconds, 'kind': kind.name};
}

/// `FretTrainer.Question`.
@immutable
class TrainerQuestion {
  const TrainerQuestion({required this.course, required this.fret, required this.pitchClass, required this.cents, this.fullName = ''});
  final int course;
  final int fret;
  final int pitchClass;
  final double cents;

  /// With the octave («D3»): the «Верно · D3» card.
  final String fullName;

  static TrainerQuestion? fromJson(Object? j) {
    if (j is! Map) return null;
    return TrainerQuestion(
      course: (j['course'] as num).toInt(),
      fret: (j['fret'] as num).toInt(),
      pitchClass: (j['pitchClass'] as num).toInt(),
      cents: (j['cents'] as num).toDouble(),
      fullName: j['fullName'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrainerQuestion && other.course == course && other.fret == fret && other.pitchClass == pitchClass;

  @override
  int get hashCode => Object.hash(course, fret, pitchClass);
}

/// `FretTrainer.Summary`.
class TrainerSummary {
  TrainerSummary.fromJson(Map<String, dynamic> j)
    : correct = (j['correct'] as num).toInt(),
      total = (j['total'] as num).toInt(),
      averageSeconds = (j['averageSeconds'] as num).toDouble(),
      bestStreak = (j['bestStreak'] as num).toInt(),
      weakCourses = [for (final c in j['weakCourses'] as List) (c as num).toInt()],
      missedPitchClasses = [for (final c in j['missedPitchClasses'] as List) (c as num).toInt()];

  final int correct;
  final int total;
  final double averageSeconds;
  final int bestStreak;
  final List<int> weakCourses;
  final List<int> missedPitchClasses;
}

/// The core's `FretTrainer` as the bridge reports it after every step.
class TrainerSession {
  TrainerSession.fromJson(Map<String, dynamic> j)
    : kind = TrainerKind.values.where((k) => k.name == j['kind']).firstOrNull ?? TrainerKind.nameNote,
      count = (j['count'] as num).toInt(),
      naturalsOnly = j['naturalsOnly'] as bool? ?? false,
      answered = (j['answered'] as num).toInt(),
      correct = (j['correct'] as num).toInt(),
      isFinished = j['isFinished'] as bool? ?? false,
      current = TrainerQuestion.fromJson(j['current']),
      frets = j['frets'] is List ? [for (final f in j['frets'] as List) (f as num).toInt()] : const [0, 12],
      summary = TrainerSummary.fromJson(Map<String, dynamic>.from(j['summary'] as Map));

  final TrainerKind kind;

  /// `options.count`, `options.naturalsOnly`.
  final int count;
  final bool naturalsOnly;

  /// `answers.count`, right answers.
  final int answered;
  final int correct;
  final bool isFinished;
  final TrainerQuestion? current;

  /// `options.frets` as [low, high].
  final List<int> frets;
  final TrainerSummary summary;
}

/// What the summary screen shows (the series' summary or the screenshot example).
class TrainerSummaryInfo {
  const TrainerSummaryInfo({
    required this.correct,
    required this.total,
    required this.averageSeconds,
    required this.bestStreak,
    required this.weakCourses,
    required this.missedPitchClasses,
    required this.kind,
    required this.frets,
  });
  final int correct;
  final int total;
  final double averageSeconds;
  final int bestStreak;
  final List<int> weakCourses;
  final List<int> missedPitchClasses;
  final TrainerKind kind;
  final List<int> frets;
}

class FretTrainerController extends ChangeNotifier {
  late AppModel app;

  static const _settingsKey = 'trainer.settings';
  static const _lastKey = 'trainer.last';

  TrainerSettings? _settings;
  TrainerSettings get settings => _settings ??= _load(_settingsKey, TrainerSettings.fromJson) ?? TrainerSettings();
  set settings(TrainerSettings value) {
    _settings = value;
    app.store.setString(_settingsKey, jsonEncode(value.toJson()));
    notifyListeners();
  }

  void updateSettings(void Function(TrainerSettings s) change) {
    final s = settings.copy();
    change(s);
    settings = s;
  }

  bool _lastLoaded = false;
  TrainerLastResult? _lastResult;
  TrainerLastResult? get lastResult {
    if (!_lastLoaded) {
      _lastLoaded = true;
      _lastResult = _load(_lastKey, TrainerLastResult.fromJson);
    }
    return _lastResult;
  }

  T? _load<T>(String key, T? Function(Map<String, dynamic>) decode) {
    final raw = app.store.getString(key);
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  TrainerSession? _session;
  TrainerSession? get session => _session;
  TrainerFeedback _feedback = TrainerFeedback.none;
  TrainerFeedback get feedback => _feedback;
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  /// «Слышу F♯» while playing.
  int? _heard;
  int? get heard => _heard;

  /// Seconds the last answer took (the «Верно» card: «0,8 с»).
  double _answerSeconds = 0;
  double get answerSeconds => _answerSeconds;

  /// «Подсказка» in «Сыграй ноту»: the asked cell is shown.
  bool _hintShown = false;
  bool get hintShown => _hintShown;

  /// The canvas summary (`-trainerSummary`).
  TrainerSummaryInfo? _demoSummary;

  TrainerSummaryInfo? get summaryInfo {
    if (_demoSummary != null) return _demoSummary;
    final s = _session;
    if (s == null || !s.isFinished) return null;
    final sum = s.summary;
    return TrainerSummaryInfo(
      correct: sum.correct,
      total: sum.total,
      averageSeconds: sum.averageSeconds,
      bestStreak: sum.bestStreak,
      weakCourses: sum.weakCourses,
      missedPitchClasses: sum.missedPitchClasses,
      kind: s.kind,
      frets: s.frets,
    );
  }

  /// Open-string names of the tuning without the octave («F♯»), by course.
  List<String> openNames() {
    final r = _call('practice.openNames');
    return r is Map ? [for (final n in r['names'] as List) n as String] : const [];
  }

  /// The question on screen: stays while the answer's feedback shows (the session has moved on by then).
  TrainerQuestion? _question;
  TrainerQuestion? get question => _question;
  bool get isFinished => _session?.isFinished ?? false;

  DateTime _askedAt = DateTime.now();
  DateTime _listenFrom = DateTime.now();
  int? _stableClass;
  int _stableCount = 0;
  Timer? _advance;
  bool _listening = false;

  /// Seed of the next series (screenshots: a fixed first question); null — random.
  @visibleForTesting
  static int? debugSeed;

  /// The cover opens the trainer while the tree builds (`FullScreenCover.initState` / `didUpdateWidget`):
  /// listeners hear about it after the frame.
  @override
  void notifyListeners() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => super.notifyListeners());
    } else {
      super.notifyListeners();
    }
  }

  // MARK: Open / close

  void open() {
    _isOpen = true;
    newSeries();
    // After the frame: the hooks answer, and the journal notifies its listeners (not during the cover's build).
    if (!_debugApplied) SchedulerBinding.instance.addPostFrameCallback((_) => _applyDebugArguments());
  }

  void close() {
    _advance?.cancel();
    _isOpen = false;
    _session = null;
    _question = null;
    _demoSummary = null;
    _feedback = TrainerFeedback.none;
    _call('practice.trainerEnd');
    _updateListening();
    notifyListeners();
  }

  void newSeries() => _newSeries(null);

  /// «Повторить ошибки»: a series of the missed notes only.
  void repeatMistakes() {
    final missed = summaryInfo?.missedPitchClasses;
    if (missed == null || missed.isEmpty) return;
    _newSeries(missed);
  }

  Map<String, dynamic> _options() {
    final n = app.courseCount;
    final List<int> courses = switch (settings.strings) {
      TrainerStrings.all => [],
      TrainerStrings.low => [for (var c = 0; c < (n < 3 ? n : 3); c++) c],
      TrainerStrings.high => [for (var c = n - 3 < 0 ? 0 : n - 3; c < n; c++) c],
    };
    final top = (app.instrument['fretCount'] as num?)?.toInt() ?? 24;
    final twelve = top < 12 ? top : 12;
    final frets = switch (settings.frets) {
      TrainerFrets.first12 => [0, twelve],
      TrainerFrets.whole => [0, top],
      TrainerFrets.upper => [twelve, top],
    };
    return {'kind': settings.kind.name, 'courses': courses, 'frets': frets, 'naturalsOnly': settings.naturalsOnly, 'count': settings.count};
  }

  void _newSeries(List<int>? pitchClasses) {
    _advance?.cancel();
    _demoSummary = null;
    final state = _call('practice.trainerStart', {..._options(), 'seed': ?debugSeed, 'pitchClasses': ?pitchClasses});
    if (state is! Map) return;
    _session = TrainerSession.fromJson(Map<String, dynamic>.from(state));
    _feedback = TrainerFeedback.none;
    _ask();
    _updateListening();
    notifyListeners();
  }

  void _ask() {
    final state = _call('practice.trainerNext');
    if (state is Map) _session = TrainerSession.fromJson(Map<String, dynamic>.from(state));
    _question = _session?.current;
    _askedAt = DateTime.now();
    // A ringing previous note must not answer the new question.
    _listenFrom = DateTime.now().add(const Duration(milliseconds: 450));
    _stableClass = null;
    _stableCount = 0;
    _heard = null;
    _hintShown = false;
    if (_session?.isFinished == true) _finish();
  }

  /// The tuner listens while «Сыграй ноту» is open (chromatic: any note gives a reading); the previous tuner
  /// mode comes back afterwards.
  void _updateListening() {
    final needs = needsMicrophone;
    final tuner = app.tuner;
    if (needs) {
      app.fretboard.stopDrone(); // 6.1 п. 5: no drone through the speaker while notes are checked
      _modeBefore ??= tuner.mode;
      if (!_listening) {
        _listening = true;
        tuner.readingListeners.add(_onReading);
      }
    } else {
      if (_listening) {
        _listening = false;
        tuner.readingListeners.remove(_onReading);
      }
    }
    // Deferred: the cover opens the trainer while the tree builds, and the tuner notifies the app model.
    scheduleMicrotask(() {
      if (needs) {
        if (tuner.mode != TunerMode.chromatic) tuner.mode = TunerMode.chromatic;
      } else if (_modeBefore != null) {
        tuner.mode = _modeBefore!;
        _modeBefore = null;
      }
      app.updateListening();
    });
  }

  TunerMode? _modeBefore;

  bool get needsMicrophone => _isOpen && settings.kind == TrainerKind.playNote && !isFinished;

  void _onReading(TunerReading reading) => hear(cents: reading.pitch.cents, provisional: reading.isProvisional);

  // MARK: Answers

  void answer(int pitchClass) {
    final s = _session, q = s?.current;
    if (s == null || q == null || !_feedback.isNone) return;
    final seconds = DateTime.now().difference(_askedAt).inMilliseconds / 1000;
    _question = q;
    final result = _call('practice.trainerAnswer', {'pitchClass': pitchClass, 'seconds': seconds});
    if (result is! Map) return;
    final ok = result['correct'] == true;
    _session = TrainerSession.fromJson(Map<String, dynamic>.from(result['state'] as Map));
    _answerSeconds = seconds;
    app.practice.activity(tuned: false);
    _feedback = ok ? TrainerFeedback.correct : TrainerFeedback.wrong(expected: q.pitchClass, heard: pitchClass);
    // Canvas: right — on by itself in a second; wrong — by «Дальше», to have time to read why.
    _advance?.cancel();
    if (ok && !holdFeedback) _advance = Timer(const Duration(seconds: 1), next);
    notifyListeners();
  }

  /// «Дальше» after a wrong answer (and the end of a right one).
  void next() {
    _advance?.cancel();
    if (_feedback.isNone) return;
    _feedback = TrainerFeedback.none;
    _ask();
    notifyListeners();
  }

  void showHint() {
    _hintShown = true;
    notifyListeners();
  }

  void skip() {
    final s = _session, q = s?.current;
    if (s == null || q == null || !_feedback.isNone) return;
    final state = _call('practice.trainerSkip', {'seconds': DateTime.now().difference(_askedAt).inMilliseconds / 1000});
    if (state is Map) _session = TrainerSession.fromJson(Map<String, dynamic>.from(state));
    _feedback = TrainerFeedback.wrong(expected: q.pitchClass);
    _advance?.cancel();
    notifyListeners();
  }

  // MARK: Screenshot hooks

  /// Keeps the «Верно» state on screen (screenshots).
  static bool holdFeedback = false;
  bool _debugApplied = false;

  /// Launch arguments of the trainer boards, once (FretTrainerController.swift): `-trainerAsk course:fret` (that
  /// question after `-trainerPrior N` right answers), `-trainerRight` (answered right in 0.8 s), `-trainerWrong pc`
  /// (answered with that pitch class), `-trainerSummary` (the canvas summary).
  void _applyDebugArguments() {
    if (_debugApplied) return;
    _debugApplied = true;
    final args = app.args;
    if (args.has('-trainerSummary')) {
      _demoSummary = TrainerSummaryInfo(
        correct: 1,
        total: 20,
        averageSeconds: 1.9,
        bestStreak: 1,
        weakCourses: [app.courseCount - 2 < 0 ? 0 : app.courseCount - 2],
        missedPitchClasses: const [1, 11, 4, 5, 6, 7, 8],
        kind: TrainerKind.nameNote,
        frets: const [6, 10],
      );
      _updateListening();
      notifyListeners();
      return;
    }
    final ask = args.value('-trainerAsk')?.split(':').map(int.tryParse).toList();
    if (ask == null || ask.length != 2 || ask.contains(null)) return;
    final prior = args.intValue('-trainerPrior') ?? 0;
    final found = _call('practice.trainerFindSeed', {..._options(), 'course': ask[0], 'fret': ask[1], 'prior': prior});
    final seed = found is Map ? (found['seed'] as num?)?.toInt() : null;
    if (seed == null) return;
    final state = _call('practice.trainerStart', {..._options(), 'seed': seed});
    if (state is! Map) return;
    _session = TrainerSession.fromJson(Map<String, dynamic>.from(state));
    for (var i = 0; i < prior; i++) {
      final s = _call('practice.trainerNext');
      final q = s is Map ? TrainerQuestion.fromJson(s['current']) : null;
      if (q == null) break;
      _call('practice.trainerAnswer', {'pitchClass': q.pitchClass, 'seconds': 1.2});
    }
    _feedback = TrainerFeedback.none;
    _ask();
    // A screenshot: the microphone hears the room, the board shows «Слушаю…».
    _listenFrom = DateTime(9999);
    final q = _question;
    if (args.has('-trainerRight') && q != null) {
      holdFeedback = true;
      _askedAt = DateTime.now().subtract(const Duration(milliseconds: 800));
      answer(q.pitchClass);
      _answerSeconds = 0.8;
    } else if (args.intValue('-trainerWrong') != null) {
      answer(args.intValue('-trainerWrong')!);
    }
    notifyListeners();
  }

  /// «Сыграй ноту»: three steady readings of one pitch class decide; a wrong note is named first and counts only
  /// if it stays (a slide or a neighbour string rings briefly).
  void hear({required double cents, bool provisional = false}) {
    final q = _question;
    if (!_isOpen ||
        settings.kind != TrainerKind.playNote ||
        !_feedback.isNone ||
        q == null ||
        DateTime.now().isBefore(_listenFrom) ||
        provisional) {
      return;
    }
    final pc = ((69 + cents / 100).round() % 12 + 12) % 12;
    if (pc == _stableClass) {
      _stableCount += 1;
    } else {
      _stableClass = pc;
      _stableCount = 1;
    }
    final changed = _heard != pc;
    _heard = pc;
    if (pc == q.pitchClass && _stableCount >= 3) {
      answer(pc);
    } else if (pc != q.pitchClass && _stableCount >= 16) {
      // 0.4 s: a slide or a neighbour string is not a mistake
      answer(pc);
    } else if (changed) {
      notifyListeners();
    }
  }

  void _finish() {
    final s = _session;
    if (s == null) return;
    final sum = s.summary;
    final result = TrainerLastResult(correct: sum.correct, total: sum.total, averageSeconds: sum.averageSeconds, kind: s.kind);
    _lastResult = result;
    _lastLoaded = true;
    app.store.setString(_lastKey, jsonEncode(result.toJson()));
    _updateListening();
  }

  // MARK: Note names

  List<String>? _sharps, _flats;

  /// `formatter.string(NoteName.simpleSpelling(ofPitchClass:, preferFlats: false))` in the app's notation.
  String name(int pc) => _names()[0][pc % 12];

  /// The same with flats (small label under a black-key button).
  String flatName(int pc) => _names()[1][pc % 12];

  String _notationKey = '';
  List<List<String>> _names() {
    final key = app.settings.notation;
    if (_sharps == null || key != _notationKey) {
      _notationKey = key;
      final r = _call('practice.noteNames');
      if (r is Map) {
        _sharps = [for (final s in r['sharps'] as List) s as String];
        _flats = [for (final s in r['flats'] as List) s as String];
      } else {
        _sharps = const ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
        _flats = const ['C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B'];
      }
    }
    return [_sharps!, _flats!];
  }

  dynamic _call(String method, [Map<String, dynamic>? params]) {
    try {
      return app.core?.call(method, params);
    } catch (e) {
      debugPrint('$method: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _advance?.cancel();
    if (_listening) app.tuner.readingListeners.remove(_onReading);
    super.dispose();
  }
}

/// Port of Truver/Sources/Features/Practice/PracticeSessionController.swift
///
/// PL-2 «Занятие»: runs the plan — the exercise with its timer, the pause with a spoken prompt, the summary.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../metronome/play_check_controller.dart';
import 'practice_links.dart';

/// PL-1 exercise: a metronome preset (or the current settings), how long, with the play check or on the neck.
class PracticeStep {
  PracticeStep({String? id, this.presetId, this.minutes = 5, this.check = true, this.onNeck = false}) : id = id ?? newUuid();

  String id;

  /// Metronome preset; null — the settings that are on the metronome when the step starts.
  String? presetId;
  int minutes;

  /// Stage SM «Проверка игры» on the metronome.
  bool check;

  /// FB-14: the current scale position on the neck, played and checked note by note.
  bool onNeck;

  PracticeStep copy({String? id}) => PracticeStep(id: id ?? this.id, presetId: presetId, minutes: minutes, check: check, onNeck: onNeck);

  factory PracticeStep.fromJson(Map<String, dynamic> j) => PracticeStep(
    id: j['id'] as String?,
    presetId: j['presetId'] as String?,
    minutes: (j['minutes'] as num?)?.toInt() ?? 5,
    check: j['check'] as bool? ?? true,
    onNeck: j['onNeck'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {'id': id, 'presetId': ?presetId, 'minutes': minutes, 'check': check, 'onNeck': onNeck};
}

/// PL-2 plan: exercises in order, a pause between them, voice prompts.
class PracticePlan {
  PracticePlan({List<PracticeStep>? steps, this.pauseSeconds = 20, this.voice = true}) : steps = steps ?? [PracticeStep()];

  List<PracticeStep> steps;
  int pauseSeconds;
  bool voice;

  PracticePlan copy() => PracticePlan(steps: [for (final s in steps) s.copy()], pauseSeconds: pauseSeconds, voice: voice);

  factory PracticePlan.fromJson(Map<String, dynamic> j) => PracticePlan(
    steps: [for (final s in (j['steps'] as List? ?? const [])) PracticeStep.fromJson(Map<String, dynamic>.from(s as Map))],
    pauseSeconds: (j['pauseSeconds'] as num?)?.toInt() ?? 20,
    voice: j['voice'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'steps': [for (final s in steps) s.toJson()],
    'pauseSeconds': pauseSeconds,
    'voice': voice,
  };
}

enum SessionPhase { idle, playing, pause, done }

class StepResult {
  StepResult({required this.title, required this.seconds, this.attempt}) : id = newUuid();
  final String id;
  final String title;
  final double seconds;
  final PlayAttempt? attempt;
}

class PracticeSessionController extends ChangeNotifier {
  late AppModel app;

  static const _planKey = 'practice.plan';

  PracticePlan? _plan;

  PracticePlan get plan => _plan ??= _loadPlan();

  /// Replaces the plan (saved, as iOS `didSet`).
  set plan(PracticePlan value) {
    _plan = value;
    app.store.setString(_planKey, jsonEncode(value.toJson()));
    notifyListeners();
  }

  /// Mutates a copy of the plan and stores it.
  void updatePlan(void Function(PracticePlan p) change) {
    final p = plan.copy();
    change(p);
    plan = p;
  }

  PracticePlan _loadPlan() {
    final raw = app.store.getString(_planKey);
    if (raw == null) return PracticePlan();
    try {
      return PracticePlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return PracticePlan();
    }
  }

  SessionPhase _phase = SessionPhase.idle;
  SessionPhase get phase => _phase;
  int _stepIndex = 0;
  int get stepIndex => _stepIndex;
  double _remaining = 0;
  double get remaining => _remaining;
  List<StepResult> _results = [];
  List<StepResult> get results => _results;

  /// Length of the running phase (the exercise or the pause), s — the ring's full circle.
  double _phaseLength = 0;
  double get phaseLength => _phaseLength;

  /// The big «Пауза» button of the running screen: the timer and the metronome hold.
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// Screenshot value of the play-check chip (the simulator hears no playing).
  double? _demoShare;
  double? get demoShare => _demoShare;

  /// While a session runs the play check's own summary sheet does not pop up between steps.
  bool get isRunning => _phase == SessionPhase.playing || _phase == SessionPhase.pause;

  Timer? _timer;
  DateTime _stepStart = DateTime.now();

  String title(PracticeStep step) {
    final preset = step.presetId == null ? null : PracticeLinks.presets(app).where((p) => p.id == step.presetId).firstOrNull;
    final base = preset?.name ?? 'Текущие настройки';
    return step.onNeck ? '$base · ${PracticeLinks.scaleTitle(app)}' : base;
  }

  PracticeStep? get currentStep => _stepIndex >= 0 && _stepIndex < plan.steps.length ? plan.steps[_stepIndex] : null;
  PracticeStep? get nextStep => _stepIndex + 1 < plan.steps.length ? plan.steps[_stepIndex + 1] : null;

  // MARK: Run

  void start() {
    if (plan.steps.isEmpty) return;
    _results = [];
    _stepIndex = 0;
    final first = plan.steps[0];
    _say('Начинаем. ${title(first)}, ${first.minutes} ${minutes(first.minutes)}.');
    _beginStep();
  }

  void stop() {
    _timer?.cancel();
    _isPaused = false;
    if (_phase == SessionPhase.playing) _endStep(advance: false);
    _phase = _results.isEmpty ? SessionPhase.idle : SessionPhase.done;
    notifyListeners();
  }

  void skip() {
    if (_phase != SessionPhase.playing && _phase != SessionPhase.pause) return;
    _timer?.cancel();
    _isPaused = false;
    if (_phase == SessionPhase.playing) {
      _endStep(advance: true);
    } else {
      _beginStep();
    }
    notifyListeners();
  }

  void reset() {
    _phase = SessionPhase.idle;
    _results = [];
    _isPaused = false;
    notifyListeners();
  }

  /// Holds the timer and the metronome; `resume` goes on from the same second.
  void pause() {
    if ((_phase != SessionPhase.playing && _phase != SessionPhase.pause) || _isPaused) return;
    _isPaused = true;
    _timer?.cancel();
    if (_phase == SessionPhase.playing && PracticeLinks.metronomeIsPlaying(app)) PracticeLinks.metronomeStop(app);
    notifyListeners();
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    if (_phase == SessionPhase.playing && currentStep?.onNeck == false && !PracticeLinks.metronomeIsPlaying(app)) {
      PracticeLinks.metronomeStart(app);
    }
    _runTimer();
    notifyListeners();
  }

  void togglePause() => _isPaused ? resume() : pause();

  /// «100 BPM · 4/4» of a step: its preset's tempo and meter, or the metronome's current ones.
  String tempoText(PracticeStep step) {
    final preset = step.presetId == null ? null : PracticeLinks.presets(app).where((p) => p.id == step.presetId).firstOrNull;
    final meter = preset?.settings ?? PracticeLinks.meter(app);
    return '${(meter['bpm'] as num).round()} BPM · ${meter['numerator']}/${meter['denominator']}';
  }

  /// Screenshot hook `-sessionRunning`: the plan starts and stands 3 s in (4:57 of 5:00), the timer held.
  void debugRunning() {
    updatePlan((p) => p.voice = false);
    start();
    _timer?.cancel();
    _remaining -= 3;
    _demoShare = 0.92;
    notifyListeners();
  }

  void _beginStep() {
    final step = currentStep;
    if (step == null) {
      _finish();
      return;
    }
    _phase = SessionPhase.playing;
    _isPaused = false;
    _stepStart = DateTime.now();
    _remaining = step.minutes * 60.0;
    _phaseLength = _remaining;
    final preset = step.presetId == null ? null : PracticeLinks.presets(app).where((p) => p.id == step.presetId).firstOrNull;
    if (preset != null) PracticeLinks.loadPreset(app, preset);
    if (step.onNeck) {
      PracticeLinks.startTraining(app);
    } else if (step.check) {
      final index = _stepIndex;
      () async {
        await PracticeLinks.playCheckEnable(app);
        // The step may have ended while the microphone was being opened.
        if (_phase != SessionPhase.playing || _stepIndex != index) return;
        if (!PracticeLinks.metronomeIsPlaying(app)) PracticeLinks.metronomeStart(app);
      }();
    } else if (!PracticeLinks.metronomeIsPlaying(app)) {
      PracticeLinks.metronomeStart(app);
    }
    _runTimer();
    notifyListeners();
  }

  void _runTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remaining -= 1;
      if (_remaining <= 0) {
        timer.cancel();
        if (_phase == SessionPhase.playing) {
          _endStep(advance: true);
        } else {
          _beginStep();
        }
      }
      notifyListeners();
    });
  }

  void _endStep({required bool advance}) {
    final step = currentStep;
    if (step == null) return;
    if (step.onNeck) {
      PracticeLinks.stopTraining(app);
    } else {
      PracticeLinks.metronomeStop(app);
      if (PracticeLinks.playCheckIsOn(app)) PracticeLinks.playCheckDisable(app);
    }
    final summary = PracticeLinks.playCheckSummary(app);
    final attempt = summary != null && !summary.date.isBefore(_stepStart) ? summary : null;
    _results = [
      ..._results,
      StepResult(title: title(step), seconds: DateTime.now().difference(_stepStart).inMilliseconds / 1000, attempt: attempt),
    ];
    if (app.sheet == const AppSheet('playCheckSummary')) app.sheet = null;
    if (!advance) return;
    _stepIndex += 1;
    final next = currentStep;
    if (next == null) {
      _finish();
      return;
    }
    _phase = SessionPhase.pause;
    _remaining = plan.pauseSeconds.toDouble();
    _phaseLength = _remaining;
    _say('Пауза ${plan.pauseSeconds} секунд. Дальше — ${title(next)}, ${next.minutes} ${minutes(next.minutes)}.');
    if (plan.pauseSeconds <= 0) {
      _beginStep();
    } else {
      _runTimer();
    }
  }

  void _finish() {
    _timer?.cancel();
    _phase = SessionPhase.done;
    _say('Занятие закончено.');
    notifyListeners();
  }

  void _say(String text) {
    if (!plan.voice) return;
    // TODO(android): TextToSpeech (ru-RU, rate ≈ 0.52 of AVSpeech) — iOS speaks `text` with AVSpeechSynthesizer,
    // stopping the previous prompt first.
    debugPrint('session: $text');
  }

  static String minutes(int n) => plural(n, 'минута', 'минуты', 'минут');

  /// `ModeParamsSheet.plural`: Russian plural forms.
  static String plural(int n, String one, String few, String many) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return one;
    if (n10 >= 2 && n10 <= 4 && !(n100 >= 12 && n100 <= 14)) return few;
    return many;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

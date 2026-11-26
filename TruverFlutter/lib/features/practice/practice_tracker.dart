/// Port of Truver/Sources/Features/Practice/PracticeTracker.swift
///
/// Simple v1 journal (PL-0). Time counts while the metronome plays or the tuner hears a note; pieces with a gap
/// under 5 minutes join into one session; background metronome time counts (6.1 п. 12).
/// Storage: `PracticeJournal` (lib/app/storage.dart) — iOS keeps the same entries in SwiftData.
library;

import 'package:flutter/foundation.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../metronome/play_check_controller.dart';

class PracticeTracker extends ChangeNotifier {
  late AppModel _app;
  AppModel get app => _app;

  /// The tuner reports heard notes and tuned strings to its activity listeners (the metronome and the trainer
  /// call [activity] themselves). `AppModel` creates the tuner before the tracker.
  set app(AppModel value) {
    _app = value;
    value.tuner.activityListeners.add((tuned) => activity(tuned: tuned));
    if (value.args.has('-practiceDemo') || value.args.has('-practiceEmpty')) {
      _entries = [];
      _demoHistory = [];
    }
    if (value.args.has('-practiceDemo')) _seedDemo();
  }

  /// Screenshot demo of the play check's history (`-practiceDemo`: 14 days, ceiling 128 → 146, spread 8 ms;
  /// `-practiceEmpty`: none) — shown instead of the controller's.
  List<PlayAttempt>? _demoHistory;
  List<PlayAttempt>? get demoHistory => _demoHistory;

  /// The board «Занятия — графики»: 14 days in a row, 2 h 10 min over the last week, the ceiling 128 → 146.
  void _seedDemo() {
    final t = DateTime.now();
    const minutes = [20, 15, 25, 20, 15, 20, 15, 15, 20, 15, 20, 15, 20, 15];
    const ceilings = <double>[128, 129, 131, 132, 133, 135, 136, 137, 139, 140, 141, 143, 144, 146];
    final history = <PlayAttempt>[];
    for (var k = 0; k < 14; k++) {
      final start = t.subtract(Duration(days: k, hours: 1));
      final i = 13 - k;
      _entries!.add(
        PracticeEntry(start: start, instrumentName: '8-струнная гитара', tuningName: 'Стандарт F♯')
          ..seconds = minutes[k] * 60.0
          ..usedMetronome = true
          ..presetName = 'Риф 7/8'
          ..lastBPM = ceilings[i]
          ..minBPM = ceilings[i] - 8,
      );
      history.add(
        PlayAttempt(
          date: start,
          preset: 'Риф 7/8',
          seconds: minutes[k] * 60.0,
          startBPM: 120,
          endBPM: ceilings[i],
          ceiling: ceilings[i],
          accurateShare: 0.8,
          meanDeviation: -5,
          spread: 14 - i * 6 / 13,
          weakestBeat: 3,
          weakestBeatDeviation: -12,
          bars: 40,
          perBeat: {0: -2, 1: 4, 2: -6, 3: -13},
        ),
      );
    }
    _demoHistory = history.reversed.toList();
  }

  static const joinGap = Duration(minutes: 5);

  List<PracticeEntry>? _entries;
  PracticeEntry? _current;
  DateTime? _lastActivity;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// All journal entries (iOS `@Query` over `PracticeEntry`), loaded on first use.
  List<PracticeEntry> get entries => _entries ??= PracticeJournal.load(app.store);

  /// Clock of the tracker (tests and demos may move it).
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// Called by the metronome (with the tempo), the tuner (a heard note, `tuned` when a string reached ±3 c) and
  /// the fret trainer (an answer).
  void activity({required bool tuned, double? bpm}) {
    final t = now();
    final instrumentName = app.instrument['name'] as String? ?? '';
    final last = _lastActivity, entry = _current;
    if (last != null && entry != null && t.difference(last) < joinGap && entry.instrumentName == instrumentName) {
      // Count at most 2 s per call so that sparse tuner readings do not inflate the time.
      final gap = t.difference(last).inMicroseconds / 1e6;
      entry.seconds += gap < 2 ? gap : 2;
    } else {
      final e = PracticeEntry(start: t, instrumentName: instrumentName, tuningName: app.tuningName);
      entries.add(e);
      _current = e;
    }
    _lastActivity = t;
    final current = _current!;
    if (bpm != null) {
      current.lastBPM = bpm;
      current.minBPM = current.usedMetronome && current.minBPM > 0 ? (current.minBPM < bpm ? current.minBPM : bpm) : bpm;
      current.usedMetronome = true;
      final preset = app.settings.metronome.currentPreset?.name;
      if (preset != null) current.presetName = preset;
    }
    if (tuned) current.tuned = true;
    current.tuningName = app.tuningName;
    if (t.difference(_lastSave).inSeconds > 10) {
      _save();
      _lastSave = t;
    }
    notifyListeners();
  }

  /// Writes the running session to the journal (app paused / closed).
  void flush() => _save();

  void _save() {
    if (_entries == null) return;
    PracticeJournal.save(app.store, _entries!);
  }
}

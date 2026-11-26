/// What the practice feature uses from the other features (metronome, play check, fretboard, tuner) — in one
/// place. iOS reads these members directly (`app.metronome.load`, `app.playCheck.history`,
/// `app.fretboard.scaleTitle`…).
library;

import '../../app/app_model.dart';
import '../../app/audio_services.dart';
import '../../app/storage.dart';
import '../metronome/play_check_controller.dart';

abstract final class PracticeLinks {
  // MARK: Play check

  /// `app.playCheck.history` — attempts for the PL-4 charts, oldest first.
  static List<PlayAttempt> playCheckHistory(AppModel app) => app.playCheck.history;

  /// `app.playCheck.summary` — the last finished attempt.
  static PlayAttempt? playCheckSummary(AppModel app) => app.playCheck.summary;

  static bool playCheckIsOn(AppModel app) => app.playCheck.isOn;

  static Future<void> playCheckEnable(AppModel app) => app.playCheck.enable();

  static void playCheckDisable(AppModel app) => app.playCheck.disable();

  // MARK: Metronome

  static List<MetronomePreset> presets(AppModel app) => app.settings.metronome.presets;

  static void loadPreset(AppModel app, MetronomePreset preset) => app.metronome.load(preset);

  static void setBPM(AppModel app, double bpm) => app.metronome.bpm = bpm;

  static bool metronomeIsPlaying(AppModel app) => app.metronome.isPlaying;

  static void metronomeStart(AppModel app) => app.metronome.start();

  static void metronomeStop(AppModel app) => app.metronome.stop();

  /// The tempo on screen (follows speed-up modes and the play check).
  static double displayBPM(AppModel app) => app.metronome.displayBPM;

  /// Core `MeterSettings` JSON of the metronome (bpm, numerator, denominator, accents).
  static Map<String, dynamic> meter(AppModel app) => app.metronome.meter;

  /// The beat that sounds now (the session's beat bars).
  static int? currentBeat(AppModel app) => app.metronome.currentBeat;

  /// Share of «точно + хорошо» in the last graded bar (the session's «Проверка · 92 %» chip).
  static double? playCheckShare(AppModel app) => app.playCheck.lastBar?.accurateShare;

  // MARK: Fretboard

  /// «Ми минор · позиция 1».
  static String scaleTitle(AppModel app) => app.fretboard.scaleTitle;

  /// FB-14 «Тренировать»: the current scale position, note by note.
  static void startTraining(AppModel app) => app.fretboard.startTraining();

  static void stopTraining(AppModel app) => app.fretboard.stopTraining();

  static bool leftHanded(AppModel app) => app.fretboard.settings.leftHanded;

  // MARK: Tuner

  static MicPermission micPermission(AppModel app) => app.tuner.permission;
}

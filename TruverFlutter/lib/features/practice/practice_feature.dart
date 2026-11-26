/// Registration of the practice feature in the app shell: the «Занятия» tab, the «Занятие» and «Тренажёр грифа»
/// covers and their debug arguments (AppModel.swift: `-sheet session|trainerName|trainerPlay`,
/// `-playCheckHistoryDemo`).
library;

import '../../app/app_model.dart';
import '../../app/feature_registry.dart';
import '../../app/storage.dart';
import 'fret_trainer_controller.dart';
import 'fret_trainer_view.dart';
import 'practice_screen.dart';
import 'practice_session_view.dart';

void registerPractice() {
  FeatureRegistry.tabScreens[AppTab.practice] = (context) => const PracticeScreen();
  FeatureRegistry.session = (context) => const PracticeSessionView();
  FeatureRegistry.trainer = (context) => const FretTrainerView();

  FeatureRegistry.debugSheets['session'] = (app) => app.showSession = true;
  FeatureRegistry.debugSheets['trainerName'] = (app) => _openTrainer(app, TrainerKind.nameNote);
  FeatureRegistry.debugSheets['trainerPlay'] = (app) => _openTrainer(app, TrainerKind.playNote);
  // `-playCheckHistoryDemo` is the play check's own hook (metronome feature), as in iOS.
}

void _openTrainer(AppModel app, TrainerKind kind) {
  app.trainer.updateSettings((s) => s.kind = kind);
  app.showTrainer = true;
}

/// Registration of the tuner feature in the app shell: the tab screen, the landscape board, the intonation sheet
/// and the debug arguments `-tunerDemo <state>` (`-tunerStage` is read by `TunerScreen` itself, as iOS does
/// in `.onAppear`).
library;

import '../../app/feature_registry.dart';
import '../../app/storage.dart';
import 'intonation_sheet.dart';
import 'tuner_demo.dart';
import 'tuner_screen.dart';

void registerTuner() {
  FeatureRegistry.tabScreens[AppTab.tuner] = (context) => const TunerScreen();
  // The same widget picks the landscape board (canvas «Тюнер — альбом») when the phone is sideways.
  FeatureRegistry.landscapeScreens[AppTab.tuner] = (context) => const TunerScreen();
  FeatureRegistry.sheets['intonation'] = (context, sheet) => const IntonationSheet();
  FeatureRegistry.sheets['tunerPro'] = (context, sheet) => const TunerProSheet();
  FeatureRegistry.debugHooks.add((app, args) {
    final demo = TunerDemo.named(args.value('-tunerDemo'));
    if (demo != null) app.tuner.demo = demo;
  });
}

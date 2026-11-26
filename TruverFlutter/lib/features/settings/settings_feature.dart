/// Registration of the settings feature in the app shell: the full-screen settings cover (the gear; `-showSettings`,
/// `-settingsPage noise|target|notation|a4|input|output|volume|about` are read by `AppModel` / `SettingsView`), the
/// saved noise threshold and the rate prompt (`SettingsHooks`, `-ratePrompt`).
library;

import '../../app/feature_registry.dart';
import 'rate_prompt.dart';
import 'settings_view.dart';

void registerSettings() {
  FeatureRegistry.settings = (context) => const SettingsView();
  FeatureRegistry.debugHooks.add((app, args) => SettingsHooks.start(app));
}

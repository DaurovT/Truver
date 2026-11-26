/// How features plug into the app shell without editing it: tab screens, sheets, full-screen covers and debug
/// launch arguments. Each feature fills its own `lib/features/<feature>/<feature>_feature.dart`
/// (`registerTuner()`…), called once at start by [registerFeatures].
library;

import 'package:flutter/widgets.dart';

import '../features/fretboard/fretboard_feature.dart';
import '../features/instrument/instrument_feature.dart';
import '../features/metronome/metronome_feature.dart';
import '../features/practice/practice_feature.dart';
import '../features/settings/settings_feature.dart';
import '../features/thanks/thanks_feature.dart';
import '../features/tour/tour_feature.dart';
import '../features/tuner/tuner_feature.dart';
import 'app_model.dart';
import 'debug_args.dart';
import 'storage.dart';

typedef SheetBuilder = Widget Function(BuildContext context, AppSheet sheet);

abstract final class FeatureRegistry {
  /// The screen of a tab (inside the shell: safe area above the tuning pill and the tab bar). Missing — an empty
  /// placeholder with the tab's header.
  static final tabScreens = <AppTab, WidgetBuilder>{};

  /// Sheet contents by `AppSheet.kind` — usually a `DesignSheet`. The host adds the dim and the slide-in.
  static final sheets = <String, SheetBuilder>{};

  /// `-sheet <name>` launch arguments whose sheet needs more than `AppSheet(name)` (an argument, demo data).
  /// Without an entry, `-sheet X` opens `AppSheet('X')` when a builder for `X` is registered.
  static final debugSheets = <String, void Function(AppModel app)>{};

  /// Called at the end of `AppModel`'s construction with the launch arguments (`-tunerDemo`, `-metroDemo`…).
  static final debugHooks = <void Function(AppModel app, DebugArgs args)>[];

  /// Full-screen covers: settings (gear), practice session, fret trainer.
  static WidgetBuilder? settings;
  static WidgetBuilder? session;
  static WidgetBuilder? trainer;

  /// Tabs whose screen sometimes covers the tab bar too (the fretboard's «Таб», canvas S6Tab).
  static final hidesTabBar = <AppTab, bool Function(AppModel app)>{};

  /// Landscape boards per tab (canvas «— альбом»); missing — the portrait screen stays.
  static final landscapeScreens = <AppTab, WidgetBuilder>{};

  /// Layers over the whole shell (update notices of «Спасибо · обновления»).
  static final overlays = <WidgetBuilder>[];

  static bool _registered = false;

  static void reset() {
    tabScreens.clear();
    sheets.clear();
    debugSheets.clear();
    debugHooks.clear();
    landscapeScreens.clear();
    overlays.clear();
    hidesTabBar.clear();
    settings = session = trainer = null;
    _registered = false;
  }
}

/// Registers every feature once.
void registerFeatures() {
  if (FeatureRegistry._registered) return;
  FeatureRegistry._registered = true;
  registerTuner();
  registerMetronome();
  registerFretboard();
  registerInstrument();
  registerPractice();
  registerSettings();
  registerThanks();
  registerTour();
}

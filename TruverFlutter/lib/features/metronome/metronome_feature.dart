/// Registration of the metronome feature in the app shell (screens, sheets, debug arguments) — the metronome part
/// of `RootView.swift` (sheet switch) and `AppModel.swift` (screenshot hooks).
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/debug_args.dart';
import '../../app/feature_registry.dart';
import '../../app/storage.dart';
import 'metronome_screen.dart';
import 'metronome_sheets.dart';
import 'metronome_controller.dart';
import 'play_check_views.dart';
import 'rhythm_library.dart';
import 'rhythm_views.dart';

void registerMetronome() {
  FeatureRegistry.tabScreens[AppTab.metronome] = (context) => const MetronomeScreen();
  FeatureRegistry.landscapeScreens[AppTab.metronome] = (context) => const MetronomeScreen(landscape: true);

  final sheets = FeatureRegistry.sheets;
  sheets['metroMeter'] = (context, _) => const MeterSheet();
  sheets['metroRhythm'] = (context, _) => const RhythmSheet();
  sheets['metroRhythmBeat'] = (context, sheet) => RhythmSheet(beat: sheet.arg as int?);
  sheets['metroModes'] = (context, _) => const ModesSheet();
  sheets['metroModeParams'] = (context, sheet) => ModeParamsSheet(kind: sheet.arg as String? ?? 'speedUp');
  sheets['metroPresets'] = (context, _) => const PresetsSheet();
  sheets['metroSounds'] = (context, _) => const SoundsSheet();
  sheets['metroTimer'] = (context, _) => const TimerSheet();
  sheets['playCheck'] = (context, _) => const PlayCheckSheet();
  sheets['playCheckSummary'] = (context, _) => const PlayCheckSummarySheet();

  // `-sheet …` arguments of AppModel.swift that open a sheet with an argument or demo data.
  final debug = FeatureRegistry.debugSheets;
  debug['metroParams'] = (app) => app.sheet = const AppSheet('metroModeParams', 'speedUp');
  debug['metroFastSlow'] = (app) => app.sheet = const AppSheet('metroModeParams', 'fastSlow');
  debug['metroSong'] = (app) => app.sheet = const AppSheet('metroModeParams', 'songMap');
  debug['metroRandomMute'] = (app) => app.sheet = const AppSheet('metroModeParams', 'randomMute');
  debug['playCheckSummary'] = (app) {
    app.playCheck.injectDemo();
    app.sheet = const AppSheet('playCheckSummary');
  };

  FeatureRegistry.debugHooks.add(_debugHook);
}

/// Screenshot hooks: `-metroDemo` (preset, mode, timer for the canvas states), `-beatFigures`, `-metroPlay`,
/// `-playCheckHistoryDemo`.
void _debugHook(AppModel app, DebugArgs args) {
  // Canvas boards (7/8 «Риф 7/8» at 142): `-metroDemo` — the meter and four presets; `-metroNoPresets`;
  // `-metroMode speedUp|gapBars|randomMute|songMap|…`; `-metroBeat N` — beat N stays lit;
  // `-metroPose playing|target|interrupted|timerEnd|landscape`; `-metroSwipe N` — preset row N open.
  if (args.has('-metroDemo')) {
    app.updateSettings((settings) {
      final s = settings.metronome;
      final meter = <String, dynamic>{
        'bpm': 142.0,
        'numerator': 7,
        'denominator': 8,
        'grouping': [2, 2, 3],
        // The canvas boards draw beats 1 and 3 strong, the rest normal.
        'accents': [Accent.strong, Accent.normal, Accent.strong, Accent.normal, Accent.normal, Accent.normal, Accent.normal],
        'subdivision': 1,
        'swing': 0.5,
      };
      s.meter = meter;
      s.modes = MetronomeModes()
        ..start = 142
        ..target = 160
        ..step = 2
        ..every = 4;
      final riff = MetronomeModes.fromJson(s.modes.toJson())..tempo = ModeTempo.speedUp;
      final preset = MetronomePreset(name: 'Риф 7/8', settings: jsonCopy(meter), modes: riff);
      s.presets = [
        preset,
        MetronomePreset(name: 'Разминка', settings: _meter(app, 90, 4, 4, 2)),
        MetronomePreset(name: 'Баллада', settings: _meter(app, 64, 6, 8, 1)),
        MetronomePreset(name: 'Соло шестнадцатыми', settings: _meter(app, 180, 4, 4, 4)),
      ];
      s.currentPresetId = preset.id;
      s.timerEnabled = false;
      s.timerMinutes = 20;
      s.accentDB = 6;
      settings.vibration = true; // canvas «Звуки и выход»: «Вибрация на сильной доле» on
    });
  }
  if (args.has('-metroNoPresets')) app.updateSettings((s) => s.metronome.presets = []);
  final mode = args.value('-metroMode');
  if (mode != null) {
    final choice = ModeChoice.values.where((c) => c.name == mode).firstOrNull;
    if (choice != null) app.metronome.choose(choice);
  }
  final beat = int.tryParse(args.value('-metroBeat') ?? '');
  if (beat != null) app.metronome.debugLitBeat = beat - 1;
  final row = int.tryParse(args.value('-metroSwipe') ?? '');
  final presets = app.metronome.state.presets;
  if (row != null && row >= 1 && row <= presets.length) app.metronome.debugOpenPreset = presets[row - 1].id;
  final pose = args.value('-metroPose');
  if (pose != null) app.metronome.debugPose(pose);
  if (args.has('-playCheckHistoryDemo')) app.playCheck.injectHistoryDemo();
  if (args.has('-beatFigures')) {
    final m = app.metronome;
    for (final (id, beat) in const [('eighths', 0), ('triplets', 2), ('16:012', 3)]) {
      m.setBeatRhythm(RhythmLibrary.byId(id), beat);
    }
  }
  if (args.has('-metroPlay')) {
    // iOS waits a second for the audio session; the Android host is ready once the core is loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) => app.metronome.start());
  }
}

/// `MeterSettings(bpm:, numerator:, denominator:, subdivision:)`.
Map<String, dynamic> _meter(AppModel app, double bpm, int numerator, int denominator, int subdivision) => {
  'bpm': bpm,
  'numerator': numerator,
  'denominator': denominator,
  'accents': app.metronome.defaultAccents(numerator, null),
  'subdivision': subdivision,
  'swing': 0.5,
};

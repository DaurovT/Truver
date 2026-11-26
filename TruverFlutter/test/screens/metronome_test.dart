import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/app_model.dart';
import 'package:truver/app/test_app.dart';
import 'package:truver/app/storage.dart';
import 'package:truver/features/metronome/metronome_controller.dart';
import 'package:truver/features/metronome/metronome_sheets.dart';
import 'package:truver/features/metronome/rhythm_library.dart';
import 'package:truver/features/metronome/tempo_knob.dart';
import 'package:truver/features/root/root_view.dart';

import '../support/screen_harness.dart';

/// Metronome tab and its sheets against the canvas boards (renders of `<Board>.dc.html`, 1170 × 2532): the test name
/// is the board name, the arguments are the same on iOS (`AppModel.swift` → `MetronomeController.applyDebugArguments`).
const base = '-resetSettings -skipOnboarding -template g6-standard-e -muteAudio';

/// Board → arguments (7/8 «Риф 7/8» at 142, beat 3 lit as on the canvas).
const boards = {
  'MetroStopped': '-tab metronome -metroDemo -metroBeat 3',
  'FixMetroPlaying': '-tab metronome -metroDemo -metroMode speedUp -metroPose playing -metroBeat 1',
  'MetroTarget': '-tab metronome -metroDemo -metroMode speedUp -metroPose target -metroBeat 1',
  'MetroTimerEnd': '-tab metronome -metroDemo -metroBeat 3 -metroPose timerEnd',
  'MetroInterrupted': '-tab metronome -metroDemo -metroBeat 3 -metroPose interrupted',
  'MetroPresetSwipe': '-tab metronome -metroDemo -metroBeat 3 -sheet metroPresets -metroSwipe 2',
  'MetroSheetMeter': '-tab metronome -metroDemo -metroBeat 3 -sheet metroMeter',
  'MetroSheetModes': '-tab metronome -metroDemo -metroBeat 3 -metroMode speedUp -sheet metroModes',
  'MetroSheetPresets': '-tab metronome -metroDemo -metroBeat 3 -sheet metroPresets',
  'MetroSheetPresetsEmpty': '-tab metronome -metroDemo -metroNoPresets -metroBeat 3 -sheet metroPresets',
  'MetroSheetSounds': '-tab metronome -metroDemo -metroBeat 3 -sheet metroSounds',
  'FixMetroTimer': '-tab metronome -metroDemo -metroBeat 3 -sheet metroTimer',
  'FixMetroRandommute': '-tab metronome -metroDemo -metroBeat 3 -metroMode randomMute -sheet metroRandomMute',
  'FixMetroSongmap': '-tab metronome -metroDemo -metroBeat 3 -metroMode songMap -sheet metroSong',
  'FixMetroPlaycheck': '-tab metronome -metroDemo -metroBeat 3 -sheet playCheck',
};

/// Other states of the app that have no board (figures on beats, the rhythm sheet, the other mode sheets).
const states = {
  'metro_figures': '-tab metronome -beatFigures',
  'metro_params': '-tab metronome -metroDemo -metroMode speedUp -sheet metroParams',
  'metro_fastslow': '-tab metronome -sheet metroFastSlow',
  'metro_rhythm': '-tab metronome -sheet metroRhythm',
  'metro_playcheck_summary': '-tab metronome -sheet playCheckSummary',
};

void main() {
  // Screens first: the behaviour tests load the fonts outside `runAsync`, and a capture after them could wait forever.
  for (final e in {...boards, ...states}.entries) {
    testWidgets(e.key, (t) async {
      await ScreenHarness.capture(t, e.key, TruverTestApp(args: '$base ${e.value}'));
      // A playing metronome polls the audio host every frame: stop it so the test ends without frame callbacks.
      final app = AppScope.read(t.element(find.byType(RootView)));
      app.metronome
        ..stop()
        ..dismissSessionEnd()
        ..clearToast();
      await t.pump();
    });
  }
  testWidgets('MetroLargeText', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await ScreenHarness.capture(t, 'MetroLargeText', const TruverTestApp(args: '$base -tab metronome -metroDemo -metroMode speedUp'));
  });
  testWidgets('LandMetro', (t) async {
    await ScreenHarness.capture(
      t,
      'LandMetro',
      const TruverTestApp(args: '$base -tab metronome -metroDemo -metroMode speedUp -metroPose landscape -metroBeat 3'),
      landscape: true,
    );
    expect(find.byType(TempoKnob), findsOneWidget);
    AppScope.read(t.element(find.byType(RootView))).metronome.stop();
    await t.pump();
  });
  behaviour();
}

void behaviour() {
  AppModel appOf(WidgetTester t) => AppScope.read(t.element(find.byType(RootView)));

  Future<AppModel> open(WidgetTester t, [String extra = '']) async {
    ScreenHarness.configure(t);
    await ScreenHarness.loadFonts();
    await t.pumpWidget(TruverTestApp(args: '$base -tab metronome $extra'));
    await t.pump(const Duration(milliseconds: 600));
    return appOf(t);
  }

  testWidgets('core: rhythms, modes, tap tempo, flash rule', (t) async {
    final app = await open(t);
    expect(RhythmLibrary.all.length, greaterThan(100));
    expect(RhythmLibrary.byId('triplets')!.tupletLabel, '3');
    expect(RhythmLibrary.byId('16:012')!.shortName, '16-16-8');
    app.metronome.updateModes((m) => m.tempo = ModeTempo.speedUp);
    expect(app.metronome.trainingModes!['tempo'], isA<Map>());
    for (final time in [100.0, 100.5, 101.0]) {
      expect(app.core!.call('metronome.tap', {'time': time})['bpm'], isNull);
    }
    expect(app.core!.call('metronome.tap', {'time': 101.5})['bpm'], 120);
    app.metronome.updateModes((m) => m.tempo = ModeTempo.none);
    app.metronome.bpm = 400;
    expect(app.metronome.statusText, '400 BPM — максимум');
    expect(app.metronome.flashRule.kind, isNot('everyBeat'));
  });

  testWidgets('beat menu sets a level', (t) async {
    final app = await open(t);
    await t.tap(find.bySemanticsLabel(RegExp('^Доля 2, обычная')));
    await t.pumpAndSettle();
    expect(find.text('Доля 2 · уровень'), findsOneWidget);
    await t.tap(find.text('Выключена'));
    await t.pumpAndSettle();
    expect(app.metronome.meter.accents, [3, 0, 2, 2]);
    expect(find.text('Доля 2 · уровень'), findsNothing);
  });

  testWidgets('knob swipe, ± and the modes chip', (t) async {
    final app = await open(t);
    final knob = find.byType(TempoKnob);
    final gesture = await t.startGesture(t.getCenter(knob));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
    }
    await gesture.up();
    await t.pumpAndSettle();
    expect(app.metronome.bpm, greaterThan(100));
    final before = app.metronome.bpm;
    await t.tap(find.bySemanticsLabel('Быстрее на 1'));
    await t.pump();
    expect(app.metronome.bpm, before + 1);
    await t.tap(find.text('Режим'));
    await t.pumpAndSettle();
    await t.tap(find.text('Разгон'));
    await t.pumpAndSettle();
    expect(app.metronome.modeChoice, ModeChoice.speedUp);
    expect(app.metronome.modeChip.text, 'Разгон');
    expect(find.text('От'), findsOneWidget);
    await t.tap(find.text('Тренировка пропусков'));
    await t.pumpAndSettle();
    expect(app.metronome.modeChoice, ModeChoice.gapBars);
    expect(app.metronome.state.modes.tempo, ModeTempo.none);
    expect(app.sheet, const AppSheet('metroModeParams', 'gapBars'));
  });

  testWidgets('presets: save, load', (t) async {
    final app = await open(t, '-sheet metroPresets');
    expect(find.text('Пресетов пока нет'), findsOneWidget);
    await t.tap(find.text('Сохранить текущий как пресет'));
    await t.pumpAndSettle();
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(app.metronome.state.presets.single.name, '4/4');
    expect(app.metronome.state.currentPreset?.name, '4/4');
    app.metronome.deletePresetUndoable(app.metronome.state.presets.single.id);
    await t.pump();
    expect(app.metronome.state.presets, isEmpty);
    app.metronome.undoDelete();
    await t.pump();
    expect(app.metronome.state.presets.single.name, '4/4');
  });

  testWidgets('rhythm sheet chooses a figure', (t) async {
    final app = await open(t, '-sheet metroRhythm');
    await t.tap(find.bySemanticsLabel('Восьмые').first);
    await t.pumpAndSettle();
    expect(app.metronome.meter.subdivision, 2);
    expect(app.sheet, isNull);
  });

  testWidgets('status line, chips and preset subtitles of the canvas', (t) async {
    final app = await open(t, '-metroDemo -metroMode speedUp');
    final m = app.metronome;
    expect(m.statusText, 'Разгон: 142 → 160 · +2 каждые 4 такта');
    final subtitles = [for (final p in m.state.presets) m.presetSubtitle(p)];
    expect(subtitles, ['7/8 · 2+2+3 · Разгон', '4/4 · восьмые', '6/8', '4/4 · 16-е']);
    expect(MeterSheet.groupings(7, null).map((g) => g.join('+')), ['2+2+3', '3+2+2', '2+3+2']);
    m.debugPose('target');
    expect(m.statusText, 'Разгон завершён · держим 160');
    m
      ..stop()
      ..clearToast();
  });
}

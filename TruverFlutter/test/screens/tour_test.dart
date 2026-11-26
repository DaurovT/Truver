import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/app_model.dart';
import 'package:truver/app/storage.dart';
import 'package:truver/app/test_app.dart';
import 'package:truver/features/tour/coach_marks.dart';
import 'package:truver/features/tour/help_settings_page.dart';
import 'package:truver/features/tour/tour_view.dart';

import '../support/screen_harness.dart';

/// «Знакомство и обучение» (features/tour) against the canvas renders `test/reference/canvas/<Board>.png`:
///   swift tool/compare.swift test/reference/canvas/CoachTuner1.png build/shots/CoachTuner1.png build/shots/cmp_CoachTuner1.jpg
/// The same arguments reproduce the boards on iOS.
const base = '-resetSettings -skipOnboarding -muteAudio';

const boards = {
  'Tour1Tuner': '-resetSettings -muteAudio -tour 1',
  'Tour2Fret': '-resetSettings -muteAudio -tour 2',
  'Tour3Metro': '-resetSettings -muteAudio -tour 3',
  'Tour4Practice': '-resetSettings -muteAudio -tour 4',
  'CoachTuner1': '$base -template g6-standard-e -tab tuner -tunerDemo flat -coach tuner1',
  'CoachTuner2': '$base -template g6-standard-e -tab tuner -tunerDemo flat -coach tuner2',
  'CoachTuner3': '$base -template g6-standard-e -tab tuner -tunerDemo flat -coach tuner3',
  'CoachFret1': '$base -template g8-standard-fs -tab fretboard -coach fret1',
  'CoachFret2': '$base -template g8-standard-fs -tab fretboard -coach fret2',
  'CoachFret3': '$base -template g8-standard-fs -tab fretboard -coach fret3',
  'CoachTab': '$base -template g8-standard-fs -tab fretboard -fretTabDemoTonic -coach tab',
  'CoachChord': '$base -template g8-standard-fs -tab fretboard -fretMode chord -fretVoicing 5 -coach chord',
  'CoachMetro1': '$base -template g6-standard-e -tab metronome -metroDemo -metroBeat 3 -coach metro1',
  'CoachMetro2': '$base -template g6-standard-e -tab metronome -metroDemo -metroBeat 3 -coach metro2',
  'CoachPractice': '$base -template g8-standard-fs -tab practice -practiceEmpty -coach practice',
  'SettingsHelp': '$base -template g8-standard-fs -tab tuner -settingsPage help',
};

void main() {
  for (final e in boards.entries) {
    testWidgets(e.key, (t) async {
      await t.runAsync(TourImages.load);
      await ScreenHarness.capture(t, e.key, TruverTestApp(args: e.value), settle: const Duration(milliseconds: 900));
    });
  }

  testWidgets('hints wait for the onboarding, show once, «Пропустить» ends the section', (t) async {
    final store = MemoryStore();
    await ScreenHarness.capture(t, 'x_coach_none', TruverTestApp(args: '$base -template g6-standard-e -tab metronome', store: store));
    final center = CoachCenter.instance;
    expect(center.run, isNull, reason: 'not armed: screenshot launches never show hints');
    center.arm();
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 1000));
    expect(center.run?.section, CoachSection.metro);
    expect(find.text('Темп — ручкой'), findsOneWidget);
    await t.tap(find.text('Дальше'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Размер и режимы'), findsOneWidget);
    await t.tap(find.text('Пропустить').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(center.run, isNull);
    expect(center.wants(CoachSection.metro), isFalse);
    expect(center.wants(CoachSection.tuner), isTrue);
    expect(store.getString('coach'), contains('metro'));
    // Another tab: its own hints.
    AppScope.read(t.element(find.byType(CoachHost))).tab = AppTab.practice;
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 1200));
    expect(center.run?.section, CoachSection.practice);
    await t.tap(find.text('Понятно'));
    await t.pump(const Duration(milliseconds: 400));
    expect(center.run, isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the tour leads to the instrument', (t) async {
    await ScreenHarness.capture(t, 'x_tour_flow', const TruverTestApp(args: '-resetSettings -muteAudio -tour 4'));
    expect(find.text('Прогресс считается сам'), findsOneWidget);
    await t.tap(find.text('Выбрать инструмент'));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Ваш инструмент'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Android back closes the replayed tour before the settings', (t) async {
    await ScreenHarness.capture(t, 'x_tour_back', const TruverTestApp(args: '$base -template g8-standard-fs -tab tuner -settingsPage help'));
    
    TourReplay.show.value = true;
    await t.pump(const Duration(milliseconds: 800));
    expect(find.byType(TourView), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 800));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.byType(TourView), findsNothing);
    expect(find.text('Обучение'), findsWidgets); // settings still open
    await t.pumpWidget(const SizedBox());
  });
}

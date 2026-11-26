import 'package:flutter_test/flutter_test.dart';
import 'package:truver/features/fretboard/fretboard_controller.dart';
import 'package:truver/features/fretboard/neck_portrait.dart';
import 'package:truver/app/test_app.dart';

import '../support/screen_harness.dart';

/// The fretboard tab (FretboardScreen.swift and its sheets) against the iOS references in test/reference/ios/fret_*.png.
const base = '-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio';

void main() {
  testWidgets('fret_position', (t) => ScreenHarness.capture(t, 'fret_position', const TruverTestApp(args: '$base -tab fretboard')));
  testWidgets('fret_demo', (t) => ScreenHarness.capture(t, 'fret_demo', const TruverTestApp(args: '$base -tab fretboard -fretDemo')));
  testWidgets('fret_whole', (t) => ScreenHarness.capture(t, 'fret_whole', const TruverTestApp(args: '$base -tab fretboard -neckWhole')));
  testWidgets('fret_scale', (t) => ScreenHarness.capture(t, 'fret_scale', const TruverTestApp(args: '$base -tab fretboard -sheet fretScale')));
  testWidgets('fret_view', (t) => ScreenHarness.capture(t, 'fret_view', const TruverTestApp(args: '$base -tab fretboard -sheet fretView')));
  testWidgets('fret_play', (t) => ScreenHarness.capture(t, 'fret_play', const TruverTestApp(args: '$base -tab fretboard -sheet fretPlay')));
  testWidgets('fret_chord', (t) => ScreenHarness.capture(t, 'fret_chord', const TruverTestApp(args: '$base -tab fretboard -fretMode chord')));
  testWidgets('fret_chord_none', (t) => ScreenHarness.capture(t, 'fret_chord_none', const TruverTestApp(args: '$base -tab fretboard -fretMode chordNone -chordLibrary')));
  testWidgets('fret_search', (t) => ScreenHarness.capture(t, 'fret_search', const TruverTestApp(args: '$base -tab fretboard -fretMode search')));
  testWidgets('fret_search_results', (t) => ScreenHarness.capture(t, 'fret_search_results', const TruverTestApp(args: '$base -tab fretboard -fretMode search -sheet searchResults')));
  testWidgets('fret_progression', (t) => ScreenHarness.capture(t, 'fret_progression', const TruverTestApp(args: '$base -tab fretboard -fretMode progression')));
  testWidgets('fret_progression_sheet', (t) => ScreenHarness.capture(t, 'fret_progression_sheet', const TruverTestApp(args: '$base -tab fretboard -fretMode progression -sheet fretProgression')));
  testWidgets('fret_progression_chord', (t) => ScreenHarness.capture(t, 'fret_progression_chord', const TruverTestApp(args: '$base -tab fretboard -fretMode progression -sheet progressionChord')));
  testWidgets('fret_path', (t) => ScreenHarness.capture(t, 'fret_path', const TruverTestApp(args: '$base -tab fretboard -fretMode path')));
  testWidgets('fret_path1', (t) => ScreenHarness.capture(t, 'fret_path1', const TruverTestApp(args: '$base -tab fretboard -fretMode path1')));
  testWidgets('fret_path_sheet', (t) => ScreenHarness.capture(t, 'fret_path_sheet', const TruverTestApp(args: '$base -tab fretboard -fretMode path -sheet fretPath')));
  testWidgets('fret_chords_from_note', (t) => ScreenHarness.capture(t, 'fret_chords_from_note', const TruverTestApp(args: '$base -tab fretboard -sheet chordsFromNote')));
  testWidgets('fret_scale_from_note', (t) => ScreenHarness.capture(t, 'fret_scale_from_note', const TruverTestApp(args: '$base -tab fretboard -sheet scaleFromNote')));
  testWidgets('fret_scale_builder', (t) => ScreenHarness.capture(t, 'fret_scale_builder', const TruverTestApp(args: '$base -tab fretboard -sheet scaleBuilder')));
  testWidgets('fret_chord_builder', (t) => ScreenHarness.capture(t, 'fret_chord_builder', const TruverTestApp(args: '$base -tab fretboard -sheet chordBuilder')));
  testWidgets('fret_user_scales', (t) => ScreenHarness.capture(t, 'fret_user_scales', const TruverTestApp(args: '$base -tab fretboard -sheet userScales')));

  // Canvas 2026-11-25 boards (reference: the canvas renders, compared with tool/compare.swift).
  const g6 = '-resetSettings -skipOnboarding -template g6-standard-e -muteAudio -tab fretboard';
  const g7 = '-resetSettings -skipOnboarding -template g7-standard-b -muteAudio -tab fretboard';
  const g8 = '$base -tab fretboard';
  testWidgets('board S6Whole', (t) => ScreenHarness.capture(t, 'board_S6Whole', const TruverTestApp(args: g6)));
  testWidgets('board S7Whole', (t) => ScreenHarness.capture(t, 'board_S7Whole', const TruverTestApp(args: g7)));
  testWidgets('board FixFretWhole', (t) => ScreenHarness.capture(t, 'board_FixFretWhole', const TruverTestApp(args: g8)));
  testWidgets('board FretCapo', (t) => ScreenHarness.capture(t, 'board_FretCapo', const TruverTestApp(args: '$g8 -capo 2 -fretsFromCapoOff')));
  testWidgets('board FretLeftHanded', (t) => ScreenHarness.capture(t, 'board_FretLeftHanded', const TruverTestApp(args: '$g8 -leftHanded')));
  testWidgets('board FlowNote1', (t) => ScreenHarness.capture(t, 'board_FlowNote1', const TruverTestApp(args: '$g8 -fretNote 2:5')));
  testWidgets('board FretChordTab', (t) => ScreenHarness.capture(t, 'board_FretChordTab', const TruverTestApp(args: '$g8 -fretMode chord -fretVoicing 5')));
  testWidgets('board FixFretSearch', (t) => ScreenHarness.capture(t, 'board_FixFretSearch', const TruverTestApp(args: '$g8 -fretMode search -sheet searchResults')));
  testWidgets('board FixLandScale', (t) => ScreenHarness.capture(t, 'board_FixLandScale', const TruverTestApp(args: g8), landscape: true));
  testWidgets('board S8Loupe', (t) => ScreenHarness.capture(t, 'board_S8Loupe', const TruverTestApp(args: '$g8 -fretLoupe 3:5')));
  testWidgets('board FlowNote3', (t) => ScreenHarness.capture(t, 'board_FlowNote3', const TruverTestApp(args: '$g8 -fretProg')));

  // Without iOS references: rendered for a look.
  testWidgets('fret_fan', (t) => ScreenHarness.capture(t, 'x_fret_fan', const TruverTestApp(args: '$base -tab fretboard -fan')));
  testWidgets('fret_capo', (t) => ScreenHarness.capture(t, 'x_fret_capo', const TruverTestApp(args: '$base -tab fretboard -capo 3')));
  testWidgets('fret_solfege', (t) => ScreenHarness.capture(t, 'x_fret_solfege', const TruverTestApp(args: '$base -tab fretboard -fretDemo -notation solfege')));
  testWidgets('fret_training', (t) => ScreenHarness.capture(t, 'x_fret_training', const TruverTestApp(args: '$base -tab fretboard -trainingDemo')));

  testWidgets('fret_landscape', (t) => ScreenHarness.capture(t, 'x_fret_landscape', const TruverTestApp(args: '$base -tab fretboard'), landscape: true));
  testWidgets('fret_landscape_path', (t) => ScreenHarness.capture(t, 'x_fret_landscape_path', const TruverTestApp(args: '$base -tab fretboard -fretMode path'), landscape: true));

  testWidgets('a held note shows the loupe, the release opens «что построить»', (t) async {
    await ScreenHarness.capture(t, 'x_fret_menu_before', const TruverTestApp(args: '$base -tab fretboard'));
    final neck = find.byType(NeckPortrait);
    expect(neck, findsOneWidget);
    final box = t.getRect(neck);
    await t.longPressAt(Offset(box.left + 26 + 4, box.top + 20)); // lowest string, 1st fret
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('что построить от этой ноты?'), findsOneWidget);
    expect(find.text('Прогрессия'), findsWidgets);
  });

  testWidgets('a key chord lights its notes; modes switch', (t) async {
    await ScreenHarness.capture(t, 'x_fret_strip', const TruverTestApp(args: '$base -tab fretboard'));
    await t.tap(find.text('Am'));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.text('Аккорд'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('расположение'), findsOneWidget);
    await t.tap(find.text('Поиск'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Отметьте ноты'), findsOneWidget);
    expect(FretMode.values.length, 4);
  });
}

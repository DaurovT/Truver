import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/test_app.dart';

import '../support/screen_harness.dart';

/// The fretboard sheets of the 2026-11-25 canvas against its 3× renders (FixFretPlaySheet, FretViewSheet,
/// FretScalePicker, FretProgressionList, FixFretChordLibrary, FixFretSearch, FixFretChordsFromNote, FlowNote2):
/// `swift tool/compare.swift <canvas>/renders/<Board>.png build/shots/sheet_<board>.png out.jpg --rows <sheet rows>`
const base = '-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio -tab fretboard';

void main() {
  testWidgets('FixFretPlaySheet', (t) => ScreenHarness.capture(t, 'sheet_play', const TruverTestApp(args: '$base -fretBpm 100 -sheet fretPlay')));
  testWidgets('FretViewSheet', (t) => ScreenHarness.capture(t, 'sheet_view', const TruverTestApp(args: '$base -capo 2 -sheet fretView')));
  testWidgets('FretScalePicker', (t) => ScreenHarness.capture(t, 'sheet_scale', const TruverTestApp(args: '$base -sheet fretScale')));
  testWidgets('FretProgressionList',
      (t) => ScreenHarness.capture(t, 'sheet_progressions', const TruverTestApp(args: '$base -fretMode progression -progressionsDemo -sheet fretProgressions')));
  testWidgets('FlowNote2', (t) => ScreenHarness.capture(t, 'sheet_progression_from_note', const TruverTestApp(args: '$base -sheet progressionFromNote')));
  testWidgets('FixFretSearch', (t) => ScreenHarness.capture(t, 'sheet_search', const TruverTestApp(args: '$base -fretMode search -sheet searchResults')));
  testWidgets('FixFretChordsFromNote', (t) => ScreenHarness.capture(t, 'sheet_chords_from_note', const TruverTestApp(args: '$base -sheet chordsFromNote')));
  testWidgets('FixFretChordLibrary', (t) => ScreenHarness.capture(t, 'sheet_chord_library', const TruverTestApp(args: '$base -fretMode chord -chordLibrary')));
}

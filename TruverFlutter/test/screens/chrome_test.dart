import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/test_app.dart';

import '../support/screen_harness.dart';

/// Shared chrome (header, tuning pill, tab bar) on one screen per tab against the canvas renders
/// (6-string Standard E, as the mockups): FixTunerFlat, FretChordTab, MetroStopped, PracticeEmpty.
const base = '-resetSettings -skipOnboarding -template g6-standard-e -muteAudio';

void main() {
  testWidgets('chrome tuner', (t) => ScreenHarness.capture(t, 'chrome_tuner', const TruverTestApp(args: '$base -tab tuner -tunerDemo flat')));
  testWidgets('chrome fretboard', (t) => ScreenHarness.capture(t, 'chrome_fretboard', const TruverTestApp(args: '$base -tab fretboard')));
  testWidgets('chrome metronome', (t) => ScreenHarness.capture(t, 'chrome_metronome', const TruverTestApp(args: '$base -tab metronome')));
  testWidgets('chrome practice', (t) => ScreenHarness.capture(t, 'chrome_practice', const TruverTestApp(args: '$base -tab practice')));
}

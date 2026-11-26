import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/test_app.dart';
import 'package:truver/features/settings/rate_prompt.dart';

import '../support/screen_harness.dart';

/// Settings (SettingsView.swift). References: the canvas boards (scratchpad renders) FixSettingsMain, FixSettingsA4,
/// FixSettingsInput (`-inputLevelDemo 12`: 12 of 24 bars), FixSettingsVolume, SettingsNotation, SettingsOutput
/// (`-audioRoutesDemo`: the board's AirPods and USB interface), SettingsLargeText (text scale 2).
const base = '-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio -tab tuner';

void main() {
  testWidgets('settings', (t) => ScreenHarness.capture(t, 'settings', const TruverTestApp(args: '$base -showSettings')));
  for (final page in ['noise', 'target', 'notation', 'a4', 'input', 'output', 'volume', 'about']) {
    final extra = switch (page) {
      'input' => ' -inputLevelDemo 12',
      'output' => ' -audioRoutesDemo',
      _ => '',
    };
    testWidgets('settings $page',
        (t) => ScreenHarness.capture(t, 'settings_$page', TruverTestApp(args: '$base -settingsPage $page$extra')));
  }
  testWidgets('settings large text', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await ScreenHarness.capture(t, 'settings_large', const TruverTestApp(args: '$base -showSettings'));
  });

  test('rate prompt: from the 3rd tuning, 3 a year, 60 days apart', () {
    final now = DateTime(2026, 11, 25);
    expect(RatePrompt.shouldAsk(successfulTunings: 2, requests: [], now: now), isFalse);
    expect(RatePrompt.shouldAsk(successfulTunings: 3, requests: [], now: now), isTrue);
    expect(RatePrompt.shouldAsk(successfulTunings: 9, requests: [now.subtract(const Duration(days: 30))], now: now), isFalse);
    expect(RatePrompt.shouldAsk(successfulTunings: 9, requests: [now.subtract(const Duration(days: 61))], now: now), isTrue);
    final three = [for (final d in [70, 150, 300]) now.subtract(Duration(days: d))];
    expect(RatePrompt.shouldAsk(successfulTunings: 9, requests: three, now: now), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/test_app.dart';

import '../support/screen_harness.dart';

/// «Таб» (FretTabView.swift) against the canvas renders S6Tab, S7Tab, S8Tab, TabPortraitFull, TabLargeText,
/// FlowNote3Tab and TabLandRuler (compare with `tool/compare.swift`).
const base = '-resetSettings -skipOnboarding -muteAudio -tab fretboard';

void main() {
  testWidgets('tab_s6', (t) => ScreenHarness.capture(t, 'tab_s6', const TruverTestApp(args: '$base -template g6-standard-e -fretTabDemo')));
  testWidgets('tab_s7', (t) => ScreenHarness.capture(t, 'tab_s7', const TruverTestApp(args: '$base -template g7-standard-b -fretTabDemo')));
  testWidgets('tab_s8', (t) => ScreenHarness.capture(t, 'tab_s8', const TruverTestApp(args: '$base -template g8-standard-fs -fretTabDemo')));
  testWidgets('tab_portrait_full',
      (t) => ScreenHarness.capture(t, 'tab_portrait_full', const TruverTestApp(args: '$base -template g8-standard-fs -fretTabDemoTonic')));
  testWidgets('tab_large',
      (t) => ScreenHarness.capture(t, 'tab_large', const TruverTestApp(args: '$base -template g8-standard-fs -fretTabDemoTonic -fretTabLarge')));
  testWidgets('tab_progression',
      (t) => ScreenHarness.capture(t, 'tab_progression', const TruverTestApp(args: '$base -template g8-standard-fs -fretProgTab')));
  testWidgets('tab_landscape',
      (t) => ScreenHarness.capture(t, 'tab_landscape', const TruverTestApp(args: '$base -template g8-standard-fs -fretTabDemoTonic'),
          landscape: true));

  testWidgets('back leaves the tab, the tab bar returns', (t) async {
    await ScreenHarness.capture(t, 'x_tab_back', const TruverTestApp(args: '$base -template g6-standard-e -fretTabDemo'));
    expect(find.text('Тюнер'), findsNothing);
    await t.tap(find.text('Гриф').first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Тюнер'), findsOneWidget);
  });
}

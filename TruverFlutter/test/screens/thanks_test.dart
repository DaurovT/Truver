import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/test_app.dart';
import 'package:truver/features/thanks/svg_path.dart';
import 'package:truver/features/thanks/thanks_model.dart';

import '../support/screen_harness.dart';

/// «Спасибо · обновления» (Features/Thanks). References: the canvas renders (ThanksAbout, ThanksMusicians,
/// ThanksProfile, ThanksOffline, ThanksLargeText, ShareSheet, UpdateAvailable, UpdateWhatsNew, UpdateRequired,
/// UpdateCheckFailed). The people differ by design — the app shows the real list (`assets/thanks/thanks.json`),
/// not the canvas samples — so the layout geometry is compared, not the names.
const base = '-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio';

Future<void> shot(WidgetTester t, String name, String args, {double textScale = 1}) async {
  await t.runAsync(ThanksData.instance.load); // the list and the decoded photos, outside the fake clock
  if (textScale != 1) {
    t.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await ScreenHarness.capture(t, name, TruverTestApp(args: '$base $args'), settle: const Duration(milliseconds: 900));
}

/// The same screens with the invented people of the canvas (test fixture, never in the app) — pixel comparison.
Future<void> sample(WidgetTester t, String name, String args, {double textScale = 1}) async {
  await t.runAsync(ThanksData.instance.load);
  final data = ThanksData.instance;
  final (musicians, partners) = (data.musicians, data.partners);
  data.apply(jsonDecode(File('../Truver/Tools/canvas/thanks_canvas_sample.json').readAsStringSync()) as Map<String, dynamic>);
  try {
    await shot(t, name, args, textScale: textScale);
  } finally {
    data.musicians = musicians;
    data.partners = partners;
  }
}

void main() {
  testWidgets('ThanksAbout sample', (t) => sample(t, 'ThanksAbout_sample', '-tab tuner -settingsPage about -updateDemo banner'));
  testWidgets('UpdateCheckFailed sample', (t) => sample(t, 'UpdateCheckFailed_sample', '-tab tuner -settingsPage about -updateDemo failed'));
  testWidgets('ThanksMusicians sample', (t) => sample(t, 'ThanksMusicians_sample', '-tab tuner -settingsPage thanks'));
  testWidgets('ThanksPartners sample', (t) => sample(t, 'ThanksPartners_sample', '-tab tuner -settingsPage thanks -thanksTab partners'));
  testWidgets('ThanksProfile sample', (t) => sample(t, 'ThanksProfile_sample', '-tab tuner -settingsPage thanks -thanksProfile anya'));
  testWidgets('ThanksOffline sample', (t) => sample(t, 'ThanksOffline_sample', '-tab tuner -settingsPage thanks -thanksOffline'));
  testWidgets('ThanksLargeText sample', (t) => sample(t, 'ThanksLargeText_sample', '-tab tuner -settingsPage thanks', textScale: 2));
  testWidgets('ShareSheet sample', (t) => sample(t, 'ShareSheet_sample', '-tab tuner -settingsPage about -shareSheet -updateDemo banner'));

  testWidgets('ThanksAbout', (t) => shot(t, 'ThanksAbout', '-tab tuner -settingsPage about -updateDemo banner'));
  testWidgets('UpdateCheckFailed', (t) => shot(t, 'UpdateCheckFailed', '-tab tuner -settingsPage about -updateDemo failed'));
  testWidgets('ThanksAbout up to date', (t) => shot(t, 'ThanksAbout_current', '-tab tuner -settingsPage about'));
  testWidgets('ThanksMusicians', (t) => shot(t, 'ThanksMusicians', '-tab tuner -settingsPage thanks'));
  testWidgets('ThanksProfile', (t) => shot(t, 'ThanksProfile', '-tab tuner -settingsPage thanks -thanksProfile timur-daurov'));
  testWidgets('ThanksOffline', (t) => shot(t, 'ThanksOffline', '-tab tuner -settingsPage thanks -thanksOffline'));
  testWidgets('ThanksLargeText', (t) => shot(t, 'ThanksLargeText', '-tab tuner -settingsPage thanks', textScale: 2));
  testWidgets('ShareSheet', (t) => shot(t, 'ShareSheet', '-tab tuner -settingsPage about -shareSheet -updateDemo banner'));
  testWidgets('UpdateAvailable', (t) => shot(t, 'UpdateAvailable', '-tab tuner -updateDemo available'));
  testWidgets('UpdateWhatsNew', (t) => shot(t, 'UpdateWhatsNew', '-tab tuner -updateDemo whatsNew'));
  testWidgets('UpdateRequired', (t) => shot(t, 'UpdateRequired', '-tab tuner -updateDemo required'));

  // Logic (no screenshots).
  test('thanks.json: the real list, partners empty', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ThanksData.instance.load();
    final data = ThanksData.instance;
    expect(data.musicians.map((m) => m.name), ['Тимур Дауров']);
    expect(data.partners, isEmpty);
    final timur = data.person('timur-daurov')!;
    expect(timur.subtitle, 'создатель Truver');
    expect(timur.thanks, 'Спасибо за создание Truver');
    expect(timur.links.single.displayHandle, '@drv_tim');
    expect(timur.links.single.url, 'https://instagram.com/drv_tim');
    expect(timur.initials, 'ТД');
    expect(data.photos.containsKey('timur-daurov-small.jpg'), isTrue);
  });

  test('versions and SVG paths', () {
    expect(UpdateCenter.compare('1.0', '1.2'), -1);
    expect(UpdateCenter.compare('1.10', '1.9'), 1);
    expect(UpdateCenter.compare('1.0', '1.0.0'), 0);
    expect(UpdateCenter.dayMonth(DateTime(2026, 11, 20)), '20 ноября');
    final pick = parseSvgPath('M28 4C40 4 50 9 50 19c0 13-12 27-19.5 32.5a4.2 4.2 0 0 1-5 0C18 46 6 32 6 19 6 9 16 4 28 4z').getBounds();
    expect(pick.left, closeTo(6, 0.01));
    expect(pick.right, closeTo(50, 0.01));
    expect(pick.top, closeTo(4, 0.01));
  });
}

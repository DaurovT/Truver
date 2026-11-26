import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/app_model.dart';
import 'package:truver/app/debug_args.dart';
import 'package:truver/app/storage.dart';
import 'package:truver/app/test_app.dart';

import 'support/screen_harness.dart';

void main() {
  test('settings round-trip with Swift field names and per-field defaults', () {
    final s = AppSettings()
      ..notation = 'german'
      ..lastTab = AppTab.metronome
      ..metronome.presets = [MetronomePreset(name: 'Риф', settings: {'bpm': 142, 'numerator': 7, 'denominator': 8})];
    final json = jsonDecode(s.encode()) as Map<String, dynamic>;
    expect(json['lastTab'], 'metronome');
    expect(json['metronome']['modes']['tempo'], 'none');
    final back = AppSettings.fromJson(json);
    expect(back.encode(), s.encode());
    // A missing key falls back alone.
    final partial = AppSettings.fromJson({'notation': 'solfege', 'metronome': {'timerMinutes': 0}});
    expect(partial.notation, 'solfege');
    expect(partial.metronome.timerMinutes, 1);
    expect(partial.metronome.meter['bpm'], 100);
  });

  test('instrument, title, names through the core', () {
    final store = MemoryStore();
    final app = AppModel(store: store, args: DebugArgs('-skipOnboarding -template g8-standard-fs'));
    expect(app.title, '8-струнная · Стандарт F♯');
    expect(app.stringName(0), 'F♯1');
    app.updateSettings((s) => s.notation = 'german');
    expect(app.stringName(1), 'H1');
    app.addTemplate('g8-drop-e');
    expect(app.tunings.length, 2);
    expect(app.tuningName, 'Drop E');
    app.deleteTuning(app.tuning['id'] as String);
    expect(app.tunings.length, 1);
    expect(AppModel.shortInstrumentName('Гитара, 7 струн'), '7-струнная');
    // Persisted.
    final again = AppModel(store: store, args: DebugArgs(''));
    expect(again.settings.notation, 'german');
    expect(again.title, '8-струнная · Стандарт F♯');
  });

  testWidgets('tab bar, gear and onboarding steps', (t) async {
    await ScreenHarness.loadFonts();
    ScreenHarness.configure(t);
    await t.pumpWidget(const TruverTestApp(args: '-resetSettings -muteAudio'));
    await t.pumpAndSettle();
    expect(find.text('Начать'), findsOneWidget);
    await t.tap(find.text('Начать'));
    await t.pumpAndSettle();
    // «Знакомство» (features/tour) comes between the welcome and the instrument.
    expect(find.text('Настройте гитару за минуту'), findsOneWidget);
    await t.tap(find.text('Пропустить'));
    await t.pumpAndSettle();
    expect(find.text('Ваш инструмент'), findsOneWidget);
    await t.tap(find.text('Бас'));
    await t.pumpAndSettle();
    expect(find.text('Число струн'), findsOneWidget);
    await t.tap(find.text('Продолжить'));
    await t.pumpAndSettle();
    expect(find.text('Зачем микрофон'), findsOneWidget);
    final app = AppScope.read(t.element(find.text('Зачем микрофон')));
    expect(app.instrument['type'], 'bass');
    app.showOnboarding = false;
    await t.pumpAndSettle();
    await t.tap(find.text('Метроном'));
    await t.pumpAndSettle();
    expect(app.tab, AppTab.metronome);
    await t.tap(find.bySemanticsLabel('Настройки'));
    await t.pumpAndSettle();
    expect(app.showSettings, isTrue);
    app.show('Тест');
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(app.notice, isNull);
    await t.pumpWidget(const SizedBox());
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:truver/app/app_model.dart';
import 'package:truver/app/test_app.dart';
import 'package:truver/design/controls.dart';
import 'package:truver/features/root/root_view.dart';

import '../support/screen_harness.dart';

/// «Инструмент и строи» sheets (TuningsSheet.swift). References: the canvas boards, `test/reference/canvas/<Board>.png`
/// (3× WebKit renders, the same grid as the harness):
///   swift tool/compare.swift test/reference/canvas/TuningsList.png build/shots/inst_tunings.png build/shots/cmp_inst_tunings.jpg
/// The same arguments reproduce each board on iOS (simulator «Eskiz 17e»).
const base = '-resetSettings -skipOnboarding -muteAudio -tab tuner -tunerDemo flat';
const six = '$base -template g6-standard-e -tuningsDemo';

void main() {
  const states = {
    'inst_tunings': '$six -sheet tunings', // TuningsList
    'inst_last_one': '$base -template ukulele-standard -sheet tuningsLastOne', // TuningsLastOne
    'inst_delete': '$six -sheet tuningsDelete', // TuningsDeleteConfirm
    'inst_tunings_add': '$six -sheet tuningsAdd', // TuningAdd
    'inst_unsaved': '$six -sheet tuningUnsaved', // TuningUnsaved
    'inst_tuning_editor': '$six -sheet tuningEditor', // FixTuningEditor
    'inst_library': '$six -sheet libraryDrop', // TuningsLibrary
    'inst_generator': '$six -sheet generatorDropC', // TuningsGenerator
    'inst_instrument': '$six -sheet instrument', // FixTunerInstrument
    // No new boards: kept as they were.
    'inst_template_card': '$base -template g8-standard-fs -sheet templateCard',
    'inst_rebuild': '$base -template g8-standard-fs -sheet instrumentRebuild',
    'inst_strings': '$base -template g8-standard-fs -sheet instrumentStrings',
  };
  for (final e in states.entries) {
    testWidgets(e.key, (t) => ScreenHarness.capture(t, e.key, TruverTestApp(args: e.value)));
  }
  behaviour();
}

/// Behaviour: the flows of the sheets (taps through the real shell and core).
Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 16));
}

void behaviour() {
  Future<AppModel> open(WidgetTester t, String args) async {
    await ScreenHarness.loadFonts();
    ScreenHarness.configure(t);
    await t.pumpWidget(TruverTestApp(args: args));
    await settle(t);
    return AppScope.read(t.element(find.byType(RootView)));
  }

  testWidgets('tuning pill opens «Инструмент и строи»', (t) async {
    final app = await open(t, '$base -template g8-standard-fs');
    await t.tap(find.text(app.title));
    await settle(t);
    expect(app.sheet, const AppSheet('tunings'));
    expect(find.text('Инструмент и строи'), findsOneWidget);
  });

  testWidgets('-tuningsDemo: five tunings of the canvas', (t) async {
    final app = await open(t, '$six -sheet tunings');
    expect([for (final x in app.tunings) x['name']], ['Стандарт E', 'Drop D', 'Полтона ниже', 'DADGAD', 'Open G']);
    expect(find.text('Строи · касание — переключить, ≡ — править'), findsOneWidget);
    expect(find.text('24 лада'), findsOneWidget);
  });

  testWidgets('editor: 6th string E2 → D2 asks to save as «Drop D»', (t) async {
    final app = await open(t, '$base -template g6-standard-e -sheet tuningEditor');
    expect(find.text('Стандарт E · редактор'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Ниже на полутон').first);
    await t.tap(find.bySemanticsLabel('Ниже на полутон').first);
    await t.pump();
    await t.tap(find.bySemanticsLabel('Закрыть'));
    await t.pump();
    expect(find.text('Сохранить изменения?'), findsOneWidget);
    expect(find.text('Вы изменили 6-ю струну: E2 → D2. Это уже другой строй — «Drop D».'), findsOneWidget);
    expect(find.text('Заменить «Стандарт E»'), findsOneWidget);
    await t.tap(find.text('Сохранить как «Drop D»'));
    await settle(t);
    expect(app.sheet, const AppSheet('tunings'));
    expect([for (final x in app.tunings) x['name']], ['Стандарт E', 'Drop D']);
    expect(app.tuningName, 'Drop D'); // a saved new tuning becomes current (Instrument.addTuning)
  });

  testWidgets('by hand: an unsaved copy, saved; then swipe-delete with confirmation', (t) async {
    final app = await open(t, '$base -template g6-standard-e -sheet tuningsAdd');
    await t.tap(find.text('Вручную'));
    await settle(t);
    expect(app.sheet?.kind, 'tuningEditor');
    expect(app.tunings.length, 1); // not saved yet
    await t.tap(find.text('Сохранить'));
    await settle(t);
    expect(app.tunings.length, 2);
    expect(app.tuningName, 'Свой строй');
    await t.drag(find.text('Свой строй'), const Offset(-200, 0));
    await settle(t);
    await t.tap(find.text('Удалить').last);
    await t.pump();
    expect(find.text('Удалить «Свой строй»?'), findsOneWidget);
    await t.tap(find.text('Удалить').last);
    await settle(t);
    expect(app.tunings.length, 1);
  });

  testWidgets('the last tuning: a toast instead of deleting', (t) async {
    final app = await open(t, '$base -template ukulele-standard -sheet tunings');
    expect(find.text('Стандарт C'), findsOneWidget);
    await t.drag(find.text('Стандарт C'), const Offset(-200, 0));
    await settle(t);
    await t.tap(find.text('Удалить').last);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Последний строй удалить нельзя — сначала добавьте другой'), findsOneWidget);
    expect(app.tunings.length, 1);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('library: kinds, «+» adds, «добавлен», nothing found', (t) async {
    final app = await open(t, '$six -sheet library');
    await t.tap(find.text('Drop'));
    await t.pump();
    expect(find.text('Drop · 6 струн'), findsOneWidget);
    expect(find.text('добавлен'), findsOneWidget); // Drop D
    await t.tap(find.byKey(const ValueKey('add g6-drop-c')));
    await t.pump();
    expect(app.tunings.length, 6);
    expect(find.text('добавлен'), findsNWidgets(2));
    await t.enterText(find.byType(EditableText), 'нет такого');
    await t.pump();
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('generator: Drop D exists → switch; 2 tones → «Добавить «Drop C»»', (t) async {
    final app = await open(t, '$six -sheet generator');
    expect(find.text('Переключиться на «Drop D»'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Больше'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Больше'));
    await t.pump();
    expect(find.text('2 тона'), findsOneWidget);
    expect(find.text('Струны тоньше 0.052 на 6-й могут болтаться — следите за натяжением'), findsOneWidget);
    await t.tap(find.text('Добавить «Drop C»'));
    await settle(t);
    expect(app.tunings.length, 6);
    expect(app.tunings.last['name'], 'Drop C');
  });

  testWidgets('generator demo: Drop C from the template, notes C2 G2 C3 F3 A3 D4', (t) async {
    await open(t, '$six -sheet generatorDropC');
    expect(find.text('Добавить «Drop C»'), findsOneWidget);
    expect(find.text('на 1 тон ниже'), findsOneWidget);
  });

  testWidgets('rebuild to 9 strings; fan frets and string sets', (t) async {
    final app = await open(t, '$base -template g8-standard-fs -sheet instrumentRebuild');
    await t.tap(find.text('Пересобрать'));
    await settle(t);
    expect(app.courseCount, 9);
    expect(app.sheet, const AppSheet('instrument'));
    app.sheet = const AppSheet('instrumentStrings');
    await settle(t);
    await t.tap(find.byType(ToggleSwitch).first);
    await t.pump();
    expect(app.instrument['multiscale'], isNotNull);
    expect(find.text('28″–25.5″ · 8-й'), findsOneWidget);
    await t.tap(find.text('Свой'));
    await settle(t);
    await t.tap(find.text('Kalium 9-str 10–90'));
    await settle(t);
    expect(find.text('.090'), findsOneWidget);
  });

  testWidgets('-fan sets the first typical fan', (t) async {
    final app = await open(t, '$base -template g8-standard-fs -fan');
    expect((app.instrument['multiscale'] as Map)['neutralFret'], 7);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/app_model.dart';
import 'package:truver/app/storage.dart';
import 'package:truver/app/test_app.dart';
import 'package:truver/features/practice/fret_trainer_controller.dart';
import 'package:truver/features/practice/fret_trainer_view.dart';
import 'package:truver/features/practice/play_check_charts.dart';
import 'package:truver/features/practice/practice_screen.dart';
import 'package:truver/features/practice/practice_session_view.dart';
import 'package:truver/features/root/root_view.dart';
import 'package:truver/features/practice/practice_session_controller.dart';

import '../support/screen_harness.dart';

/// The Practice tab: journal, play-check charts, «Занятие», «Тренажёр грифа».
/// References: test/reference/ios/practice*.png (arguments in states.txt). The iOS simulator's journal held one
/// entry when they were taken (today 16:47–16:48, «8-струнная · Стандарт F#», 1 min) — seeded the same here.
const base = '-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio';

/// The journal of the reference simulator.
MemoryStore journalStore() {
  final now = DateTime.now();
  final entry = PracticeEntry(
    start: DateTime(now.year, now.month, now.day, 16, 47, 10),
    instrumentName: '8-струнная гитара',
    tuningName: 'Стандарт F#',
  )..seconds = 65;
  return MemoryStore({
    PracticeJournal.key: jsonEncode([entry.toJson()]),
  });
}

/// `ScreenHarness.capture` with a step between the first frames and the snapshot.
Future<void> captureAfter(
  WidgetTester t,
  String name,
  Widget screen,
  Future<void> Function() step, {
  void Function(AppModel app)? close,
}) async {
  await ScreenHarness.loadFonts();
  ScreenHarness.configure(t);
  final key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(key: key, child: screen));
  await t.pump(const Duration(milliseconds: 600));
  await step();
  await t.pump(const Duration(milliseconds: 16));
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ScreenHarness.pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('build/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  // Timers and the trainer's tuner subscription stop before the tree goes.
  final app = AppScope.read(t.element(find.byType(RootView)));
  close?.call(app);
  app.trainer.close();
  await t.pump(const Duration(seconds: 2));
}

void main() {
  tearDown(() {
    FretTrainerController.holdFeedback = false;
    FretTrainerController.debugSeed = null;
  });

  // The corrected canvas boards (references: the canvas renders, `scratchpad/canvas/renders/<Board>.png`; the
  // same arguments reproduce them on iOS).
  testWidgets('practice charts', (t) => ScreenHarness.capture(t, 'practice_charts', const TruverTestApp(args: '$base -tab practice -practiceDemo')));

  testWidgets('practice empty', (t) => ScreenHarness.capture(t, 'practice_empty', const TruverTestApp(args: '$base -tab practice -practiceEmpty')));

  testWidgets('practice session', (t) => ScreenHarness.capture(t, 'practice_session', const TruverTestApp(args: '$base -tab practice -sheet session')));

  testWidgets('practice session running', (t) async {
    await captureAfter(
      t,
      'practice_session_running',
      const TruverTestApp(args: '$base -tab practice -sheet session -sessionRunning'),
      () async {
        await t.pump(const Duration(milliseconds: 100));
        final app = AppScope.read(t.element(find.byType(PracticeSessionView)));
        expect(app.session.phase, SessionPhase.playing);
        expect(app.session.remaining, 297);
      },
      close: (app) {
        app.session.stop();
        app.session.reset();
      },
    );
  });

  testWidgets('practice trainer name', (t) async {
    await captureAfter(
      t,
      'practice_trainer_name',
      const TruverTestApp(args: '$base -tab practice -sheet trainerName -trainerAsk 5:8'),
      () async => expect(AppScope.read(t.element(find.byType(FretTrainerView))).trainer.question?.fret, 8),
    );
  });

  testWidgets('trainer play', (t) async {
    await captureAfter(
      t,
      'trainer_play',
      const TruverTestApp(args: '$base -tab practice -sheet trainerPlay -trainerAsk 3:5 -trainerPrior 1'),
      () async => expect(AppScope.read(t.element(find.byType(FretTrainerView))).trainer.session?.correct, 1),
    );
  });

  testWidgets('trainer right', (t) async {
    await captureAfter(
      t,
      'trainer_right',
      const TruverTestApp(args: '$base -tab practice -sheet trainerPlay -trainerAsk 3:5 -trainerPrior 1 -trainerRight'),
      () async => expect(AppScope.read(t.element(find.byType(FretTrainerView))).trainer.feedback.isCorrect, isTrue),
    );
  });

  testWidgets('trainer wrong', (t) async {
    await captureAfter(
      t,
      'trainer_wrong',
      const TruverTestApp(args: '$base -tab practice -sheet trainerName -trainerAsk 0:1 -trainerWrong 0'),
      () async {
        final trainer = AppScope.read(t.element(find.byType(FretTrainerView))).trainer;
        expect(trainer.feedback.isWrong, isTrue);
        expect(trainer.session!.answered, 1);
      },
    );
  });

  testWidgets('practice trainer summary', (t) async {
    await captureAfter(
      t,
      'practice_trainer_summary',
      const TruverTestApp(args: '$base -tab practice -sheet trainerName -trainerSummary'),
      () async => expect(find.text('Повторить ошибки'), findsOneWidget),
    );
  });

  testWidgets('trainer next and repeat mistakes', (t) async {
    await ScreenHarness.loadFonts();
    ScreenHarness.configure(t);
    await t.pumpWidget(const TruverTestApp(args: '$base -tab practice -sheet trainerName -trainerAsk 0:1 -trainerWrong 0'));
    await t.pump(const Duration(milliseconds: 600));
    final trainer = AppScope.read(t.element(find.byType(FretTrainerView))).trainer;
    expect(trainer.feedback.isWrong, isTrue);
    await t.pump(const Duration(seconds: 3));
    expect(trainer.feedback.isWrong, isTrue); // a wrong answer waits for «Дальше»
    await t.tap(find.text('Дальше'));
    await t.pump(const Duration(milliseconds: 300));
    expect(trainer.feedback.isNone, isTrue);
    expect(trainer.session!.answered, 1);
    trainer.close();
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('trainer options menu', (t) async {
    await ScreenHarness.loadFonts();
    ScreenHarness.configure(t);
    await t.pumpWidget(TruverTestApp(args: '$base -tab practice -sheet trainerName', store: journalStore()));
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.bySemanticsLabel('Настройки тренажёра'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Три нижние'), findsOneWidget);
    await t.tap(find.text('Три нижние'));
    await t.pump(const Duration(milliseconds: 300));
    final app = AppScope.read(t.element(find.byType(FretTrainerView)));
    expect(app.trainer.settings.strings, TrainerStrings.low);
    expect(app.trainer.question!.course, lessThan(3));
    app.trainer.close();
    await t.pump(const Duration(seconds: 2));
  });

  // Logic (no screenshots).
  test('journal merges a day per instrument and tuning, metronome by preset', () {
    final day = DateTime(2026, 11, 20, 18, 40);
    PracticeEntry e(int minute, double seconds, {String preset = '', double bpm = 0, double minBPM = 0}) =>
        PracticeEntry(
            start: day.add(Duration(minutes: minute)),
            instrumentName: 'Гитара, 8 струн',
            tuningName: 'Drop E',
          )
          ..seconds = seconds
          ..usedMetronome = bpm > 0
          ..lastBPM = bpm
          ..minBPM = minBPM
          ..presetName = preset;
    final sessions = merged([
      e(0, 600, preset: 'Риф 7/8', bpm: 150, minBPM: 142),
      e(20, 300, preset: 'Риф 7/8', bpm: 146, minBPM: 146),
      e(40, 120),
    ]);
    expect(sessions, hasLength(1));
    expect(sessions[0].title, '8-струнная · Drop E');
    expect(sessions[0].seconds, 1020);
    expect(sessions[0].metronome.single, (name: 'Риф 7/8', minBPM: 142.0, maxBPM: 150.0));
    expect(PracticeScreen.duration(1020), '17 мин');
    expect(PracticeScreen.duration(3900), '1 ч 5 мин');
    expect(PracticeScreen.duration(7800), '2 ч 10 мин');
    expect(CeilingChart.grid([128, 146]), (120.0, 15.0));
    expect(CeilingChart.shortDate(DateTime(2026, 11, 10)), '10 нояб.');
    expect(PracticeScreen.dayTitle(DateTime(2026, 11, 20), DateTime(2026, 11, 25, 12)), 'пятница, 20 ноября');
    final data = PracticeJournalData([e(0, 600), e(60 * 24, 20)], DateTime(2026, 11, 21, 9));
    expect(data.days, hasLength(1)); // under 30 s does not count
    expect(data.streak, 1);
  });

  test('plural and plan JSON', () {
    expect(PracticeSessionController.plural(1, 'минута', 'минуты', 'минут'), 'минута');
    expect(PracticeSessionController.plural(3, 'минута', 'минуты', 'минут'), 'минуты');
    expect(PracticeSessionController.plural(11, 'минута', 'минуты', 'минут'), 'минут');
    final plan = PracticePlan.fromJson(jsonDecode(jsonEncode(PracticePlan(pauseSeconds: 30).toJson())) as Map<String, dynamic>);
    expect(plan.pauseSeconds, 30);
    expect(plan.steps.single.minutes, 5);
  });
}

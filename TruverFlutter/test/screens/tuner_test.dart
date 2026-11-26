import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/app_model.dart';
import 'package:truver/app/debug_args.dart';
import 'package:truver/app/feature_registry.dart';
import 'package:truver/app/storage.dart';
import 'package:truver/app/test_app.dart';
import 'package:truver/features/tuner/tuner_controller.dart';
import 'package:truver/features/tuner/tuner_screen.dart';

import '../support/screen_harness.dart';

/// Tuner states against the canvas renders (corrected «Fix…» boards of 2026-11-25, 1170 × 2532 / 2532 × 1170 —
/// `scratchpad/canvas/renders/<Board>.png`; the same arguments reproduce each board on iOS):
///   flutter test test/screens/tuner_test.dart
///   swift tool/compare.swift <canvas>/FixTunerFlat.png build/shots/FixTunerFlat.png build/shots/cmp_FixTunerFlat.jpg
const base = '-resetSettings -skipOnboarding -muteAudio';

/// Mockups use a 6-string Standard E unless they show otherwise (S7 / S8 — 7 / 8 strings).
String _args(String state) => state.contains('-template') ? '$base $state' : '$base -template g6-standard-e $state';

const states = {
  'FixTunerFlat': '-tab tuner -tunerDemo flat',
  'FixTunerSharp': '-tab tuner -tunerDemo sharp',
  'FixTunerWaiting': '-tab tuner -tunerDemo waiting',
  'FixTunerDone': '-tab tuner -tunerDemo done',
  'FixTunerReference': '-tab tuner -tunerDemo reference',
  'FixTunerOutOfRange': '-tab tuner -tunerDemo outOfRange',
  'FixTunerNoAccess': '-tab tuner -tunerDemo noAccess',
  'FixTunerPro': '-tab tuner -tunerDemo flat -sheet tunerPro',
  'FixTunerIntonation': '-tab tuner -tunerDemo flat -sheet intonation -intonationDemo',
  'TunerListening': '-tab tuner -tunerDemo listening',
  'TunerManual': '-tab tuner -tunerDemo manual',
  'TunerChromatic': '-tab tuner -tunerDemo chromatic',
  'TunerStrobe': '-tab tuner -tunerDemo strobe',
  'TunerStagePhone': '-tab tuner -tunerDemo stage -tunerStage',
  'TunerBluetooth': '-tab tuner -tunerDemo bluetooth',
  'TunerEngineFail': '-tab tuner -tunerDemo engineFail',
  'TunerInputSwitched': '-tab tuner -tunerDemo inputSwitched',
  'DeviceDisconnected': '-tab tuner -tunerDemo disconnected',
  'S6Tuner': '-tab tuner -tunerDemo flat',
  'S7Tuner': '-tab tuner -tunerDemo flat -template g7-standard-b',
  'S8Tuner': '-tab tuner -tunerDemo flat -template g8-standard-fs',
};

void main() {
  test('core describes the strings and a reading becomes the canvas texts', () {
    registerFeatures();
    final app = AppModel(store: MemoryStore(), args: DebugArgs('$base -template g8-standard-fs'));
    final tuner = app.tuner;
    expect(tuner.courses.map((c) => '${c.short}${c.octave}').join(' '), 'F♯1 B1 E2 A2 D3 G3 B3 E4');
    expect(tuner.openFrequency(const StringRef(3)), closeTo(110, 0.01));
    tuner.applyPoll({
      'tuner': [
        {
          'display': 'reading',
          'level': -30,
          'reading': {
            'frequency': 109.1,
            'pitch': {'cents': -2414, 'label': 'A2', 'name': 'A', 'octave': 2},
            'target': {
              'kind': 'string',
              'string': {'course': 3, 'string': 0},
              'target': {'cents': -2400, 'label': 'A2', 'name': 'A', 'octave': 2},
              'deviation': -14.2,
            },
            'provisional': false,
            'inTune': false,
          },
          'tuned': [],
          'allTuned': false,
        },
      ],
    });
    final p = TunerPresenter(app);
    expect(p.statusText, 'Ниже — подтяните');
    expect(p.voiceValue, 'A2, ниже на 14 центов');
    expect(tuner.stringStatus[const StringRef(3)], StringStatus.flat);
    expect(TunerPresenter.tones(-400), '−2 тона');
    expect(TunerPresenter.tones(100), '+полтона');
    expect(TunerPresenter.tones(-300), '−1,5 тона');
    app.dispose();
  });

  for (final MapEntry(key: name, value: args) in states.entries) {
    testWidgets(name, (t) async {
      resetTunerStageArg();
      await ScreenHarness.capture(t, name, TruverTestApp(args: _args(args)));
    });
  }

  // Canvas «Тюнер — крупный шрифт»: the accessibility text size (the shell hides the tuning pill too).
  testWidgets('FixTunerLarge', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await ScreenHarness.capture(t, 'FixTunerLarge', TruverTestApp(args: _args('-tab tuner -tunerDemo large -tunerLarge')));
  });

  testWidgets('LandTuner',
      (t) => ScreenHarness.capture(t, 'LandTuner', TruverTestApp(args: _args('-tab tuner -tunerDemo landscape')), landscape: true));
}

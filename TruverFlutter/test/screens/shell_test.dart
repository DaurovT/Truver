import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/test_app.dart';

import '../support/screen_harness.dart';

/// The app shell: header, tuning pill and tab bar over the tab screens. References:
/// test/reference/ios/{tuner_flat,shell_practice}.png. The design-system sheets «Таймер занятия» and «Звуки и
/// выходы» are checked by the real metronome sheets in metronome_test.dart (metro_timer, metro_sounds).
const base = '-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio';

void main() {
  testWidgets('shell tuner', (t) => ScreenHarness.capture(t, 'shell_tuner', const TruverTestApp(args: '$base -tab tuner')));
  testWidgets('shell practice', (t) => ScreenHarness.capture(t, 'shell_practice', const TruverTestApp(args: '$base -tab practice')));
}

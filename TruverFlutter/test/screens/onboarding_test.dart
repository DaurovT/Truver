import 'package:flutter_test/flutter_test.dart';
import 'package:truver/app/test_app.dart';

import '../support/screen_harness.dart';

/// Onboarding steps. References: test/reference/ios/onboarding_{0,1,2}.png
/// (iOS: `-resetSettings -onboardingStep N -muteAudio`).
void main() {
  for (final step in [0, 1, 2]) {
    testWidgets('onboarding $step',
        (t) => ScreenHarness.capture(t, 'onboarding_$step', TruverTestApp(args: '-resetSettings -onboardingStep $step -muteAudio')));
  }
}

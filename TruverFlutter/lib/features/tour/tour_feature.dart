/// Registration of «Знакомство и обучение» (features/tour) in the app shell: the coach marks over everything, the
/// tour replayed from the settings, and the launch arguments `-coach <board>` (CoachCatalog.parse), `-tour N`
/// (read by the onboarding) and `-settingsPage help` (read by the settings).
library;

import 'package:flutter/widgets.dart';

import '../../app/feature_registry.dart';
import '../../design/motion.dart';
import 'coach_marks.dart';
import 'help_settings_page.dart';
import 'tour_view.dart';

void registerTour() {
  FeatureRegistry.debugHooks.add((app, args) {
    CoachCenter.instance.attach(app);
    TourReplay.show.value = false;
  });
  FeatureRegistry.overlays.add((context) => const CoachHost());
  FeatureRegistry.overlays.add((context) => const _TourReplayHost());
}

class _TourReplayHost extends StatelessWidget {
  const _TourReplayHost();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: TourReplay.show,
        builder: (context, show, _) => AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.out,
          switchOutCurve: Motion.out,
          child: show
              ? TourView(key: const ValueKey('tour'), mode: TourMode.replay, finish: () => TourReplay.show.value = false)
              : const SizedBox.shrink(),
        ),
      );
}

/// Registration of «Спасибо · обновления» in the app shell: the update notices over the app (`UpdateNoticeHost`) and
/// the people list loaded at start. «О Truver» itself is a settings page (`SettingsPage.about` → `AboutView`).
/// Debug arguments (same as iOS): `-settingsPage about|thanks`, `-updateDemo available|banner|whatsNew|required|failed`,
/// `-shareSheet`, `-aboutWhatsNew`, `-thanksProfile <id>`, `-thanksTab partners`, `-thanksOffline`.
library;

import '../../app/feature_registry.dart';
import 'thanks_model.dart';
import 'update_views.dart';

void registerThanks() {
  FeatureRegistry.overlays.add((context) => const UpdateNoticeHost());
  FeatureRegistry.debugHooks.add((app, args) {
    UpdateCenter.of(app);
    ThanksData.instance.load();
  });
}

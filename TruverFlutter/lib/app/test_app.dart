/// The app for tests and the screen harness: the same shell with given debug arguments and in-memory settings.
///
///   testWidgets('tuner flat', (t) => ScreenHarness.capture(t, 'tuner_flat', TruverTestApp(args: '-tab tuner -tunerDemo flat')));
library;

import 'package:flutter/widgets.dart';

import 'app_model.dart';
import 'debug_args.dart';
import 'feature_registry.dart';
import 'storage.dart';
import 'truver_app.dart';

class TruverTestApp extends StatefulWidget {
  const TruverTestApp({super.key, this.args = '', this.store});

  /// Launch arguments as on iOS (`-tab metronome -sheet metroTimer`). `-skipOnboarding` is not implied.
  final String args;

  /// Settings to start from (defaults to an empty memory store).
  final SettingsStore? store;

  @override
  State<TruverTestApp> createState() => _TruverTestAppState();
}

class _TruverTestAppState extends State<TruverTestApp> {
  late final AppModel model;

  @override
  void initState() {
    super.initState();
    registerFeatures();
    model = AppModel(store: widget.store ?? MemoryStore(), args: DebugArgs(widget.args));
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TruverApp(model: model);
}

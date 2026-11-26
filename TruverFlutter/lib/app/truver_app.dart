/// Port of Truver/Sources/App/TruverApp.swift
library;

import 'package:flutter/widgets.dart';

import '../design/theme.dart';
import '../design/typo.dart';
import '../features/root/root_view.dart';
import 'app_model.dart';
import 'feature_registry.dart';

/// The app: dark, no Material visuals, the shell from `RootView`. `model` is created by `main` (real storage)
/// or by `TruverTestApp` (memory, debug arguments).
class TruverApp extends StatelessWidget {
  const TruverApp({super.key, required this.model});
  final AppModel model;

  @override
  Widget build(BuildContext context) => AppScope(
        app: model,
        child: WidgetsApp(
          title: 'Truver',
          color: TruverColors.background,
          debugShowCheckedModeBanner: false,
          textStyle: Typo.inter(15, TypoWeight.regular, TruverColors.textBody),
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
              PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
          home: const _Home(),
        ),
      );
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: const TruverScrollBehavior(),
        child: ColoredBox(
          color: TruverColors.background,
          // Feature layers over the shell (update notices, `FeatureRegistry.overlays`).
          child: Stack(children: [const Positioned.fill(child: RootView()), for (final o in FeatureRegistry.overlays) Positioned.fill(child: Builder(builder: o))]),
        ),
      );
}

/// iOS-like scrolling everywhere: bounce, no glow, no scrollbars.
class TruverScrollBehavior extends ScrollBehavior {
  const TruverScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// Port of Truver/Sources/Features/Root/RootView.swift
///
/// App shell (canvas): the current tab's screen, the tuning pill above a custom tab bar, sheets, toasts on top,
/// full-screen covers (settings, session, trainer, onboarding).
///
/// Tab screens are laid out in the iOS safe area: the box starts below the status bar (47 pt on the reference
/// phone) and ends above the tuning pill; `MediaQuery.padding` inside is zero.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/feature_registry.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/landscape.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../metronome/metronome_screen.dart' show metronomeInterruptionBanner;
import '../onboarding/onboarding_view.dart';
import '../tour/coach_marks.dart';

/// System text size at or above iOS «accessibility» sizes (Dynamic Type AX1: body 17 → 28 pt).
bool isAccessibilityTextSize(BuildContext context) => MediaQuery.textScalerOf(context).scale(17) / 17 >= 1.6;

class RootView extends StatefulWidget {
  const RootView({super.key});

  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).updateListening();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) AppScope.read(context).practice.flush();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final media = MediaQuery.of(context);
    final landscape = isPhoneLandscape(context);
    final tab = app.settings.lastTab;
    final landscapeBuilder = landscape ? FeatureRegistry.landscapeScreens[tab] : null;

    Widget screen = KeyedSubtree(
      key: ValueKey(tab),
      child: Builder(builder: (context) => (FeatureRegistry.tabScreens[tab] ?? _placeholder(tab))(context)),
    );
    screen = AnimatedSwitcher(
      duration: Motion.quick,
      switchInCurve: Motion.out,
      switchOutCurve: Motion.out,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [...previous, ?current]),
      child: screen,
    );

    final hideBar = FeatureRegistry.hidesTabBar[tab]?.call(app) ?? false;
    final body = landscapeBuilder != null
        ? landscapeBuilder(context)
        : Column(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: media.padding.top, left: media.padding.left, right: media.padding.right),
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    removeLeft: true,
                    removeRight: true,
                    child: ExcludeSemantics(excluding: app.sheet != null, child: screen),
                  ),
                ),
              ),
              if (!hideBar) ExcludeSemantics(
                excluding: app.sheet != null,
                // The corrected canvas shows the tuning pill on the tuner only (the fretboard names the tuning under
                // its title; metronome and practice boards have none). The pill sits 8 pt above the tab bar.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (TuningPill.isShown(tab) && !TuningPill.largeText(context)) ...[const CoachAnchor(id: CoachAnchors.tuningPill, child: TuningPill()), const SizedBox(height: 8)],
                    AppTabBar(selection: tab, onSelect: (t) => app.tab = t, bottomInset: media.padding.bottom),
                  ],
                ),
              ),
            ],
          );

    return KeyCommands(
      child: Stack(
        children: [
          const Positioned.fill(child: ScreenBackground()),
          Positioned.fill(child: body),
          // Canvas «Прервано звонком»: the banner at y 698 lies over the tab bar.
          if (!landscape && tab == AppTab.metronome && app.sheet == null)
            Positioned(
              left: 20,
              right: 20,
              top: 698,
              child: ListenableBuilder(
                listenable: app.metronome,
                builder: (context, _) => app.metronome.interrupted ? metronomeInterruptionBanner(app.metronome) : const SizedBox.shrink(),
              ),
            ),
          const Positioned.fill(child: SheetHost()),
          Positioned(left: 0, right: 0, top: media.padding.top, child: const ToastHost()),
          Positioned.fill(
            child: FullScreenCover(
              visible: app.showSettings,
              builder:
                  FeatureRegistry.settings ?? (_) => _CoverPlaceholder(title: 'Настройки', close: () => app.showSettings = false),
            ),
          ),
          Positioned.fill(
            child: FullScreenCover(
              visible: app.showSession,
              builder:
                  FeatureRegistry.session ?? (_) => _CoverPlaceholder(title: 'Занятие', close: () => app.showSession = false),
            ),
          ),
          Positioned.fill(
            child: FullScreenCover(
              visible: app.showTrainer,
              onShow: app.trainer.open,
              onDismiss: app.trainer.close,
              builder:
                  FeatureRegistry.trainer ??
                  (_) => _CoverPlaceholder(title: 'Тренажёр грифа', close: () => app.showTrainer = false),
            ),
          ),
          Positioned.fill(
            child: FullScreenCover(visible: app.showOnboarding, builder: (_) => const OnboardingView()),
          ),
        ],
      ),
    );
  }

  static WidgetBuilder _placeholder(AppTab tab) =>
      (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: tabTitle(tab)),
          const Spacer(),
        ],
      );
}

String tabTitle(AppTab tab) => switch (tab) {
  AppTab.tuner => 'Тюнер',
  AppTab.fretboard => 'Гриф',
  AppTab.metronome => 'Метроном',
  AppTab.practice => 'Занятия',
};

/// «8-струнная · Drop E ▾» above the tab bar: the tuning switcher (6, 6.1 п. 2). Canvas: a 40 pt button, padding 18,
/// radius 20, border white 8 %, card fill, 14 medium, chevron 14, gap 8, shadow `0 8px 20px` black 50 %.
class TuningPill extends StatelessWidget {
  const TuningPill({super.key});

  /// Tabs whose boards show the pill (the tuner only since the corrected canvas).
  static bool isShown(AppTab tab) => tab == AppTab.tuner;

  /// Large-text boards (FixTunerLarge, MetroLargeText) have no pill; `-tunerLarge` forces the tuner's large layout.
  static bool largeText(BuildContext context) =>
      isAccessibilityTextSize(context) || AppScope.read(context).args.has('-tunerLarge');

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final large = isAccessibilityTextSize(context);
    final locked = app.isSmartModeRunning;
    return Pressable(
      label: 'Строй: ${app.title}',
      onTap: () {
        if (locked) {
          app.show('Остановите упражнение, чтобы сменить строй', icon: AppIcon.lock);
        } else {
          app.sheet = const AppSheet('tunings');
        }
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: large ? 270 : 0, minHeight: large ? 48 : 40, maxHeight: large ? 48 : 40),
        child: ShapeBox(
          shape: const SwiftShape.rounded(1000),
          shadows: [SwiftShadow(TruverColors.black(0.5), 10, y: 8)],
          fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Large text (canvas): only the tuning name, 18 pt, a 270 × 48 button.
                Flexible(
                  child: Text(
                    large ? app.tuningName : app.title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textScaler: large ? TextScaler.noScaling : null,
                    style: large
                        ? Typo.fixed(18, TypoWeight.regular, TruverColors.textBody)
                        : Typo.inter(14, TypoWeight.medium, TruverColors.textBody),
                  ),
                ),
                const SizedBox(width: 8),
                // Canvas «переключатель заблокирован»: a lock instead of the chevron while an exercise runs.
                AppIconView(locked ? AppIcon.lock : AppIcon.chevronDown, size: 14, color: TruverColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom tab bar of the canvas: 84 pt with the home-indicator area (50 above it), background #0a0b0d at 96 %, top
/// hairline white 6 %, padding 8; items: icon 24 at 13 pt from the top (border 1 + padding 8 + 4), label 11 four
/// points below — ivory semibold when selected, tertiary regular otherwise. A playing metronome shows a dot on its
/// icon breathing with the strong beats (motion spec, «Навигация»).
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.selection, required this.onSelect, this.bottomInset = 0});

  final AppTab selection;
  final ValueChanged<AppTab> onSelect;

  /// The home-indicator area the bar's background runs into.
  final double bottomInset;

  static const _items = [
    (AppTab.tuner, AppIcon.tuner, 'Тюнер'),
    (AppTab.fretboard, AppIcon.fretboard, 'Гриф'),
    (AppTab.metronome, AppIcon.metronome, 'Метроном'),
    (AppTab.practice, AppIcon.practice, 'Занятия'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final large = isAccessibilityTextSize(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: TruverColors.background.withValues(alpha: 0.96)),
      position: DecorationPosition.background,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(left: 8, right: 8, bottom: bottomInset),
            child: Row(
              children: [
                for (final (tab, icon, title) in _items)
                  Expanded(
                    child: Pressable(
                      scale: 1,
                      label: title,
                      selected: selection == tab,
                      onTap: () => onSelect(tab),
                      child: SizedBox(
                        height: 50,
                        child: OverflowBox(
                          maxHeight: double.infinity,
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 13),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AppIconView(
                                      icon,
                                      size: 24,
                                      lineWidth: 1.5,
                                      color: selection == tab ? TruverColors.textPrimary : TruverColors.textTertiary,
                                    ),
                                    if (tab == AppTab.metronome && app.metronome.isPlaying)
                                      Positioned(
                                        right: -3,
                                        top: -1,
                                        child: AnimatedOpacity(
                                          opacity: app.metronome.currentBeat == 0 ? 1 : 0.45,
                                          duration: Motion.tick,
                                          curve: Motion.out,
                                          child: const SizedBox(
                                            width: 6,
                                            height: 6,
                                            child: ShapeBox(
                                              shape: SwiftShape.circle,
                                              fills: [SwiftFill(TruverColors.textPrimary)],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                // Large text (corrected canvas «Тюнер / Метроном — крупный шрифт»): the labels stay, at 11 pt.
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  textScaler: large ? TextScaler.noScaling : null,
                                  style: (selection == tab ? Typo.tabSelected : Typo.tab).copyWith(
                                    color: selection == tab ? TruverColors.textPrimary : TruverColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ColoredBox(color: TruverColors.white(0.06), child: const SizedBox(height: 1)),
          ),
        ],
      ),
    );
  }
}

/// Presents `app.sheet`: dim fades in (280 ms), the panel rises 60 pt with fade (340 ms, «out»); closing slides it
/// down off the screen.
class SheetHost extends StatelessWidget {
  const SheetHost({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sheet = app.sheet;
    final builder = sheet == null ? null : FeatureRegistry.sheets[sheet.kind];
    // A sheet whose feature is not ported yet shows nothing (no dim over an empty panel).
    final shown = builder != null;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !shown,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: Semantics(
                label: 'Закрыть лист',
                button: true,
                onTap: () => app.sheet = null,
                child: GestureDetector(
                  onTap: () => app.sheet = null,
                  child: ColoredBox(color: TruverColors.sheetDim),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 340),
            reverseDuration: const Duration(milliseconds: 340),
            switchInCurve: Motion.out,
            switchOutCurve: Motion.out,
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [...previous, ?current]),
            transitionBuilder: (child, animation) {
              final entering = child.key == ValueKey(sheet);
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) {
                  final t = animation.value;
                  if (entering) {
                    return Opacity(
                      opacity: t.clamp(0, 1),
                      child: Transform.translate(offset: Offset(0, 60 * (1 - t)), child: child),
                    );
                  }
                  // `.move(edge: .bottom)`: down by the panel's own height.
                  return FractionalTranslation(translation: Offset(0, 1 - t), child: child);
                },
              );
            },
            child: sheet == null || builder == null
                ? const SizedBox.shrink(key: ValueKey(null))
                : KeyedSubtree(
                    key: ValueKey(sheet),
                    child: Builder(builder: (context) => builder(context, sheet)),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The toast of `app.notice` under the status bar: a design toast with an icon (62 pt) or the plain capsule (54 pt).
class ToastHost extends StatelessWidget {
  const ToastHost({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final notice = app.notice;
    Widget child = const SizedBox.shrink(key: ValueKey('none'));
    if (notice != null) {
      child = Padding(
        key: ValueKey(notice),
        padding: EdgeInsets.only(top: app.noticeIcon != null ? 62 : 54),
        child: Center(
          child: app.noticeIcon != null
              ? DesignToast(icon: app.noticeIcon, iconColor: app.noticeIconColor, text: notice)
              : ToastView(text: notice),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.out,
      switchOutCurve: Motion.out,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// iOS `.fullScreenCover`: slides up over everything, slides down when dismissed.
class FullScreenCover extends StatefulWidget {
  const FullScreenCover({super.key, required this.visible, required this.builder, this.onShow, this.onDismiss});

  final bool visible;
  final WidgetBuilder builder;
  final VoidCallback? onShow;
  final VoidCallback? onDismiss;

  @override
  State<FullScreenCover> createState() => _FullScreenCoverState();
}

class _FullScreenCoverState extends State<FullScreenCover> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.visible ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) widget.onShow?.call();
  }

  @override
  void didUpdateWidget(FullScreenCover old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (widget.visible) {
        widget.onShow?.call();
        _controller.animateTo(1, curve: Motion.snap, duration: Motion.reduced(context) ? Duration.zero : null);
      } else {
        _controller.animateBack(0, curve: Motion.inCurve, duration: Motion.reduced(context) ? Duration.zero : Motion.move).then((
          _,
        ) {
          widget.onDismiss?.call();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      if (_controller.value == 0 && !widget.visible) return const SizedBox.shrink();
      return FractionalTranslation(
        translation: Offset(0, 1 - _controller.value),
        child: Semantics(scopesRoute: true, explicitChildNodes: true, child: widget.builder(context)),
      );
    },
  );
}

/// A cover whose feature is not ported yet: background, title and a close button.
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title, required this.close});
  final String title;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: ScreenBackground()),
      Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 6, left: 20, right: 20),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: Typo.screenTitle.copyWith(color: TruverColors.textPrimary, letterSpacing: -0.17)),
              ),
              RoundIconButton(icon: AppIcon.close, label: 'Закрыть', onTap: close),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Hardware keys and Bluetooth page-turner pedals (they send arrows or Page Up / Down): Space — metronome
/// start/stop, ← → — tempo ∓1 (⇧ — ∓10), ↑ ↓ / Page Up / Page Down — previous / next preset (keeps playing),
/// T — tap tempo, Ctrl+1…4 — tabs.
class KeyCommands extends StatelessWidget {
  const KeyCommands({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
      final app = AppScope.read(context);
      final m = app.metronome;
      final keys = HardwareKeyboard.instance;
      final key = event.logicalKey;
      if (keys.isControlPressed || keys.isMetaPressed) {
        final tabs = {
          LogicalKeyboardKey.digit1: AppTab.tuner,
          LogicalKeyboardKey.digit2: AppTab.fretboard,
          LogicalKeyboardKey.digit3: AppTab.metronome,
          LogicalKeyboardKey.digit4: AppTab.practice,
        };
        final tab = tabs[key];
        if (tab == null) return KeyEventResult.ignored;
        app.tab = tab;
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.space) {
        m.toggle();
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        m.step(keys.isShiftPressed ? -10 : -1);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        m.step(keys.isShiftPressed ? 10 : 1);
      } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
        _stepPreset(app, -1);
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown) {
        _stepPreset(app, 1);
      } else if (key == LogicalKeyboardKey.keyT) {
        m.tapTempo();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    },
    child: child,
  );

  /// Next / previous preset — a pedal walks a set list; the metronome keeps playing from the next bar.
  static void _stepPreset(AppModel app, int delta) {
    final presets = app.settings.metronome.presets;
    if (presets.isEmpty) return;
    var current = presets.indexWhere((p) => p.id == app.settings.metronome.currentPresetId);
    if (current < 0) current = delta > 0 ? -1 : presets.length;
    final next = (current + delta).clamp(0, presets.length - 1);
    if (next == current) return;
    app.metronome.load(presets[next]);
    final bpm = (presets[next].settings['bpm'] as num?)?.toInt() ?? 0;
    app.show('${presets[next].name} · $bpm', icon: AppIcon.list);
  }
}

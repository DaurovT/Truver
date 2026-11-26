/// Port of Truver/Sources/Features/Thanks/AboutView.swift
///
/// «О Truver» (canvas ThanksAbout / UpdateCheckFailed): the app icon and word mark, the update banner, «Спасибо» and
/// «Что нового», then share, feedback, rating and privacy. Opened from «Настройки → О Truver».
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../design/brand.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'share_truver_sheet.dart';
import 'thanks_art.dart';
import 'thanks_chrome.dart';
import 'thanks_model.dart';
import 'thanks_view.dart';
import 'update_views.dart';

export 'thanks_model.dart' show appVersion, appBuild;

/// «Оценить в Google Play» (iOS: the system rating sheet).
/// TODO(android): the In-App Review API once the app is published; until then the store page.
void rateApp() => openExternal('market://details?id=app.truver.android');

/// «Обратная связь» (iOS `mailto:?subject=Truver`).
void openFeedback() => openExternal(UpdateCenter.feedbackUrl);

enum _Overlay { share, whatsNew }

class AboutView extends StatefulWidget {
  const AboutView({super.key, required this.back});
  final VoidCallback back;

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> with SingleTickerProviderStateMixin {
  _Overlay? _overlay;
  late final AnimationController _push;
  bool _thanks = false;

  @override
  void initState() {
    super.initState();
    _push = AnimationController(vsync: this, duration: Motion.move);
    // Screenshot hooks: `-settingsPage thanks` (the list), `-shareSheet`, `-aboutWhatsNew`, `-thanksProfile <id>`.
    final args = AppScope.read(context).args;
    if (args.has('-shareSheet')) _overlay = _Overlay.share;
    if (args.has('-aboutWhatsNew')) _overlay = _Overlay.whatsNew;
    if (args.value('-settingsPage') == 'thanks' || args.has('-thanksProfile')) {
      _thanks = true;
      _push.value = 1;
    }
    ThanksData.instance.load();
  }

  @override
  void dispose() {
    _push.dispose();
    super.dispose();
  }

  void _openThanks() {
    setState(() => _thanks = true);
    if (Motion.reduced(context)) {
      _push.value = 1;
    } else {
      _push.animateTo(1, curve: Motion.out);
    }
  }

  Future<void> _closeThanks() async {
    if (Motion.reduced(context)) {
      _push.value = 0;
    } else {
      await _push.animateBack(0, curve: Motion.out);
    }
    if (mounted) setState(() => _thanks = false);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(children: [
      const Positioned.fill(child: ScreenBackground()),
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ThanksHeader(title: 'О Truver', back: widget.back),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
                  child: _content(context),
                ),
              ),
            ),
          ]),
        ),
      ),
      Positioned.fill(
        child: ThanksSheetHost<_Overlay>(
          item: _overlay,
          dim: _overlay == _Overlay.share ? const Color.fromRGBO(3, 3, 4, 0.55) : null,
          dismiss: () => setState(() => _overlay = null),
          builder: (context, item) => switch (item) {
            _Overlay.share => ShareTruverSheet(close: () => setState(() => _overlay = null)),
            _Overlay.whatsNew => UpdateSheet(kind: UpdateSheetKind.whatsNew, atLaunch: false, close: () => setState(() => _overlay = null)),
          },
        ),
      ),
      if (_thanks)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _push,
            builder: (context, child) => FractionalTranslation(translation: Offset(1 - _push.value, 0), child: child),
            child: ThanksView(back: _closeThanks),
          ),
        ),
    ]);
  }

  Widget _content(BuildContext context) {
    final updates = UpdateCenter.of(AppScope.read(context));
    final notes = updates.whatsNew;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18), // 112 from the top of the screen
      const Center(child: TruverAppIconArt(size: 96, radius: 21)),
      const SizedBox(height: 12),
      const SizedBox(height: 34, child: OverflowBox(maxHeight: 60, child: Center(child: Wordmark(size: 34)))),
      const SizedBox(height: 46), // cards from 300
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListenableBuilder(
            listenable: updates,
            builder: (context, _) => updates.status == UpdateStatus.available ||
                    updates.status == UpdateStatus.required ||
                    updates.status == UpdateStatus.failed
                ? const Padding(padding: EdgeInsets.only(bottom: 14), child: UpdateBanner())
                : const SizedBox.shrink(),
          ),
          Card(children: [
            Pressable(scale: 1, onTap: _openThanks, label: 'Спасибо', child: const _ThanksRow()),
            ThanksRow(
              title: 'Что нового',
              value: notes?.$1 ?? updates.currentVersion,
              onTap: () => setState(() => _overlay = _Overlay.whatsNew),
            ),
          ]),
          const SizedBox(height: 14),
          Card(children: [
            ThanksRow(title: 'Поделиться Truver', onTap: () => setState(() => _overlay = _Overlay.share)),
            ThanksRow(title: 'Обратная связь', onTap: () => openExternal(UpdateCenter.feedbackUrl)),
            ThanksRow(title: 'Оценить в Google Play', onTap: rateApp),
            ThanksRow(
              title: 'Конфиденциальность',
              subtitle: 'звук не записывается и не отправляется',
              minHeight: 61,
              onTap: () => showPrivacyPolicy(context),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

/// «Спасибо · музыканты и партнёры» with the first three avatars (26 pt, overlapping by 8).
class _ThanksRow extends StatelessWidget {
  const _ThanksRow();

  @override
  Widget build(BuildContext context) {
    final data = ThanksData.instance;
    return ValueListenableBuilder(
      valueListenable: data.loaded,
      builder: (context, _, _) {
        final people = [...data.musicians, ...data.partners].take(3).toList();
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: TruverColors.white(0.06)))),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 65), // 64 + the bottom border
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const ThanksPick(size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    SwiftText('Спасибо', style: Typo.row.copyWith(color: TruverColors.textBody)),
                    const SizedBox(height: 2),
                    SwiftText('музыканты и партнёры', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                  ]),
                ),
                if (people.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 26.0 + 18 * (people.length - 1),
                    height: 26,
                    child: Stack(children: [
                      for (final (i, p) in people.indexed)
                        Positioned(left: 18.0 * i, top: 0, child: ThanksAvatar(person: p, size: 26, font: 9, badge: null, index: i)),
                    ]),
                  ),
                ],
                const SizedBox(width: 12),
                const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Privacy policy (6.2 «О приложении»): what the app does and does not do with data. Kept in the app, so it works
/// offline and before a web page exists. iOS shows it as a system page sheet; here a panel slides up the same way.
void showPrivacyPolicy(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _PrivacyLayer(dismiss: () => entry.remove()));
  overlay.insert(entry);
}

class _PrivacyLayer extends StatefulWidget {
  const _PrivacyLayer({required this.dismiss});
  final VoidCallback dismiss;

  @override
  State<_PrivacyLayer> createState() => _PrivacyLayerState();
}

class _PrivacyLayerState extends State<_PrivacyLayer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: Motion.move)..animateTo(1, curve: Motion.out);

  static const _sections = [
    ('Микрофон',
        'Truver слушает микрофон, только пока открыт тюнер. Звук анализируется на устройстве и сразу отбрасывается: он не записывается, не сохраняется и никуда не отправляется.'),
    ('Данные',
        'Строи, пресеты метронома, журнал занятий и настройки хранятся только на этом устройстве. Удалите приложение — они удалятся вместе с ним.'),
    ('Сеть', 'Truver не обращается к интернету: нет аккаунтов, серверов и синхронизации.'),
    ('Аналитика и реклама', 'Нет аналитики, рекламы, трекинга и сторонних SDK. Мы не знаем, кто и как пользуется приложением.'),
    ('Обратная связь', 'Если вы напишете нам письмо, мы увидим только то, что вы в нём отправили, и используем это лишь для ответа.'),
  ];

  Future<void> _close() async {
    await _controller.animateBack(0, curve: Motion.inCurve);
    widget.dismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                child: ColoredBox(color: TruverColors.black(0.4 * _controller.value)),
              ),
            ),
            Positioned.fill(
              top: padding.top + 10,
              child: FractionalTranslation(translation: Offset(0, 1 - _controller.value), child: child),
            ),
          ],
        ),
        child: ShapeBox(
          shape: const SwiftShape.topRounded(26),
          fills: const [SwiftFill(TruverColors.panel)],
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('Конфиденциальность', style: Typo.inter(17, TypoWeight.semibold, TruverColors.textPrimary)),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Pressable(
                        scale: 1,
                        onTap: _close,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(child: Text('Готово', style: Typo.inter(17, TypoWeight.semibold, TruverColors.textPrimary))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + padding.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, (title, text)) in _sections.indexed) ...[
                        if (i > 0) const SizedBox(height: 18),
                        SwiftText(title, style: Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
                        const SizedBox(height: 6),
                        SwiftText(text, style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary), lineSpacing: 3),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Port of Truver/Sources/Features/Onboarding/OnboardingView.swift
///
/// First launch (canvas «Первый запуск», 6.1 п. 4): welcome → instrument → why the microphone → system request.
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/brand.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../tour/coach_marks.dart';
import '../tour/tour_view.dart';

enum OnboardingKind {
  guitar('Гитара'),
  bass('Бас'),
  ukulele('Укулеле'),
  mandolin('Мандолина');

  const OnboardingKind(this.title);
  final String title;

  /// Canvas tile caption.
  String get subtitle => switch (this) {
    OnboardingKind.guitar => '6–9 струн',
    OnboardingKind.bass => '4–6 струн',
    OnboardingKind.ukulele => '4 струны',
    OnboardingKind.mandolin => '4 пары струн',
  };

  (int, int)? get stringRange => switch (this) {
    OnboardingKind.guitar => (6, 9),
    OnboardingKind.bass => (4, 6),
    _ => null,
  };
}

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  /// 0 welcome, 1 instrument, 2 microphone (then the system request).
  late int step = AppScope.read(context).onboardingStep.clamp(0, 2);
  OnboardingKind kind = OnboardingKind.guitar;
  int strings = 7;
  String templateId = 'g7-standard-b';
  int frets = 24;

  /// «Знакомство» (features/tour) between the welcome and the instrument; `-tour N` (debug) opens card N.
  late int? tourPage = switch (AppScope.read(context).args.intValue('-tour')) {
    final n? when n > 0 => n - 1,
    _ => null,
  };

  void _go(int next) => setState(() => step = next);

  @override
  Widget build(BuildContext context) {
    final reduce = Motion.reduced(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return Stack(
          children: [
            const Positioned.fill(child: ScreenBackground()),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: reduce ? Motion.base : Motion.snapDuration,
                switchInCurve: reduce ? Motion.out : Motion.snap,
                switchOutCurve: reduce ? Motion.out : Motion.snap,
                layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                transitionBuilder: (child, animation) {
                  final key = (child.key as ValueKey<int>).value;
                  final entering = key == step;
                  if (key == 0 || reduce) return FadeTransition(opacity: animation, child: child);
                  // Step 1 enters from the trailing edge and leaves to the leading one; step 2 enters from trailing.
                  final begin = entering || key == 2 ? const Offset(1, 0) : const Offset(-1, 0);
                  return SlideTransition(
                    position: Tween(begin: begin, end: Offset.zero).animate(animation),
                    child: child,
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: switch (step) {
                    0 => _welcome(h),
                    1 => _instrument(h),
                    _ => _microphone(h),
                  },
                ),
              ),
            ),
            // Canvas: the dots row at 64 pt on «Ваш инструмент», at 70 pt on «Зачем микрофон».
            if (step > 0) Positioned(left: 0, right: 0, top: step == 1 ? 64 : 70, child: _progress(reduce)),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: reduce ? Motion.base : Motion.move,
                switchInCurve: Motion.out,
                switchOutCurve: Motion.out,
                transitionBuilder: (child, animation) => reduce
                    ? FadeTransition(opacity: animation, child: child)
                    : SlideTransition(
                        position: Tween(begin: Offset(tourPage != null ? 1 : -1, 0), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                child: tourPage == null
                    ? const SizedBox.shrink()
                    : TourView(
                        key: const ValueKey('tour'),
                        mode: TourMode.firstRun,
                        page: tourPage!,
                        finish: () => setState(() {
                          tourPage = null;
                          step = 1;
                        }),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Canvas boards are 844 pt high and positioned from the screen top; blocks under the middle keep their distance
  /// to the bottom edge instead, so taller and shorter phones only stretch the gap between them.
  static double _fromBottom(double y, double h) => h - (844 - y);

  Widget _progress(bool reduce) => Semantics(
    label: 'Шаг $step из 3',
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: reduce ? Motion.base : Motion.snapDuration,
            curve: reduce ? Motion.out : Motion.snap,
            width: i == step - 1 ? 22 : 6,
            height: 6,
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: i == step - 1 ? TruverColors.textPrimary : TruverColors.white(step == 1 ? 0.25 : 0.2),
            ),
          ),
        ],
      ],
    ),
  );

  // MARK: Step 0 (canvas «Первый запуск — приветствие»)

  Widget _welcome(double h) => Stack(
    children: [
      // Mark 150 at 150 pt, then 28 pt gaps: the wordmark (line height 1 → 64 pt box) and the tagline
      // (17 pt, line height 1.45, max 300 wide).
      Positioned(
        left: 0,
        right: 0,
        top: 150,
        child: Column(
          children: [
            const SizedBox(width: 150, height: 150, child: BrandMark()),
            const SizedBox(height: 28),
            SizedBox(
              height: 64,
              child: OverflowBox(maxHeight: double.infinity, child: const Wordmark(size: 64)),
            ),
            // − 1: SkParagraph sets the first line of a line-spaced paragraph 1 pt lower than WebKit / SwiftUI (measured).
            const SizedBox(height: 28 + (17 * 1.45 - 17 * interLineHeight) / 2 - 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                'Тюнер, гриф и метроном для гитар на 4–9 струн — и любых строев',
                textAlign: TextAlign.center,
                textHeightBehavior: swiftLineSpacing,
                style: lineSpaced(
                  Typo.inter(17, TypoWeight.regular, TruverColors.textSecondary),
                  17 * 1.45 - 17 * interLineHeight,
                ),
              ),
            ),
          ],
        ),
      ),
      // What the app does: three rows of icon 20 + 14 pt text, 10 apart, at 560 pt.
      Positioned(
        left: 24,
        right: 24,
        top: _fromBottom(560, h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _feature(AppIcon.tuner, 'Точный тюнер, даже для B0 на 9 струнах'),
            const SizedBox(height: 10),
            _feature(AppIcon.fretboard, 'Гаммы и позиции в вашем строе'),
            const SizedBox(height: 10),
            _feature(AppIcon.metronome, 'Метроном с режимами для занятий'),
          ],
        ),
      ),
      Positioned(
        left: 24,
        right: 24,
        top: _fromBottom(716, h),
        child: Column(
          children: [
            PrimaryButton(title: 'Начать', height: 56, maxWidth: null, onTap: () => setState(() => tourPage = 0)),
            const SizedBox(height: 6),
            Text('Бесплатно. Без регистрации и рекламы', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
          ],
        ),
      ),
    ],
  );

  Widget _feature(AppIcon icon, String text) => SizedBox(
    height: 20,
    child: Row(
      children: [
        AppIconView(icon, size: 20, lineWidth: 1.6, color: TruverColors.textSecondary),
        const SizedBox(width: 12),
        Text(text, style: Typo.inter(14, TypoWeight.regular, TruverColors.textBody)),
      ],
    ),
  );

  // MARK: Step 1

  List<Map<String, dynamic>> get _templates {
    final app = AppScope.read(context);
    List all;
    try {
      all = (app.core?.call('theory.templates') as List?) ?? const [];
    } catch (_) {
      all = const [];
    }
    return [
      for (final t in all.cast<Map>())
        if (switch (kind) {
          OnboardingKind.guitar => (t['type'] == 'guitar' || t['type'] == 'guitarExtendedHigh') && t['courses'] == strings,
          OnboardingKind.bass => t['type'] == 'bass' && t['courses'] == strings,
          OnboardingKind.ukulele => t['type'] == 'ukulele',
          OnboardingKind.mandolin => t['type'] == 'mandolin',
        })
          Map<String, dynamic>.from(t),
    ];
  }

  /// Common fret counts: guitars 21 / 22 / 24 / 27 (baritone), basses 20 / 21 / 22 / 24.
  List<int>? get _fretOptions => switch (kind) {
    OnboardingKind.guitar => const [21, 22, 24, 27],
    OnboardingKind.bass => const [20, 21, 22, 24],
    _ => null,
  };

  void _pickFirstTemplate() {
    final first = _templates.firstOrNull;
    if (first != null) templateId = first['id'] as String;
  }

  String get _templateCaption => switch (kind) {
    OnboardingKind.guitar || OnboardingKind.bass => 'Строй · $strings ${strings < 5 ? 'струны' : 'струн'}',
    _ => 'Строй',
  };

  Widget _instrument(double h) {
    final app = AppScope.of(context);
    final range = kind.stringRange;
    final fretOptions = _fretOptions;
    final templates = _templates;
    final hasCard = range != null || fretOptions != null;
    final listTop = hasCard ? 476.0 : 340.0;
    return Stack(
      children: [
        Positioned(
          left: 24,
          right: 24,
          top: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ваш инструмент', style: Typo.inter(30, TypoWeight.light, TruverColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Всё можно поменять позже', style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
            ],
          ),
        ),
        // Instrument tiles: 2 columns, 8 apart, 72 pt, radius 16; name 16 semibold + range 12, left-aligned.
        Positioned(
          left: 24,
          right: 24,
          top: 176,
          child: Column(
            children: [
              for (var row = 0; row < 2; row++) ...[
                if (row > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col > 0) const SizedBox(width: 8),
                      Expanded(child: _kindCell(OnboardingKind.values[row * 2 + col])),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        // Strings and frets: one card at 340 pt, rows 56 pt (+ divider).
        if (hasCard)
          Positioned(
            left: 24,
            right: 24,
            top: 340,
            child: Card(
              children: [
                if (range != null)
                  CardRow(
                    title: 'Число струн',
                    minHeight: 57,
                    trailing: ValueStepper(
                      value: '$strings',
                      canDecrement: strings > range.$1,
                      canIncrement: strings < range.$2,
                      valueMaxWidth: null,
                      decrement: () => setState(() {
                        strings--;
                        _pickFirstTemplate();
                      }),
                      increment: () => setState(() {
                        strings++;
                        _pickFirstTemplate();
                      }),
                    ),
                  ),
                if (fretOptions != null)
                  // The neck, positions and paths end at the guitar's last fret (user: «24 или 22 лада»).
                  CardRow(
                    title: 'Ладов',
                    minHeight: 57,
                    trailing: SizedBox(
                      width: 170,
                      child: Segments<int>(
                        options: [for (final f in fretOptions) (f, '$f')],
                        selection: frets,
                        onChanged: (f) => setState(() => frets = f),
                        size: SegmentsSize.compact,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // Tunings: at 476 pt down to 158 pt above the bottom, scrolling under a 44 pt fade.
        Positioned(
          left: 24,
          right: 24,
          top: listTop,
          height: (_fromBottom(686, h) - listTop).clamp(0.0, double.infinity),
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 44),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionCaption(text: _templateCaption),
                        Card(
                          children: [
                            for (final t in templates)
                              Pressable(
                                scale: 1,
                                selected: t['id'] == templateId,
                                onTap: () => setState(() => templateId = t['id'] as String),
                                child: _templateRow(t),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 44,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x000D0E10), Color(0xFF0C0D0F)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: _fromBottom(704, h),
          child: PrimaryButton(
            title: 'Продолжить',
            height: 52,
            maxWidth: null,
            onTap: () {
              app.replaceInstrument(templateId, fretCount: fretOptions == null ? null : frets);
              _go(2);
            },
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: _fromBottom(768, h),
          child: Pressable(
            scale: 1,
            onTap: () {
              app.replaceInstrument('g6-standard-e');
              _go(2);
            },
            child: Text(
              'Пропустить — гитара 6 струн, стандарт E',
              textAlign: TextAlign.center,
              style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  /// A tuning row of the canvas: min height 54 (+ divider), title 15 (semibold when chosen), notes 12, ivory check 20.
  Widget _templateRow(Map<String, dynamic> t) {
    final selected = t['id'] == templateId;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: rowDivider,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 55),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwiftText(
                      t['name'] as String,
                      style: Typo.inter(15, selected ? TypoWeight.semibold : TypoWeight.regular, TruverColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    SwiftText((t['notes'] as List).join(' '), style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                  ],
                ),
              ),
              // Green means only «в строю» (brand rule): the selection mark is ivory.
              if (selected) const AppIconView(AppIcon.check, size: 20, lineWidth: 2, color: TruverColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindCell(OnboardingKind k) {
    final selected = k == kind;
    return Pressable(
      selected: selected,
      onTap: () => setState(() {
        kind = k;
        final range = k.stringRange;
        if (range != null) strings = strings.clamp(range.$1, range.$2);
        _pickFirstTemplate();
      }),
      child: SizedBox(
        height: 72,
        child: ShapeBox(
          shape: const SwiftShape.rounded(16),
          fills: [SwiftFill(TruverColors.white(selected ? 0.1 : 0.04))],
          strokes: [SwiftStroke(selected ? const Color(0xB3F3EFE6) : TruverColors.hairline, inside: true)],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17), // border 1 + padding 16
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SwiftText(k.title, style: Typo.inter(16, TypoWeight.semibold, TruverColors.textPrimary)),
                ),
                const SizedBox(height: 3),
                SwiftText(k.subtitle, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: Step 2 → 3

  Widget _microphone(double h) {
    final app = AppScope.read(context);
    return Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 170,
          child: Center(
            child: MiniBezel(
              size: 200,
              child: AppIconView(AppIcon.mic, size: 56, lineWidth: 1.2, color: TruverColors.textPrimary),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: 420,
          child: Column(
            children: [
              Text(
                'Зачем микрофон',
                textAlign: TextAlign.center,
                style: Typo.inter(28, TypoWeight.light, TruverColors.textPrimary),
              ),
              // − 1: SkParagraph sets the first line of a line-spaced paragraph 1 pt lower than WebKit / SwiftUI (measured).
              const SizedBox(height: 12 + (15 * 1.5 - 15 * interLineHeight) / 2 - 1),
              // 15 pt, line height 1.5
              Text(
                'Микрофон нужен только тюнеру и проверке игры. Звук обрабатывается на телефоне — не записывается и никуда не отправляется.',
                textAlign: TextAlign.center,
                textHeightBehavior: swiftLineSpacing,
                style: lineSpaced(
                  Typo.inter(15, TypoWeight.regular, TruverColors.textSecondary),
                  15 * 1.5 - 15 * interLineHeight,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: _fromBottom(740, h),
          child: PrimaryButton(
            title: 'Продолжить',
            height: 56,
            maxWidth: null,
            onTap: () async {
              await app.audio.requestMicPermission();
              app.updateSettings((s) {
                s.onboarded = true;
                s.lastTab = AppTab.tuner;
              });
              CoachCenter.instance.arm(); // the hints of «Знакомство и обучение» start now
              app.showOnboarding = false;
            },
          ),
        ),
      ],
    );
  }
}

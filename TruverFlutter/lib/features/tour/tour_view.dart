/// Port of Truver/Sources/Features/Tour/TourView.swift
///
/// «Знакомство» (canvas Tour1Tuner … Tour4Practice): four cards after the welcome screen, before the instrument.
/// «N из 4» and «Пропустить» at the top (none on the last card), a 280 × 420 miniature of the screen at 104 (radius 30,
/// white 10 % border, shadow `0 24px 60px` black 55 %), the title 26 semibold and the text 15 / 1.5 at 552, the dots
/// and the 56 pt button 128 pt above the bottom. Steps slide left 320 ms (ease-out), the dots stretch in 200 ms.
///
/// The miniatures are the canvas renders of the boards' inner screens (`assets/tour/*.jpg`, 3×, the same files as
/// iOS): the tour shows the app before an instrument is chosen, with the canvas's sample states, so pictures.
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/components.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';

enum TourMode {
  /// After the welcome screen: the last card leads to the instrument.
  firstRun,

  /// Settings → «Обучение» → «Знакомство с приложением».
  replay,
}

class TourPage {
  const TourPage(this.image, this.title, this.text);
  final String image;
  final String title;
  final String text;
}

const tourPages = [
  TourPage('tour-tuner', 'Настройте гитару за минуту',
      'Сыграйте струну — Truver покажет ноту и подскажет, подтянуть её или ослабить. Для 6, 7, 8 и 9 струн и любого строя'),
  TourPage('tour-fret', 'Гаммы и аккорды на вашем грифе',
      'Выберите гамму — её ноты появятся на всех ладах, сразу в вашем строе. Нажмите на ноту, чтобы построить от неё аккорд или прогрессию'),
  TourPage('tour-metro', 'Метроном, с которым растёт темп',
      'Сам поднимает скорость, умеет пропускать доли и подсказывает, где вы спешите или отстаёте'),
  TourPage('tour-practice', 'Прогресс считается сам',
      'Минуты, дни подряд и ваш потолок темпа. Бесплатно, без регистрации и рекламы, звук не записывается'),
];

/// The decoded miniatures (tests: `await t.runAsync(TourImages.load)` before pumping).
abstract final class TourImages {
  static final images = ValueNotifier<Map<String, ui.Image>>({});
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    final out = <String, ui.Image>{};
    for (final p in tourPages) {
      try {
        final data = await rootBundle.load('assets/tour/${p.image}.jpg');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        out[p.image] = (await codec.getNextFrame()).image;
      } catch (_) {
        // Without the picture the frame stays empty.
      }
    }
    images.value = out;
  }
}

class TourView extends StatefulWidget {
  const TourView({super.key, required this.mode, this.page = 0, required this.finish});
  final TourMode mode;
  final int page;
  final VoidCallback finish;

  @override
  State<TourView> createState() => _TourViewState();
}

class _TourViewState extends State<TourView> {
  late int page = widget.page.clamp(0, tourPages.length - 1);
  bool forward = true;

  bool get isLast => page == tourPages.length - 1;

  @override
  void initState() {
    super.initState();
    TourImages.load();
  }

  void _go(int next) => setState(() {
        forward = next > page;
        page = next;
      });

  @override
  Widget build(BuildContext context) {
    final reduce = Motion.reduced(context);
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200 && !isLast) _go(page + 1);
          if (v > 200 && page > 0) _go(page - 1);
        },
        child: Stack(
          children: [
            const Positioned.fill(child: ScreenBackground()),
            Positioned.fill(
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: reduce ? Motion.base : Motion.move,
                  switchInCurve: Motion.out,
                  switchOutCurve: Motion.out,
                  layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                  transitionBuilder: (child, animation) {
                    if (reduce) return FadeTransition(opacity: animation, child: child);
                    final entering = (child.key as ValueKey<int>).value == page;
                    final dir = forward ? 1.0 : -1.0;
                    final begin = Offset(entering ? dir : -dir, 0);
                    return SlideTransition(position: Tween(begin: begin, end: Offset.zero).animate(animation), child: child);
                  },
                  child: KeyedSubtree(key: ValueKey(page), child: _card(tourPages[page], w)),
                ),
              ),
            ),
            Positioned(left: 20, width: w - 40, top: 50, child: _header()),
            Positioned(
              left: 20,
              width: w - 40,
              top: h - (844 - 716),
              child: Column(
                children: [
                  _dots(),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    title: isLast ? (widget.mode == TourMode.firstRun ? 'Выбрать инструмент' : 'Готово') : 'Дальше',
                    height: 56,
                    maxWidth: null,
                    onTap: () => isLast ? widget.finish() : _go(page + 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// «1 из 4» 13 tertiary · «Пропустить» 15 secondary (padding 10 0 10 20) in a 44 pt row.
  Widget _header() => SizedBox(
        height: 44,
        child: Row(
          children: [
            Text('${page + 1} из ${tourPages.length}', style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary)),
            const Spacer(),
            if (!isLast)
              Pressable(
                scale: 1,
                label: 'Пропустить',
                onTap: widget.finish,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 0, 10),
                  child: Text('Пропустить', style: Typo.inter(15, TypoWeight.regular, TruverColors.textSecondary)),
                ),
              ),
          ],
        ),
      );

  /// Dots: the current 18 × 6 ivory, the others 6 × 6 white 20 %, 6 apart.
  Widget _dots() => ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < tourPages.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Motion.out,
                width: i == page ? 18 : 6,
                height: 6,
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: i == page ? TruverColors.textPrimary : TruverColors.white(0.2),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _card(TourPage p, double w) {
    const spacing = 15 * 1.5 - 15 * interLineHeight;
    return Stack(
      children: [
        Positioned(left: (w - 280) / 2, top: 104, width: 280, height: 420, child: TourMiniature(image: p.image)),
        // Title 26 semibold (−0.02 em, normal line height) and the text 15 / 1.5, 10 apart, centred in 334.
        Positioned(
          left: 28,
          width: w - 56,
          top: 552,
          child: Column(
            children: [
              SwiftText(
                p.title,
                textAlign: TextAlign.center,
                style: Typo.inter(26, TypoWeight.semibold, TruverColors.textPrimary).copyWith(letterSpacing: -0.52),
              ),
              // − 1: SkParagraph sets the first line of a line-spaced paragraph 1 pt lower than WebKit / SwiftUI (measured).
              const SizedBox(height: 10 + spacing / 2 - 1),
              Text(
                p.text,
                textAlign: TextAlign.center,
                textHeightBehavior: swiftLineSpacing,
                style: lineSpaced(Typo.inter(15, TypoWeight.regular, TruverColors.textSecondary), spacing),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The miniature of a screen in its rounded frame.
class TourMiniature extends StatelessWidget {
  const TourMiniature({super.key, required this.image});
  final String image;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ShapeBox(
          shape: const SwiftShape.rounded(30),
          shadows: [SwiftShadow(TruverColors.black(0.55), 30, y: 24)],
          fills: const [SwiftFill(Color(0xFF0D0E10))],
          strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(29),
              child: ValueListenableBuilder(
                valueListenable: TourImages.images,
                builder: (context, images, _) => images[image] == null
                    ? const SizedBox.expand()
                    : RawImage(image: images[image], width: 278, height: 418, fit: BoxFit.fill, filterQuality: FilterQuality.high),
              ),
            ),
          ),
        ),
      );
}

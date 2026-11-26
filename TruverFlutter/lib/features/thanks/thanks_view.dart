/// Port of Truver/Sources/Features/Thanks/ThanksView.swift
///
/// «Спасибо» (canvas ThanksMusicians / ThanksPartners / ThanksOffline / ThanksLargeText): people who tell about Truver,
/// with their links. Real people only (`thanks.json`); the «Партнёры» segment appears once there are partners.
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../root/root_view.dart' show isAccessibilityTextSize;
import 'svg_path.dart';
import 'thanks_art.dart';
import 'thanks_chrome.dart';
import 'thanks_model.dart';

enum _Tab { musicians, partners }

class ThanksView extends StatefulWidget {
  const ThanksView({super.key, required this.back});
  final VoidCallback back;

  @override
  State<ThanksView> createState() => _ThanksViewState();
}

class _ThanksViewState extends State<ThanksView> {
  _Tab _tab = _Tab.musicians;
  ThanksPerson? _profile;
  String? _profileId;

  @override
  void initState() {
    super.initState();
    // Screenshot hooks: `-thanksTab partners`, `-thanksProfile <id>`.
    final args = AppScope.read(context).args;
    if (args.value('-thanksTab') == 'partners') _tab = _Tab.partners;
    _profileId = args.value('-thanksProfile');
    final data = ThanksData.instance;
    data.load();
    data.loaded.addListener(_loaded);
    _loaded();
  }

  void _loaded() {
    if (!ThanksData.instance.loaded.value || !mounted) return;
    setState(() {
      if (_profileId != null) {
        _profile = ThanksData.instance.person(_profileId!);
        _profileId = null;
      }
    });
  }

  @override
  void dispose() {
    ThanksData.instance.loaded.removeListener(_loaded);
    super.dispose();
  }

  List<ThanksPerson> get _people {
    final data = ThanksData.instance;
    return _tab == _Tab.partners && data.partners.isNotEmpty ? data.partners : data.musicians;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final large = isAccessibilityTextSize(context);
    final offline = UpdateCenter.of(AppScope.read(context)).offlineSince;
    return Stack(children: [
      const Positioned.fill(child: ScreenBackground()),
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.only(top: padding.top),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (large)
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 3),
                child: SizedBox(
                  height: 44,
                  child: Row(children: [
                    Semantics(
                      header: true,
                      child: Text('Спасибо', textScaler: TextScaler.noScaling, style: Typo.fixed(34, TypoWeight.bold, TruverColors.textPrimary)),
                    ),
                    const Spacer(),
                    RoundIconButton(icon: AppIcon.close, iconSize: 16, label: 'Назад', onTap: widget.back),
                  ]),
                ),
              )
            else
              ThanksHeader(title: 'Спасибо', back: widget.back),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(left: 20, right: 20, bottom: (offline != null ? 60 : 40) + padding.bottom),
                  // The large-text board is laid out at its own fixed sizes (iOS `Typo.fixed`).
                  child: large ? MediaQuery.withNoTextScaling(child: _largeList()) : _list(),
                ),
              ),
            ),
          ]),
        ),
      ),
      if (offline != null)
        Positioned(
          left: 20,
          right: 20,
          bottom: 844 - 806 - 32.5, // canvas: top 806 of 844
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color.fromRGBO(30, 31, 35, 0.98),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TruverColors.white(0.12)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
              child: Row(children: [
                const AppIconView(AppIcon.warning, size: 14, color: TruverColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: SwiftText('Нет интернета · показан список от ${UpdateCenter.dayMonth(offline)}',
                      maxLines: 1, style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
                ),
              ]),
            ),
          ),
        ),
      Positioned.fill(
        child: ThanksSheetHost<ThanksPerson>(
          item: _profile,
          dismiss: () => setState(() => _profile = null),
          builder: (context, person) => ThanksProfileSheet(person: person, close: () => setState(() => _profile = null)),
        ),
      ),
    ]);
  }

  Widget _list() {
    final data = ThanksData.instance;
    final people = _people;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14), // 108 from the top of the screen
      Row(children: [
        const ThanksPick(size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwiftText('Спасибо, что рассказываете о Truver', style: Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary)),
            const SizedBox(height: 2),
            SwiftText('Растём только благодаря вам', style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
          ]),
        ),
      ]),
      if (data.partners.isNotEmpty) ...[
        const SizedBox(height: 18), // 166
        Segments<_Tab>(
          options: [(_Tab.musicians, 'Музыканты ${data.musicians.length}'), (_Tab.partners, 'Партнёры ${data.partners.length}')],
          selection: _tab,
          onChanged: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 12), // 216
      ] else
        const SizedBox(height: 18),
      for (final (i, person) in people.indexed) ...[
        Pressable(scale: 0.98, onTap: () => setState(() => _profile = person), label: person.name, child: _card(person, i)),
        const SizedBox(height: 8),
      ],
      _tellUs(),
    ]);
  }

  /// A card 92 pt: avatar 48 with the gold badge, name 15 semibold, who it is 12, platform tiles 22.
  Widget _card(ThanksPerson person, int index) => SizedBox(
        height: 92,
        child: ShapeBox(
          shape: const SwiftShape.rounded(18),
          fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(children: [
              ThanksAvatar(person: person, index: index),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  SwiftText(person.name, maxLines: 1, style: Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary)),
                  const SizedBox(height: 2),
                  SwiftText(person.subtitle, maxLines: 1, softWrap: false, overflow: TextOverflow.clip,
                      style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
                  if (person.links.isNotEmpty) ...[
                    const SizedBox(height: 6), // gap 2 + margin-top 4
                    Row(children: [
                      for (final (i, link) in person.links.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        PlatformTile(kind: link.kind),
                      ],
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: 14),
              const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
            ]),
          ),
        ),
      );

  /// «Рассказали о Truver? Добавим вас и ваши ссылки · Написать» in a dashed gold frame.
  Widget _tellUs() => CustomPaint(
        foregroundPainter: _DashedBorder(ThanksColors.goldA(0.35), 18),
        child: DecoratedBox(
          decoration: BoxDecoration(color: ThanksColors.goldA(0.04), borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(children: [
              const ThanksPick(size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SwiftText('Рассказали о Truver?', style: Typo.inter(14, TypoWeight.semibold, TruverColors.textPrimary)),
                  const SizedBox(height: 3),
                  SwiftText('Добавим вас и ваши ссылки', style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
                ]),
              ),
              const SizedBox(width: 12),
              GraphiteCapsuleButton(title: 'Написать', onTap: () => openExternal(UpdateCenter.feedbackUrl)),
            ]),
          ),
        ),
      );

  /// Large text (canvas ThanksLargeText): cards in a column — avatar 56 and name 24, who it is 19, tiles 40.
  Widget _largeList() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 22), // 116 from the top of the screen
        for (final (i, person) in _people.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          Pressable(
            scale: 0.98,
            onTap: () => setState(() => _profile = person),
            label: person.name,
            child: ShapeBox(
              shape: const SwiftShape.rounded(18),
              fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
              strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ThanksAvatar(person: person, size: 56, font: 19, badge: 22, badgeGlyph: 16, index: i),
                    const SizedBox(width: 14),
                    Flexible(
                      child: SwiftText(person.name, style: Typo.fixed(24, TypoWeight.semibold, TruverColors.textPrimary)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: (19 * 1.35 - 23.01) / 2),
                    child: SwiftText(person.subtitle,
                        lineSpacing: 19 * 1.35 - 23.01, style: Typo.fixed(19, TypoWeight.regular, TruverColors.textSecondary)),
                  ),
                  if (person.links.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      for (final (j, link) in person.links.indexed) ...[
                        if (j > 0) const SizedBox(width: 8),
                        PlatformTile(kind: link.kind, size: 40, radius: 11, glyph: 27),
                      ],
                    ]),
                  ],
                ]),
              ),
            ),
          ),
        ],
      ]);
}

/// CSS `border: 1px dashed` of the «Рассказали о Truver?» card: 3 pt dashes, 3 pt gaps.
class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius - 0.5)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// «Музыкант» / «Партнёр» (canvas ThanksProfile): avatar 64, name 20, what we thank for, links as 56 pt rows.
class ThanksProfileSheet extends StatelessWidget {
  const ThanksProfileSheet({super.key, required this.person, required this.close});
  final ThanksPerson person;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    const extra = 14 * 1.4 - 16.95; // CSS line-height 1.4 over Inter 14
    return ThanksSheetPanel(
      title: person.kind == null ? 'Музыкант' : 'Партнёр',
      height: 544,
      close: close,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ThanksAvatar(person: person, size: 64, font: 22, badge: 26, badgeGlyph: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwiftText(person.name, style: Typo.inter(20, TypoWeight.semibold, TruverColors.textPrimary)),
              const SizedBox(height: 3),
              SwiftText(person.subtitle, style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary)),
            ]),
          ),
        ]),
        if (person.thanks != null) ...[
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: ThanksColors.goldA(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ThanksColors.goldA(0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
              child: Row(children: [
                const ThanksPick(size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: extra / 2),
                    child: SwiftText(person.thanks!, lineSpacing: extra, style: Typo.inter(14, TypoWeight.regular, TruverColors.textBody)),
                  ),
                ),
              ]),
            ),
          ),
        ],
        if (person.links.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(children: [
            for (final link in person.links)
              Pressable(
                scale: 1,
                onTap: () => openExternal(link.url),
                label: '${link.platform} ${link.displayHandle}',
                child: _linkRow(link),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        SwiftText('Ссылки открываются в приложении площадки или в браузере',
            style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
      ]),
    );
  }

  Widget _linkRow(ThanksLink link) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: TruverColors.white(0.06)))),
        child: SizedBox(
          height: 57, // 56 + the bottom border
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              PlatformTile(kind: link.kind, size: 32, radius: 9, glyph: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SwiftText(link.platform, style: Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
                  const SizedBox(height: 1),
                  SwiftText(link.displayHandle, style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
                ]),
              ),
              const SizedBox(width: 12),
              const SvgGlyph('M9 6h9v9M18 6L7 17', size: 14, color: TruverColors.textTertiary, stroke: 2, cap: StrokeCap.round),
            ]),
          ),
        ),
      );
}

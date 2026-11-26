/// Port of Truver/Sources/Features/Thanks/ThanksArt.swift
///
/// Drawings of the «Спасибо · обновления» page: platform tiles, the gold plectrum, avatars with badges, the app icon,
/// capsule buttons.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../design/components.dart';
import '../../design/shapes.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'svg_path.dart';
import 'thanks_model.dart';

/// Colours of the page (canvas): the gold of thanks and of the update banner.
abstract final class ThanksColors {
  static const gold = Color(0xFFE8B54A);
  static const goldTop = Color(0xFFF3CF7A);
  static const goldBottom = Color(0xFFC98D22);
  static const ink = Color(0xFF16171A);
  static const badgeRing = Color(0xFF15161A);
  static Color goldA(double a) => gold.withValues(alpha: a);

  /// Initials avatars without a photo (canvas palette).
  static const avatarPalette = [
    (Color(0xFF6A5ACD), Color(0xFF2C2650)),
    (Color(0xFF3F8F7A), Color(0xFF1B3A33)),
    (Color(0xFFB0624A), Color(0xFF4A2A20)),
    (Color(0xFF8A7A3A), Color(0xFF3A3418)),
    (Color(0xFF4A74B0), Color(0xFF1E2F4A)),
  ];
  static const partnerPalette = [
    (Color(0xFF5B6470), Color(0xFF22262C)),
    (Color(0xFF7A5A3A), Color(0xFF2E2216)),
    (Color(0xFF6B3F5F), Color(0xFF2A1826)),
    (Color(0xFF3F6B6B), Color(0xFF182A2A)),
  ];
}

/// CSS `linear-gradient(<angle>deg, …)` over a box with `aspect` = w / h.
LinearGradient cssLinearGradient(double degrees, List<Color> colors, {List<double>? stops, double aspect = 1}) {
  final a = degrees * math.pi / 180;
  final dx = math.sin(a), dy = -math.cos(a);
  final half = (dx.abs() * aspect + dy.abs()) / 2;
  final sx = dx * half / aspect, sy = dy * half;
  return LinearGradient(
    begin: Alignment(-sx * 2, -sy * 2),
    end: Alignment(sx * 2, sy * 2),
    colors: colors,
    stops: stops,
  );
}

LinearGradient _g160(int a, int b) => cssLinearGradient(160, [Color(a), Color(b)]);

// MARK: - Platform tiles

/// A platform tile (canvas «Плитки площадок»): sizes 22 / 32 / 40 / 58, radii 6 / 9 / 11 / 16, glyphs 15 / 22 / 27 / 39.
class PlatformTile extends StatelessWidget {
  const PlatformTile({super.key, required this.kind, this.size = 22, this.radius = 6, this.glyph = 15});
  final LinkKind kind;
  final double size;
  final double radius;
  final double glyph;

  static LinearGradient background(LinkKind kind) => switch (kind) {
        LinkKind.youtube => _g160(0xFFFF4B42, 0xFFD7140F),
        LinkKind.instagram => cssLinearGradient(
            45,
            const [Color(0xFFF7B13A), Color(0xFFE8423F), Color(0xFFC22F8F), Color(0xFF7B3FD1)],
            stops: const [0, 0.4, 0.7, 1],
          ),
        LinkKind.tiktok => _g160(0xFF222429, 0xFF0B0C0E),
        LinkKind.telegram => _g160(0xFF37B9F5, 0xFF1D93D2),
        LinkKind.spotify => _g160(0xFF2BD46A, 0xFF149A46),
        LinkKind.site => _g160(0xFF6B7380, 0xFF3D434C),
      };

  @override
  Widget build(BuildContext context) => Semantics(
        label: ThanksLink.platformName(kind),
        child: SizedBox(
          width: size,
          height: size,
          child: ShapeBox(
            shape: SwiftShape.rounded(radius),
            fills: [SwiftFill.gradient(background(kind))],
            strokes: [SwiftStroke(TruverColors.white(0.14), inside: true)],
            child: Center(child: PlatformGlyph(kind: kind, size: glyph)),
          ),
        ),
      );
}

/// The white glyph of a platform on the canvas 24 × 24 grid.
class PlatformGlyph extends StatelessWidget {
  const PlatformGlyph({super.key, required this.kind, required this.size});
  final LinkKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _GlyphPainter(kind))),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind);
  final LinkKind kind;

  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.save();
    canvas.scale(k);
    Paint stroke(Color c, double w, {StrokeCap cap = StrokeCap.butt}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = cap
      ..color = c
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = _white
      ..isAntiAlias = true;
    switch (kind) {
      case LinkKind.youtube:
        canvas.drawPath(parseSvgPath('M9 7.2v9.6c0 .6.6.9 1.1.6l7.4-4.8c.5-.3.5-1 0-1.3L10.1 6.6C9.6 6.3 9 6.6 9 7.2z'), fill);
      case LinkKind.instagram:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(4, 4, 16, 16), const Radius.circular(5)), stroke(_white, 2));
        canvas.drawCircle(const Offset(12, 12), 3.6, stroke(_white, 2));
        canvas.drawCircle(const Offset(16.9, 7.1), 1.2, fill);
      case LinkKind.tiktok:
        final note = parseSvgPath('M13.5 4v10.2a3.3 3.3 0 1 1-2.6-3.2');
        canvas.drawPath(note.shift(const Offset(-0.8, -0.6)), stroke(const Color(0xFF25F4EE), 2.2, cap: StrokeCap.round));
        canvas.drawPath(note.shift(const Offset(0.8, 0.6)), stroke(const Color(0xFFFE2C55), 2.2, cap: StrokeCap.round));
        canvas.drawPath(parseSvgPath('M13.5 4v10.2a3.3 3.3 0 1 1-2.6-3.2M13.5 4c.4 2.3 2 3.8 4.3 4'), stroke(_white, 2.2, cap: StrokeCap.round));
      case LinkKind.telegram:
        canvas.drawPath(
            parseSvgPath(
                'M4.5 11.4l13.6-5.3c.7-.3 1.3.2 1.1 1l-2.3 10.9c-.2.8-.8 1-1.4.6l-3.6-2.7-1.8 1.7c-.2.2-.4.3-.7.3l.3-3.7 6.6-6c.3-.3-.1-.4-.4-.2l-8.2 5.2-3.5-1.1c-.8-.2-.8-.8.3-1.2z'),
            fill);
      case LinkKind.spotify:
        canvas.drawPath(parseSvgPath('M6.5 9.3c3.8-1.2 8.1-.9 11 .8M7.2 12.6c3.1-.9 6.4-.6 8.9.7M7.9 15.7c2.4-.6 4.8-.4 6.7.6'),
            stroke(const Color(0xFF0B0C0E), 2, cap: StrokeCap.round));
      case LinkKind.site:
        canvas.drawCircle(const Offset(12, 12), 8, stroke(_white, 1.7));
        canvas.drawPath(parseSvgPath('M4 12h16M12 4c2.4 2.4 2.4 13.6 0 16M12 4c-2.4 2.4-2.4 13.6 0 16'), stroke(_white, 1.7));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind;
}

// MARK: - The gold plectrum

/// The gold plectrum with a heart (`viewBox 0 0 56 56`, gradient #f3cf7a → #c98d22 over the pick's box).
class ThanksPick extends StatelessWidget {
  const ThanksPick({super.key, this.size = 30});
  final double size;

  static const outline = 'M28 4C40 4 50 9 50 19c0 13-12 27-19.5 32.5a4.2 4.2 0 0 1-5 0C18 46 6 32 6 19 6 9 16 4 28 4z';
  static const heart =
      'M28 34.5s-9.5-5.6-9.5-12.2c0-3.1 2.3-5.3 5.1-5.3 2 0 3.5 1.1 4.4 2.6.9-1.5 2.4-2.6 4.4-2.6 2.8 0 5.1 2.2 5.1 5.3 0 6.6-9.5 12.2-9.5 12.2z';

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(fit: StackFit.expand, children: [
            SvgGlyph(
              outline,
              viewBox: 56,
              // objectBoundingBox of the outline: x 6…50, y 4…~52.4 (of 56).
              gradient: LinearGradient(
                begin: Alignment(6 / 56 * 2 - 1, 4 / 56 * 2 - 1),
                end: Alignment(50 / 56 * 2 - 1, 52.4 / 56 * 2 - 1),
                colors: const [ThanksColors.goldTop, ThanksColors.goldBottom],
              ),
            ),
            const SvgGlyph(heart, viewBox: 56, color: ThanksColors.ink),
          ]),
        ),
      );
}

// MARK: - Avatars

/// The gold badge on an avatar: a heart for musicians, the partner's kind for partners. Gold disc 19 / 22 / 26 pt in a
/// 2 pt dark ring outside it (CSS content-box: 23 / 26 / 30 in all).
class ThanksBadge extends StatelessWidget {
  const ThanksBadge({super.key, this.kind, this.size = 19, this.glyph = 13});
  final PartnerKind? kind;
  final double size;
  final double glyph;

  @override
  Widget build(BuildContext context) {
    final w = 2.0;
    final Widget mark = switch (kind) {
      null => const SvgGlyph(
          'M12 3.5c3.6 0 6.5 1.5 6.5 4.4 0 3.9-3.6 8.4-5.7 10.4a1.2 1.2 0 0 1-1.6 0C9.1 16.3 5.5 11.8 5.5 7.9c0-2.9 2.9-4.4 6.5-4.4z',
          color: ThanksColors.ink),
      PartnerKind.school =>
        SvgGlyph('M3 9.5L12 5l9 4.5-9 4.5z M7 11.6v3.6c0 1.3 2.2 2.6 5 2.6s5-1.3 5-2.6v-3.6', color: ThanksColors.ink, stroke: w, join: StrokeJoin.round),
      PartnerKind.shop => SvgGlyph('M6 8h12l-1 11H7z M9 8V6.5a3 3 0 0 1 6 0V8', color: ThanksColors.ink, stroke: w, join: StrokeJoin.round),
      PartnerKind.festival => const SvgGlyph('M12 4l2.3 4.8 5.2.7-3.8 3.6.9 5.2L12 15.8l-4.6 2.5.9-5.2-3.8-3.6 5.2-.7z', color: ThanksColors.ink),
      PartnerKind.channel => SvgGlyph('M5 10v4h3l6 4V6l-6 4z M17 9.5c1 1.4 1 3.6 0 5',
          color: ThanksColors.ink, stroke: w, cap: StrokeCap.round, join: StrokeJoin.round),
    };
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: ThanksColors.badgeRing, shape: BoxShape.circle),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: cssLinearGradient(160, const [ThanksColors.goldTop, ThanksColors.goldBottom]),
            ),
            child: Center(child: SizedBox(width: glyph, height: glyph, child: mark)),
          ),
        ),
      ),
    );
  }
}

/// A person's avatar: the downscaled whole photo aspect-filling a circle (never a cropped file), or initials on the
/// canvas gradient; partners get a rounded square (radius 13 of 48). Optional gold badge at the bottom-right (−3 pt).
class ThanksAvatar extends StatelessWidget {
  const ThanksAvatar({
    super.key,
    required this.person,
    this.size = 48,
    this.font = 16,
    this.badge = 19,
    this.badgeGlyph = 13,
    this.index = 0,
  });

  final ThanksPerson person;
  final double size;
  final double font;
  final double? badge;
  final double badgeGlyph;
  final int index;

  @override
  Widget build(BuildContext context) {
    final partner = person.kind != null;
    final shape = partner ? SwiftShape.rounded(size * 13 / 48) : SwiftShape.circle;
    final name = person.photoSmall ?? person.photo;
    final ui.Image? photo = name == null ? null : ThanksData.instance.photos[name];
    final palette = partner ? ThanksColors.partnerPalette : ThanksColors.avatarPalette;
    final colors = palette[index % palette.length];
    final face = ShapeBox(
      shape: shape,
      fills: photo == null
          ? [
              SwiftFill.gradient(RadialGradient(
                center: const Alignment(-0.4, -0.6),
                radius: 1.2,
                colors: [colors.$1, colors.$2],
              )),
            ]
          : const [SwiftFill(Color(0xFF000000))],
      strokes: [SwiftStroke(TruverColors.white(0.16), inside: true)],
      shadows: [SwiftShadow(TruverColors.black(0.35), 8, y: 6)],
      clip: true,
      child: SizedBox(
        width: size,
        height: size,
        child: photo != null
            ? RawImage(image: photo, fit: BoxFit.cover, width: size, height: size, filterQuality: FilterQuality.medium)
            : Center(
                child: Text(
                  person.initials,
                  textScaler: TextScaler.noScaling,
                  style: Typo.fixed(font, TypoWeight.semibold, TruverColors.textPrimary).copyWith(letterSpacing: 0.02 * font),
                ),
              ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: face),
          if (badge != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: ThanksBadge(kind: person.kind, size: badge!, glyph: badgeGlyph),
            ),
        ]),
      ),
    );
  }
}

// MARK: - The app icon

/// The app icon as drawn on the canvas (About, update screens, share sheet).
class TruverAppIconArt extends StatelessWidget {
  const TruverAppIconArt({super.key, this.size = 96, this.radius = 21});
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ring = size * 71.25 / 96, face = size * 61.275 / 96;
    return Semantics(
      label: 'Значок Truver',
      child: SizedBox(
        width: size,
        height: size,
        child: ShapeBox(
          shape: SwiftShape.rounded(radius),
          fills: const [
            SwiftFill.gradient(RadialGradient(
              center: Alignment(0, -0.56),
              radius: 0.9,
              colors: [Color(0xFF2A2D33), Color(0xFF101114), Color(0xFF070708)],
              stops: [0, 0.6, 1],
            )),
          ],
          clip: true,
          child: Center(
            child: SizedBox(
              width: ring,
              height: ring,
              child: ShapeBox(
                shape: SwiftShape.circle,
                fills: const [SwiftFill.gradient(TruverGradients.metal)],
                shadows: [SwiftShadow(TruverColors.black(0.6), size * 2.8125 / 96, y: size * 2.8125 / 96)],
                child: Center(
                  child: SizedBox(
                    width: face,
                    height: face,
                    child: ShapeBox(
                      shape: SwiftShape.circle,
                      fills: const [
                        SwiftFill.gradient(RadialGradient(
                          center: Alignment(0, -0.24),
                          radius: 0.7965,
                          colors: [Color(0xFF1E2024), Color(0xFF0A0A0B)],
                          stops: [0, 0.7],
                        )),
                      ],
                      child: const CustomPaint(painter: _DialPainter(), size: Size.infinite),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    final c = Offset(50 * k, 50 * k);
    const rad = math.pi / 180;
    // inset 0 0.94 2.25 rgba(0,0,0,0.9) of the face (numbers for the 96 pt icon, whose face is 61.275).
    final px = size.width / 61.275;
    canvas.save();
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Rect.fromLTWH(-size.width, -size.height, 3 * size.width, 3 * size.height))
        ..addOval(Rect.fromLTWH(0, 0.9375 * px, size.width, size.height)),
      Paint()
        ..color = TruverColors.black(0.9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.125 * px),
    );
    canvas.restore();
    void arc(double r, double from, double to, Paint p) =>
        canvas.drawArc(Rect.fromCircle(center: c, radius: r * k), from * rad, (to - from) * rad, false, p);
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * k
      ..color = const Color.fromRGBO(233, 230, 223, 0.6);
    for (var i = 0; i < 24; i++) {
      final mid = -90.0 + i * 15;
      arc(44, mid - 0.35, mid + 0.35, tick);
    }
    final seg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5 * k
      ..color = TruverColors.inTune;
    for (var i = 0; i < 22; i++) {
      final start = -72.0 + i * 15;
      arc(32, start, start + 9, seg);
    }
    final fill = Paint()..color = TruverColors.inTune;
    canvas.drawPath(
        Path()
          ..moveTo(50 * k, 11.5 * k)
          ..lineTo(45.4 * k, 3.2 * k)
          ..lineTo(54.6 * k, 3.2 * k)
          ..close(),
        fill);
    final needle = RRect.fromRectAndRadius(Rect.fromLTWH(48 * k, 12.5 * k, 4 * k, 15 * k), Radius.circular(2 * k));
    canvas.drawRRect(needle, Paint()
      ..color = TruverColors.inTune
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.8 * k));
    canvas.drawRRect(needle, fill);
  }

  @override
  bool shouldRepaint(_DialPainter old) => false;
}

// MARK: - Buttons

/// Ivory capsule action (`linear-gradient(180deg, #f6f3ec, #d9d4c8)`, 15 semibold, padding 0 18).
class IvoryCapsuleButton extends StatelessWidget {
  const IvoryCapsuleButton({super.key, required this.title, this.height = 44, this.fullWidth = false, required this.onTap});
  final String title;
  final double height;
  final bool fullWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: Pressable(
          onTap: onTap,
          child: SizedBox(
            height: height,
            width: fullWidth ? double.infinity : null,
            child: ShapeBox(
              shape: SwiftShape.capsule,
              fills: const [SwiftFill.gradient(TruverGradients.primaryFill)],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  widthFactor: 1,
                  child: Text(title, maxLines: 1, style: Typo.inter(15, TypoWeight.semibold, TruverColors.background)),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Graphite capsule (card fill, 1 pt white 8 % border, 15 medium body).
class GraphiteCapsuleButton extends StatelessWidget {
  const GraphiteCapsuleButton({super.key, required this.title, this.height = 44, this.width, required this.onTap});
  final String title;
  final double height;
  final double? width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: Pressable(
          onTap: onTap,
          child: SizedBox(
            height: height,
            width: width,
            child: ShapeBox(
              shape: SwiftShape.capsule,
              fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
              strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  widthFactor: 1,
                  child: Text(title, maxLines: 1, style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody)),
                ),
              ),
            ),
          ),
        ),
      );
}

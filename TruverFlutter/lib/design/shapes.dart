/// SwiftUI shape modifiers in Flutter terms: `.background(Shape().fill(…))`, `.overlay(Shape().stroke(…))`,
/// `.overlay(Shape().strokeBorder(…))`, `.clipShape(…)` and `.shadow(color:radius:x:y:)` — painted exactly, so
/// widths, stroke positions and corner styles match the iOS app.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A SwiftUI shape: `Capsule()`, `Circle()`, `RoundedRectangle(cornerRadius:style:)`,
/// `UnevenRoundedRectangle(topLeadingRadius:topTrailingRadius:style: .continuous)`.
@immutable
class SwiftShape {
  const SwiftShape._(this._kind, [this.radius = 0, this.continuous = false]);

  /// `Capsule()` (circular ends).
  static const capsule = SwiftShape._(0);

  /// `Circle()` — the largest circle centred in the rect.
  static const circle = SwiftShape._(1);

  /// `RoundedRectangle(cornerRadius: r)` — `.circular` by default as in SwiftUI; `continuous: true` for
  /// `style: .continuous` (Apple's squircle corners ≈ Flutter's RSuperellipse).
  const SwiftShape.rounded(double radius, {bool continuous = false}) : this._(2, radius, continuous);

  /// `UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)` (sheet panels).
  const SwiftShape.topRounded(double radius, {bool continuous = true}) : this._(3, radius, continuous);

  final int _kind;
  final double radius;
  final bool continuous;

  /// The outline in `rect`, inset by `inset` points (positive — inwards, as `.inset(by:)` / `strokeBorder`).
  Path path(Rect rect, [double inset = 0]) {
    final r = rect.deflate(inset);
    if (r.width <= 0 || r.height <= 0) return Path();
    switch (_kind) {
      case 0:
        return Path()..addRSuperellipse(RSuperellipse.fromRectAndRadius(r, Radius.circular(math.min(r.width, r.height) / 2)));
      case 1:
        return Path()..addOval(Rect.fromCircle(center: r.center, radius: math.min(r.width, r.height) / 2));
      case 2:
        final rad = math.max(0.0, math.min(radius - inset, math.min(r.width, r.height) / 2));
        if (continuous) return Path()..addRSuperellipse(RSuperellipse.fromRectAndRadius(r, Radius.circular(rad)));
        return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(rad)));
      default:
        final rad = Radius.circular(math.max(0.0, math.min(radius - inset, math.min(r.width, r.height) / 2)));
        if (continuous) {
          return Path()..addRSuperellipse(RSuperellipse.fromRectAndCorners(r, topLeft: rad, topRight: rad));
        }
        return Path()..addRRect(RRect.fromRectAndCorners(r, topLeft: rad, topRight: rad));
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SwiftShape && other._kind == _kind && other.radius == radius && other.continuous == continuous;

  @override
  int get hashCode => Object.hash(_kind, radius, continuous);
}

/// `.shadow(color:radius:x:y:)`. SwiftUI's radius is the Gaussian blur's standard deviation in points.
@immutable
class SwiftShadow {
  const SwiftShadow(this.color, this.radius, {this.x = 0, this.y = 0});
  final Color color;
  final double radius;
  final double x;
  final double y;

  /// Sigma per SwiftUI radius point (tuned against simulator screenshots).
  static const sigmaPerRadius = 1.0;

  void paint(Canvas canvas, Path path) {
    canvas.drawPath(
      path.shift(Offset(x, y)),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.01, radius * sigmaPerRadius)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SwiftShadow && other.color == color && other.radius == radius && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(color, radius, x, y);
}

/// A stroke: `.stroke(…)` is centred on the outline (`inside: false`), `.strokeBorder(…)` lies inside it.
/// `trim` is SwiftUI's `.trim(from:to:)` (fractions of the outline, starting at 3 o'clock for circles).
@immutable
class SwiftStroke {
  const SwiftStroke(this.color, {this.width = 1, this.inside = false, this.gradient, this.inset = 0, this.trim});
  final Color color;
  final double width;
  final bool inside;
  final Gradient? gradient;

  /// `.inset(by:)` of the shape before stroking.
  final double inset;
  final (double, double)? trim;

  @override
  bool operator ==(Object other) =>
      other is SwiftStroke &&
      other.color == color &&
      other.width == width &&
      other.inside == inside &&
      other.gradient == gradient &&
      other.inset == inset &&
      other.trim == trim;

  @override
  int get hashCode => Object.hash(color, width, inside, gradient, inset, trim);
}

/// A fill layer: a colour or a gradient (gradients use the shape's bounds, like SwiftUI's unit points).
@immutable
class SwiftFill {
  const SwiftFill(this.color) : gradient = null;
  const SwiftFill.gradient(Gradient this.gradient) : color = const Color(0x00000000);
  final Color color;
  final Gradient? gradient;

  @override
  bool operator ==(Object other) => other is SwiftFill && other.color == color && other.gradient == gradient;

  @override
  int get hashCode => Object.hash(color, gradient);
}

class _ShapePainter extends CustomPainter {
  _ShapePainter({required this.shape, required this.fills, required this.strokes, required this.shadows, this.foreground = false});

  final SwiftShape shape;
  final List<SwiftFill> fills;
  final List<SwiftStroke> strokes;
  final List<SwiftShadow> shadows;
  final bool foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = shape.path(rect);
    if (!foreground) {
      for (final s in shadows) {
        s.paint(canvas, outline);
      }
      for (final f in fills) {
        // With a shader the paint colour's alpha still modulates it: keep it opaque for gradients.
        final paint = Paint()..color = f.gradient != null ? const Color(0xFF000000) : f.color;
        if (f.gradient != null) paint.shader = f.gradient!.createShader(rect);
        canvas.drawPath(outline, paint);
      }
      return;
    }
    for (final s in strokes) {
      final inset = s.inset + (s.inside ? s.width / 2 : 0);
      var path = shape.path(rect, inset);
      if (s.trim != null) path = _trim(path, s.trim!.$1, s.trim!.$2);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..color = s.gradient != null ? const Color(0xFF000000) : s.color;
      if (s.gradient != null) paint.shader = s.gradient!.createShader(rect);
      canvas.drawPath(path, paint);
    }
  }

  /// Circles in Flutter start at 3 o'clock going clockwise — the same as SwiftUI's `Circle().trim`.
  static Path _trim(Path path, double from, double to) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(metric.length * from, metric.length * to), Offset.zero);
    }
    return out;
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.shape != shape ||
      !_listEq(old.fills, fills) ||
      !_listEq(old.strokes, strokes) ||
      !_listEq(old.shadows, shadows) ||
      old.foreground != foreground;

  static bool _listEq(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A child with SwiftUI shape decoration: shadows and fills behind, strokes in front, optional clip.
class ShapeBox extends StatelessWidget {
  const ShapeBox({
    super.key,
    required this.shape,
    this.fills = const [],
    this.strokes = const [],
    this.shadows = const [],
    this.clip = false,
    this.child,
  });

  final SwiftShape shape;
  final List<SwiftFill> fills;
  final List<SwiftStroke> strokes;
  final List<SwiftShadow> shadows;

  /// `.clipShape(shape)` of the content (strokes are drawn after the clip, as with `.overlay` before
  /// `.clipShape` only the inner half of a centred stroke stays — use `inside: true` with half width for that).
  final bool clip;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget content = child ?? const SizedBox.shrink();
    if (clip) content = ClipPath(clipper: _ShapeClipper(shape), child: content);
    return CustomPaint(
      painter: _ShapePainter(shape: shape, fills: fills, strokes: strokes, shadows: shadows),
      foregroundPainter:
          strokes.isEmpty ? null : _ShapePainter(shape: shape, fills: fills, strokes: strokes, shadows: shadows, foreground: true),
      child: content,
    );
  }
}

class _ShapeClipper extends CustomClipper<Path> {
  _ShapeClipper(this.shape);
  final SwiftShape shape;

  @override
  Path getClip(Size size) => shape.path(Offset.zero & size);

  @override
  bool shouldReclip(_ShapeClipper old) => old.shape != shape;
}

/// Text with iOS line boxes.
///
/// Flutter's paragraph engine (SkParagraph) rounds every line's height to whole logical pixels and puts the
/// extra above the baseline: Inter 12 pt is 15 pt tall in Flutter but 14.52 pt in SwiftUI (17 pt: 21 vs 20.57).
/// SwiftUI instead rounds the frame up to whole device pixels (14.67 pt at 3×). In a stack of texts this drifts
/// by up to half a point per text. [SwiftText] reports SwiftUI's frame height (lines × 1.21 × size + spacing,
/// rounded up to device pixels); the glyphs stay where Flutter draws them (their first baseline already matches
/// iOS in the simulator comparisons). Use it where texts stack vertically (rows, captions, titles above content); a single line centred in
/// a fixed frame does not need it.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'components.dart' show interLineHeight;

class SwiftText extends StatelessWidget {
  const SwiftText(this.data, {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.softWrap, this.lineSpacing = 0})
      : span = null;

  const SwiftText.rich(InlineSpan this.span, {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.softWrap, this.lineSpacing = 0})
      : data = null;

  final String? data;
  final InlineSpan? span;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  /// SwiftUI `.lineSpacing(x)`; the style must not set `height` then (it is computed here).
  final double lineSpacing;

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final size = MediaQuery.textScalerOf(context).scale(effective.fontSize ?? 14);
    final natural = interLineHeight * size;
    final textStyle = lineSpacing == 0
        ? style
        : (style ?? const TextStyle()).copyWith(
            height: (natural + lineSpacing) / size * (effective.fontSize ?? 14) / (effective.fontSize ?? 14),
            leadingDistribution: TextLeadingDistribution.even);
    final text = span != null
        ? Text.rich(span!, style: textStyle, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap,
            textWidthBasis: TextWidthBasis.longestLine,
            textHeightBehavior: lineSpacing == 0 ? null : const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false))
        : Text(data!, style: textStyle, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap,
            textWidthBasis: TextWidthBasis.longestLine,
            textHeightBehavior: lineSpacing == 0 ? null : const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false));
    return _LineBoxFix(natural: natural, spacing: lineSpacing, child: text);
  }
}

class _LineBoxFix extends SingleChildRenderObjectWidget {
  const _LineBoxFix({required this.natural, required this.spacing, required super.child});
  final double natural;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLineBoxFix(natural, spacing)..pixelRatio = MediaQuery.devicePixelRatioOf(context);

  @override
  void updateRenderObject(BuildContext context, _RenderLineBoxFix renderObject) => renderObject
    ..natural = natural
    ..spacing = spacing
    ..pixelRatio = MediaQuery.devicePixelRatioOf(context);
}

class _RenderLineBoxFix extends RenderProxyBox {
  _RenderLineBoxFix(this._natural, this._spacing);

  double _natural;
  set natural(double v) {
    if (v == _natural) return;
    _natural = v;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  /// Flutter's rounded line pitch for this text.
  double get _rounded => spacing0 ? _natural.roundToDouble() : (_natural + _spacing).roundToDouble();
  bool get spacing0 => _spacing == 0;

  /// Glyphs stay where Flutter puts them: measured against iOS, the first baseline already matches.
  double get _shift => 0;

  /// Device pixels per point; SwiftUI rounds text frames up to whole device pixels.
  double pixelRatio = 3;

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(constraints.loosen().copyWith(minWidth: constraints.minWidth), parentUsesSize: true);
    final pitch = _rounded;
    final firstLine = spacing0 ? pitch : _natural.roundToDouble();
    final lines = child.size.height <= firstLine + 0.5 ? 1 : 1 + ((child.size.height - firstLine) / pitch).round();
    final height = ((lines * _natural + (lines - 1) * _spacing) * pixelRatio - 0.01).ceilToDouble() / pixelRatio;
    size = constraints.constrain(Size(child.size.width, height));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final b = child?.getDistanceToActualBaseline(baseline);
    return b == null ? null : b - _shift;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset.translate(0, -_shift));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position.translate(0, _shift)) ?? false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.translateByDouble(0, -_shift, 0, 1);
}

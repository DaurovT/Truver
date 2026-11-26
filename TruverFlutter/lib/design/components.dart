/// Port of Truver/Sources/DesignSystem/Components.swift (and `PressableStyle` of Motion.swift)
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../app/app_model.dart';
import 'icons.dart';
import 'motion.dart';
import 'shapes.dart';
import 'swift_text.dart';
import 'theme.dart';
import 'typo.dart';

/// Button press feedback (motion spec: scale 96 % and slightly lighter while touched, `tick`). Port of
/// `PressableStyle`; `scale: 1` gives SwiftUI's `.buttonStyle(.plain)` (no feedback).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.enabled = true,
    this.label,
    this.selected = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool enabled;
  final String? label;
  final bool selected;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    Widget child = widget.child;
    if (widget.scale != 1) {
      child = AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: Motion.tick,
        curve: Motion.out,
        child: _pressed
            ? ColorFiltered(
                // `.brightness(0.06)`: + 0.06 on every colour channel.
                colorFilter: const ColorFilter.matrix([1, 0, 0, 0, 15.3, 0, 1, 0, 0, 15.3, 0, 0, 1, 0, 15.3, 0, 0, 0, 1, 0]),
                child: child,
              )
            : child,
      );
    }
    return Semantics(
      button: true,
      enabled: active,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: widget.label != null,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: active ? (_) => _set(true) : null,
        onTapUp: active ? (_) => _set(false) : null,
        onTapCancel: active ? () => _set(false) : null,
        onTap: active ? widget.onTap : null,
        child: child,
      ),
    );
  }
}

/// Round graphite button (settings, reference tone, ± tempo). Canvas: `radial-gradient(circle at 50% 35%, #26282c,
/// #141518)` (to the farthest corner), 1 pt border white 10 %, `0 8px 18px` shadow, inner top highlight. The button
/// takes exactly `size` in the layout, like the canvas; the touch area still reaches 44 × 44 around it ([TouchArea]).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 18,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final AppIcon icon;
  final double size;
  final double iconSize;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TouchArea(
          minimum: 44,
          child: Pressable(
            onTap: onTap,
            enabled: enabled,
            label: label,
            child: RoundButtonFace(size: size, child: Center(child: AppIconView(icon, size: iconSize))),
          ),
        ),
      );
}

/// The disc of the canvas round buttons (graphite face, hairline, inner top highlight, drop shadow).
class RoundButtonFace extends StatelessWidget {
  const RoundButtonFace({super.key, required this.size, this.child});
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: ShapeBox(
          shape: SwiftShape.circle,
          shadows: [SwiftShadow(TruverColors.black(0.6), 9, y: 8)],
          fills: const [
            // `circle at 50% 35%` reaches the farthest corner of the box: √(0.5² + 0.65²) · size = 0.82 · size.
            SwiftFill.gradient(RadialGradient(
              center: Alignment(0, -0.3),
              radius: 0.82,
              colors: [TruverColors.panelHigh, TruverColors.panel],
            )),
          ],
          strokes: [
            const SwiftStroke(TruverColors.hairlineStrong, inside: true),
            // inset 0 1px 0 rgba(255,255,255,0.08): a hairline of light on the top edge, inside the border.
            SwiftStroke(TruverColors.white(0.08), inset: 1, trim: (0.55, 0.95)),
          ],
          child: child,
        ),
      );
}

/// Extends the hit area of its child to at least `minimum` × `minimum` points without changing the layout (the
/// canvas lays out 36 and 40 pt buttons at their visual size). Touches outside the child are moved onto its edge.
/// Like SwiftUI, the extra area only works inside the parent's own bounds.
class TouchArea extends SingleChildRenderObjectWidget {
  const TouchArea({super.key, this.minimum = 44, super.child});
  final double minimum;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTouchArea(minimum);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderTouchArea).minimum = minimum;
}

class _RenderTouchArea extends RenderProxyBox {
  _RenderTouchArea(this.minimum);
  double minimum;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final dx = math.max(0.0, (minimum - size.width) / 2), dy = math.max(0.0, (minimum - size.height) / 2);
    final area = Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
    if (!area.contains(position) || child == null) return false;
    final inside = Offset(position.dx.clamp(0.0, math.max(0.0, size.width - 0.01)), position.dy.clamp(0.0, math.max(0.0, size.height - 0.01)));
    if (child!.hitTest(result, position: inside)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// Big ivory round button (start / stop: 88 pt, 100 pt with large text).
class PrimaryRoundButton extends StatelessWidget {
  const PrimaryRoundButton({super.key, required this.icon, this.size = 88, this.iconSize = 30, required this.label, required this.onTap});

  final AppIcon icon;
  final double size;
  final double iconSize;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        label: label,
        child: SizedBox(
          width: size,
          height: size,
          child: ShapeBox(
            shape: SwiftShape.circle,
            shadows: [SwiftShadow(TruverColors.black(0.6), 9, y: 8)],
            fills: const [SwiftFill.gradient(TruverGradients.primaryFill)],
            child: Center(child: AppIconView(icon, size: iconSize, color: TruverColors.background)),
          ),
        ),
      );
}

/// Small header chip ("Микрофон", preset name). Canvas: a `<span>` 32 pt high plus a 1 pt border outside it —
/// 34 pt in all, radius 16, padding 12, icon 14 (the metronome's chevron 12) and 6 pt gap, 12 medium.
class HeaderChip extends StatelessWidget {
  const HeaderChip({super.key, required this.text, this.icon, this.tint, this.iconSize = 14});

  final String text;
  final AppIcon? icon;
  final Color? tint;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: ShapeBox(
          shape: const SwiftShape.rounded(16),
          fills: [SwiftFill(tint?.withValues(alpha: tint!.a * 0.08) ?? TruverColors.fill)],
          strokes: [SwiftStroke(tint?.withValues(alpha: tint!.a * 0.45) ?? TruverColors.hairlineStrong, inside: true)],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[AppIconView(icon!, size: iconSize, color: tint ?? TruverColors.textTertiary), const SizedBox(width: 6)],
                Text(text, style: Typo.chip.copyWith(color: tint ?? TruverColors.textBody), maxLines: 1, softWrap: false),
              ],
            ),
          ),
        ),
      );
}

/// Ivory capsule for the main action of a state ("Включить микрофон", "Продолжить").
/// `maxWidth: null` stretches to the offered width (SwiftUI `.infinity`).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.title, this.icon, this.height = 50, this.maxWidth = 260, required this.onTap});

  final String title;
  final AppIcon? icon;
  final double height;
  final double? maxWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _IvoryCapsule(title: title, icon: icon, height: height, maxWidth: maxWidth, onTap: onTap);
}

class _IvoryCapsule extends StatelessWidget {
  const _IvoryCapsule({required this.title, this.icon, required this.height, this.maxWidth, this.onTap});

  final String title;
  final AppIcon? icon;
  final double height;
  final double? maxWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity, minHeight: height),
          child: Pressable(
            onTap: onTap,
            child: ShapeBox(
              shape: const SwiftShape.rounded(1000),
              fills: const [SwiftFill.gradient(TruverGradients.primaryFill)],
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[AppIconView(icon!, size: 18, color: TruverColors.background), const SizedBox(width: 8)],
                      Flexible(
                        child: Text(title, style: Typo.button.copyWith(color: TruverColors.background), textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Ivory action button of sheets and states (50 pt by default — the canvas sheet footers; full width). Port of `SheetButton` (Controls.swift).
class SheetButton extends StatelessWidget {
  const SheetButton({super.key, required this.title, this.icon, this.height = 50, required this.onTap});

  final String title;
  final AppIcon? icon;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _IvoryCapsule(title: title, icon: icon, height: height, onTap: onTap);
}

/// Segmented control (Авто / Ручной / Хром.) — the canvas tray: 30 pt segments (radius 15), padding 3, a 1 pt
/// border inside, radius 18 — 38 pt in all. Same as `Segments` at its regular size.
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({super.key, required this.options, required this.selection, required this.onChanged});

  final List<(T, String)> options;
  final T selection;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SegmentsBar<T>(options: options, selection: selection, onChanged: onChanged, height: 30);
}

/// The tray of [SegmentedPill] and `Segments`: padding 3 inside a 1 pt border (4 to the segments), card fill, radius
/// 18 (22 for 38 pt segments), ivory selection.
class SegmentsBar<T> extends StatelessWidget {
  const SegmentsBar({super.key, required this.options, required this.selection, required this.onChanged, required this.height, this.radius});

  final List<(T, String)> options;
  final T selection;
  final ValueChanged<T> onChanged;
  final double height;

  /// Tray corner radius; by default 18 for 30 pt segments and 22 for 38 pt ones (canvas).
  final double? radius;

  @override
  Widget build(BuildContext context) => ShapeBox(
        shape: SwiftShape.rounded(radius ?? (height > 30 ? 22 : 18)),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final (value, title) in options)
                Expanded(
                  child: Pressable(
                    scale: 1,
                    selected: value == selection,
                    onTap: () => onChanged(value),
                    child: _Segment(title: title, selected: value == selection, height: height),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _Segment extends StatelessWidget {
  const _Segment({required this.title, required this.selected, required this.height});
  final String title;
  final bool selected;
  final double height;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: selected ? 1 : 0),
        duration: Motion.quick,
        curve: Motion.out,
        builder: (context, t, _) => ShapeBox(
          shape: const SwiftShape.rounded(1000),
          fills: [SwiftFill(TruverColors.accent.withValues(alpha: t))],
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: (selected ? Typo.segmentSelected : Typo.segment)
                    .copyWith(color: Color.lerp(TruverColors.textSecondary, TruverColors.background, t)),
              ),
            ),
          ),
        ),
      );
}

/// Screen header of the canvas (`left 20, top 50, width 350`, a 44 pt row): title 26 semibold (−0.02 em, line
/// height 1.15) with an optional 12 pt subtitle under it, chips and the 40 pt settings button on the right, 8 apart.
/// On the reference phone the safe area ends at 47, so the row starts 3 pt below it.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.leading, this.trailing = const [], this.subtitle});

  final String title;
  final Widget? leading;

  /// Second line under the title (canvas «Гриф и гаммы» / «8-струнная · Стандарт F♯»): 12 pt, tertiary.
  final String? subtitle;

  /// Chips before the gear (8 pt apart).
  final List<Widget> trailing;

  static const topPadding = 3.0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: topPadding),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: OverflowBox(
                      maxHeight: double.infinity,
                      alignment: Alignment.centerLeft,
                      fit: OverflowBoxFit.deferToChild,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // CSS `line-height: 1.15`: a 29.9 pt line box with the natural 31.5 pt text line centred in it.
                          SizedBox(
                            height: 29.9,
                            child: OverflowBox(
                              maxHeight: double.infinity,
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                header: true,
                                child: Text(title,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: Typo.screenTitle.copyWith(color: TruverColors.textPrimary, letterSpacing: -0.52)),
                              ),
                            ),
                          ),
                          if (subtitle != null)
                            Text(subtitle!,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                        ],
                      ),
                    ),
                  ),
                  if (leading != null) ...[const SizedBox(width: 8), leading!],
                ],
              ),
            ),
            const SizedBox(width: 8),
            for (final t in trailing) ...[t, const SizedBox(width: 8)],
            RoundIconButton(icon: AppIcon.gear, label: 'Настройки', onTap: () => app.showSettings = true),
          ],
        ),
      ),
    );
  }
}

/// Card group with rows (lists in settings, journal, onboarding): optional 12 pt title, 16 pt continuous card.
class CardGroup extends StatelessWidget {
  const CardGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SwiftText(title!, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
            ),
            const SizedBox(height: 6),
          ],
          ShapeBox(
            // Canvas card: radius 16, 1 pt border inside (white 8 %), card fill, `overflow: hidden`.
            shape: const SwiftShape.rounded(16),
            fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
            strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
            clip: true,
            // The rows sit inside the border, as in CSS (`border: 1px` around the content box).
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      );
}

/// A row of a card (canvas: padding 0 16, gap 10, title 15 body, subtitle 12 tertiary 2 pt below, trailing 14
/// secondary, divider white 6 %). `minHeight` — the canvas uses 52, 56, 58 and 60.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.title, this.subtitle, this.showsDivider = true, this.trailing, this.minHeight = 56});

  final String title;
  final String? subtitle;
  final bool showsDivider;
  final Widget? trailing;
  final double minHeight;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: showsDivider ? const _BottomDivider() : const BoxDecoration(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwiftText(title, style: Typo.row.copyWith(color: TruverColors.textBody)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        SwiftText(subtitle!, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 18), // Spacer(minLength: 8) + spacing 10
                  DefaultTextStyle(style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary), child: trailing!),
                ],
              ],
            ),
          ),
        ),
      );
}

/// A 1 pt line of white 0.06 along the bottom edge (row dividers).
class _BottomDivider extends Decoration {
  const _BottomDivider();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _BottomDividerPainter();
}

class _BottomDividerPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy + size.height - 1, size.width, 1), Paint()..color = TruverColors.white(0.06));
  }
}

/// Row divider as a decoration, for rows built by features (`DecoratedBox(position: foreground, decoration: rowDivider)`).
const Decoration rowDivider = _BottomDivider();

/// A small card with a caption and a big light number (journal summary).
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.caption, required this.value});
  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) => ShapeBox(
        shape: const SwiftShape.rounded(16),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Padding(
          padding: const EdgeInsets.all(15), // 14 + the 1 pt border
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwiftText(caption, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                    const SizedBox(height: 2),
                    SwiftText(value, style: Typo.inter(28, TypoWeight.light, TruverColors.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// `.panel()`: 12 pt padding on a 16 pt continuous card with a hairline.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ShapeBox(
        shape: const SwiftShape.rounded(16),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Padding(padding: const EdgeInsets.all(13), child: child), // 12 + the 1 pt border
      );
}

/// Toast at the top: slides in by 14 pt, stays 3 s, a new one replaces the old in place (motion spec).
class ToastView extends StatelessWidget {
  const ToastView({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ShapeBox(
          shape: SwiftShape.capsule,
          shadows: [SwiftShadow(TruverColors.black(0.5), 10, y: 8)],
          fills: const [SwiftFill(TruverColors.panel)],
          strokes: const [SwiftStroke(TruverColors.hairlineStrong)],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Text(text, textAlign: TextAlign.center, style: Typo.inter(13, TypoWeight.medium, TruverColors.textBody)),
          ),
        ),
      );
}

/// Inter's natural line height (hhea ascender + descender, no line gap) per point of size.
const interLineHeight = 1.20996;

/// SwiftUI `.lineSpacing(spacing)` for Inter text: `spacing` extra points between lines and none above the first
/// or below the last line. Use together with [swiftLineSpacing] as the `textHeightBehavior`.
TextStyle lineSpaced(TextStyle style, double spacing) {
  final size = style.fontSize ?? 14;
  return style.copyWith(height: (interLineHeight * size + spacing) / size, leadingDistribution: TextLeadingDistribution.even);
}

const swiftLineSpacing = TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false);

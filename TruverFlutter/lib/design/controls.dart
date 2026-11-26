/// Port of Truver/Sources/DesignSystem/Controls.swift — controls of the canvas sheets: switch, radio, value
/// stepper, segments, chips, toast, sheet chrome, alerts. Also `SwipeRow` and `FlowLayout`
/// (MetronomeSheets.swift), shared by the presets and tunings lists.
library;

import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'components.dart';
import 'icons.dart';
import 'landscape.dart';
import 'motion.dart';
import 'shapes.dart';
import 'swift_text.dart';
import 'theme.dart';
import 'typo.dart';

/// iOS-size switch (51 × 31): ivory track when on, graphite knob.
class ToggleSwitch extends StatelessWidget {
  const ToggleSwitch({super.key, required this.isOn, required this.onChanged, required this.label});

  final bool isOn;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        value: isOn ? 'включено' : 'выключено',
        button: true,
        toggled: isOn,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!isOn),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: isOn ? 1 : 0),
            duration: Motion.quick,
            curve: Motion.out,
            builder: (context, t, _) => SizedBox(
              width: 51,
              height: 31,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                fills: [SwiftFill(Color.lerp(TruverColors.white(0.14), TruverColors.accent, t)!)],
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Align(
                    alignment: Alignment(t * 2 - 1, 0),
                    child: SizedBox(
                      width: 27,
                      height: 27,
                      child: ShapeBox(
                        shape: SwiftShape.circle,
                        shadows: [SwiftShadow(TruverColors.black(0.4), 2, y: 2)],
                        fills: [SwiftFill(Color.lerp(const Color(0xFFFFFFFF), TruverColors.panel, t)!)],
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

/// Radio mark (20 pt ring, 10 pt dot).
class RadioMark extends StatelessWidget {
  const RadioMark({super.key, required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: ShapeBox(
          shape: SwiftShape.circle,
          strokes: [SwiftStroke(selected ? TruverColors.textPrimary : TruverColors.white(0.3), width: 1.5, inside: true)],
          child: selected
              ? const Center(
                  child: SizedBox(
                      width: 10, height: 10, child: ShapeBox(shape: SwiftShape.circle, fills: [SwiftFill(TruverColors.textPrimary)])),
                )
              : null,
        ),
      );
}

/// A row with a radio mark: title 15, optional subtitle 12 (min height 56, padding 6 × 16).
class RadioRow extends StatelessWidget {
  const RadioRow({super.key, required this.title, this.subtitle, required this.selected, this.showsDivider = true, required this.onTap});

  final String title;
  final String? subtitle;
  final bool selected;
  final bool showsDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        scale: 1,
        selected: selected,
        onTap: onTap,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: showsDivider ? rowDivider : const BoxDecoration(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  RadioMark(selected: selected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwiftText(title, style: Typo.inter(15, TypoWeight.regular, TruverColors.textPrimary)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          SwiftText(subtitle!, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// «− 120 +» inside a row: 36 pt round buttons 4 apart from the value (16 pt, min width 44).
///
/// `valueMaxWidth`: inside a [CardRow] SwiftUI's HStack hands the stepper about a third of the row, so a value
/// wider than 44 pt wraps («20 / мин» in «Таймер занятия») — 44 reproduces that. Pass null where the iOS screen
/// shows the value on one line.
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.value,
    this.canDecrement = true,
    this.canIncrement = true,
    required this.decrement,
    required this.increment,
    this.valueMaxWidth = 44,
  });

  final String value;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback decrement;
  final VoidCallback increment;
  final double? valueMaxWidth;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: canDecrement ? 1 : 0.4,
            child: RoundIconButton(icon: AppIcon.minus, size: 36, iconSize: 16, label: 'Меньше', onTap: decrement, enabled: canDecrement),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 44, maxWidth: valueMaxWidth ?? double.infinity),
            // SwiftUI multiline text is leading-aligned; the 44 pt frame centres the text block.
            child: Center(
              widthFactor: 1,
              child: Text(value,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: Typo.monospacedDigit(Typo.inter(16, TypoWeight.regular, TruverColors.textPrimary))),
            ),
          ),
          const SizedBox(width: 4),
          Opacity(
            opacity: canIncrement ? 1 : 0.4,
            child: RoundIconButton(icon: AppIcon.plus, size: 36, iconSize: 16, label: 'Больше', onTap: increment, enabled: canIncrement),
          ),
        ],
      );
}

enum SegmentsSize { regular, compact, large }

/// Segmented control of the canvas: segments 30 pt (radius 15) in a tray with padding 3, a 1 pt border inside and
/// radius 18 — 38 pt in all (`regular` and `compact` are the same since the corrected canvas). `large` — 38 pt
/// segments, radius 22 (large-text boards).
class Segments<T> extends StatelessWidget {
  const Segments({super.key, required this.options, required this.selection, required this.onChanged, this.size = SegmentsSize.regular});

  final List<(T, String)> options;
  final T selection;
  final ValueChanged<T> onChanged;
  final SegmentsSize size;

  @override
  Widget build(BuildContext context) =>
      SegmentsBar<T>(options: options, selection: selection, onChanged: onChanged, height: size == SegmentsSize.large ? 38 : 30);
}

enum ChipStyle { plain, emphasized, positive, muted }

enum ChipSize { regular, large }

/// Chip of the canvas. `regular`: a `<span>` 32 pt + 1 pt border outside — 34 pt, radius 16, 12 medium; `large`: a
/// 36 pt button (border inside), radius 18, 14 medium (metronome chips). Padding 12 + border, gap 6.
/// Variants: plain, emphasized (ivory ring and tint), positive (green), muted.
class Chip extends StatelessWidget {
  const Chip({super.key, required this.text, this.icon, this.style = ChipStyle.plain, this.size = ChipSize.regular});

  final String text;
  final AppIcon? icon;
  final ChipStyle style;
  final ChipSize size;

  Color get _fillColor => switch (style) {
        ChipStyle.emphasized => const Color(0x1AF6F3EC),
        ChipStyle.positive => TruverColors.inTune.withValues(alpha: 0.08),
        _ => TruverColors.fill,
      };

  Color get _textColor => switch (style) {
        ChipStyle.plain => TruverColors.textBody,
        ChipStyle.emphasized => TruverColors.textPrimary,
        ChipStyle.positive => TruverColors.inTune,
        ChipStyle.muted => TruverColors.textSecondary,
      };

  Color get _iconColor => switch (style) {
        ChipStyle.emphasized => TruverColors.beat,
        ChipStyle.positive => TruverColors.inTune,
        _ => TruverColors.textTertiary,
      };

  Color get _borderColor => switch (style) {
        ChipStyle.emphasized => const Color(0x8CF6F3EC),
        ChipStyle.positive => TruverColors.inTune.withValues(alpha: 0.45),
        _ => TruverColors.hairlineStrong,
      };

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size == ChipSize.large ? 36 : 34,
        child: ShapeBox(
          shape: SwiftShape.rounded(size == ChipSize.large ? 18 : 16),
          fills: [SwiftFill(_fillColor)],
          strokes: [SwiftStroke(_borderColor, inside: true)],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  AppIconView(icon!, size: 14, lineWidth: icon == AppIcon.check ? 2 : 1.6, color: _iconColor),
                  const SizedBox(width: 6),
                ],
                Text(text,
                    maxLines: 1,
                    softWrap: false,
                    style: (size == ChipSize.large ? Typo.inter(14, TypoWeight.medium) : Typo.chip).copyWith(color: _textColor)),
              ],
            ),
          ),
        ),
      );
}

/// Toast of the canvas: 16 pt radius, icon 16 + text 13 medium, padding 11 × 16.
class DesignToast extends StatelessWidget {
  const DesignToast({super.key, this.icon, this.iconColor = TruverColors.beat, required this.text});

  final AppIcon? icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Semantics(
          container: true,
          child: ShapeBox(
            shape: const SwiftShape.rounded(16, continuous: true),
            shadows: [SwiftShadow(TruverColors.black(0.6), 15, y: 14)],
            fills: [SwiftFill(const Color(0xFF26282D).withValues(alpha: 0.96))],
            strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
            child: Padding(
              // Canvas padding 11 × 16 plus the 1 pt border, which is drawn inside the shape.
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    AppIconView(icon!,
                        size: 16,
                        lineWidth: icon == AppIcon.check ? 2 : 1.6,
                        color: icon == AppIcon.check ? TruverColors.inTune : iconColor),
                    const SizedBox(width: 10),
                  ],
                  Flexible(child: Text(text, style: Typo.inter(13, TypoWeight.medium, TruverColors.textBody))),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Section caption above a card in sheets (12 pt, padding 0 4 6 4).
class SectionCaption extends StatelessWidget {
  const SectionCaption({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
        child: SizedBox(
          width: double.infinity,
          child: SwiftText(text, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
        ),
      );
}

/// A card without a title (rows inside): radius 16, 1 pt border inside, clipped (canvas `overflow: hidden`).
class Card extends StatelessWidget {
  const Card({super.key, this.radius = 16, required this.children});
  final double radius;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ShapeBox(
        shape: SwiftShape.rounded(radius),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        clip: true,
        // The rows sit inside the border, as in CSS (`border: 1px` around the content box).
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

/// Wrapping row of chips (flex-wrap), 6 pt apart both ways.
class FlowLayout extends StatelessWidget {
  const FlowLayout({super.key, this.spacing = 6, required this.children});
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: spacing, runSpacing: spacing, children: children);
}

// MARK: Sheet

/// Sheet of the canvas: panel with 26 pt top corners, grabber, title 18 semibold and a round close button; an
/// optional ivory action at the bottom over a fade. Heights come from the canvas (844 − top). The dim and the
/// slide-in are drawn by the sheet host (`lib/features/root/root_view.dart`).
class DesignSheet extends StatefulWidget {
  const DesignSheet({super.key, required this.title, required this.height, required this.close, required this.child, this.footer});

  final String title;
  final double height;
  final VoidCallback close;
  final Widget child;

  /// Bottom actions (laid out in a row, 10 pt apart), e.g. `[Expanded(child: SheetButton(…))]`.
  final List<Widget>? footer;

  @override
  State<DesignSheet> createState() => _DesignSheetState();
}

class _DesignSheetState extends State<DesignSheet> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final landscape = isPhoneLandscape(context);
    final height = landscape ? math.min(widget.height, 360.0) : widget.height;
    final footer = widget.footer;
    final panel = SizedBox(
      height: height,
      width: double.infinity,
      child: ShapeBox(
        shape: const SwiftShape.topRounded(26),
        shadows: [SwiftShadow(TruverColors.black(0.6), 25, y: -20)],
        fills: const [
          SwiftFill.gradient(LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D1F23), TruverColors.panel],
          )),
        ],
        strokes: [
          SwiftStroke(
            const Color(0x00000000),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: const Alignment(0, 0.08 * 2 - 1),
              colors: [TruverColors.white(0.1), TruverColors.white(0)],
            ),
          ),
        ],
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 11, left: 20, right: 20), // border-top 1 + padding 10
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      width: 40,
                      height: 5,
                      child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.22))]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(widget.title, style: Typo.inter(18, TypoWeight.semibold, TruverColors.textPrimary)),
                          ),
                        ),
                        RoundIconButton(icon: AppIcon.close, size: 36, iconSize: 16, label: 'Закрыть', onTap: widget.close),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(padding: EdgeInsets.only(bottom: footer == null ? 34 : 110), child: widget.child),
                    ),
                  ),
                ],
              ),
            ),
            if (footer != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.3],
                      colors: [TruverColors.panel.withValues(alpha: 0), TruverColors.panel],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 34),
                    child: Row(children: [
                      for (var i = 0; i < footer.length; i++) ...[if (i > 0) const SizedBox(width: 10), footer[i]],
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _drag += d.delta.dy),
      onVerticalDragEnd: (d) {
        final predicted = _drag + (d.primaryVelocity ?? 0) * 0.25;
        if (_drag > 120 || predicted > 260) {
          widget.close();
        } else {
          setState(() => _drag = 0);
        }
      },
      onVerticalDragCancel: () => setState(() => _drag = 0),
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: Transform.translate(offset: Offset(0, math.max(0, _drag)), child: panel),
      ),
    );
  }
}

/// System-like alert of the canvas (290 wide, 22 radius, #202227) with a text field.
class TextFieldAlert extends StatefulWidget {
  const TextFieldAlert({super.key, required this.title, required this.controller, required this.cancel, required this.save});

  final String title;
  final TextEditingController controller;
  final VoidCallback cancel;
  final VoidCallback save;

  @override
  State<TextFieldAlert> createState() => _TextFieldAlertState();
}

class _TextFieldAlertState extends State<TextFieldAlert> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: widget.cancel, child: const ColoredBox(color: Color(0xA8030304))),
          ),
          Center(
            child: _AlertBox(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.title,
                          textAlign: TextAlign.center, style: Typo.inter(17, TypoWeight.semibold, TruverColors.textPrimary)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ShapeBox(
                          shape: const SwiftShape.rounded(10),
                          fills: [SwiftFill(TruverColors.white(0.08))],
                          strokes: const [SwiftStroke(TruverColors.flat, width: 1.5, inside: true)],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: EditableText(
                                controller: widget.controller,
                                focusNode: _focus,
                                style: Typo.inter(16, TypoWeight.regular, TruverColors.textPrimary),
                                cursorColor: TruverColors.flat,
                                backgroundCursorColor: TruverColors.textTertiary,
                                selectionColor: TruverColors.flat.withValues(alpha: 0.35),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => widget.save(),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _AlertButtons(actions: [
                  DesignAlertAction('Отмена', widget.cancel),
                  DesignAlertAction('Сохранить', widget.save, role: DesignAlertRole.preferred),
                ]),
              ],
            ),
          ),
        ],
      );
}

enum DesignAlertRole { normal, preferred, destructive }

class DesignAlertAction {
  const DesignAlertAction(this.title, this.perform, {this.role = DesignAlertRole.normal});
  final String title;
  final DesignAlertRole role;
  final VoidCallback perform;
}

/// Alert of the canvas (290 wide, radius 22, #202227): title 17 semibold, message 13; two buttons side by side,
/// three or more stacked; destructive ones in red (#ff8a80).
class DesignAlert extends StatelessWidget {
  const DesignAlert({super.key, required this.title, this.message, required this.actions, required this.dismiss});

  final String title;
  final String? message;
  final List<DesignAlertAction> actions;
  final VoidCallback dismiss;

  @override
  Widget build(BuildContext context) => Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: Stack(
          children: [
            Positioned.fill(child: GestureDetector(onTap: dismiss, child: const ColoredBox(color: Color(0xA8030304)))),
            Center(
              child: _AlertBox(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 22, bottom: 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, textAlign: TextAlign.center, style: Typo.inter(17, TypoWeight.semibold, TruverColors.textPrimary)),
                        if (message != null) ...[
                          const SizedBox(height: 6),
                          // line-height 1.4
                          Text(message!,
                              textAlign: TextAlign.center,
                              textHeightBehavior: swiftLineSpacing,
                              style: lineSpaced(Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary), 2.47)),
                        ],
                      ],
                    ),
                  ),
                  _AlertButtons(actions: actions),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AlertBox extends StatelessWidget {
  const _AlertBox({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 290,
        child: ShapeBox(
          shape: const SwiftShape.rounded(22),
          shadows: [SwiftShadow(TruverColors.black(0.7), 35, y: 30)],
          fills: const [SwiftFill(Color(0xFF202227))],
          strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
          clip: true,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

class _AlertButtons extends StatelessWidget {
  const _AlertButtons({required this.actions});
  final List<DesignAlertAction> actions;

  Widget _button(DesignAlertAction a) => Pressable(
        scale: 1,
        onTap: a.perform,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Center(
            child: Text(
              a.title,
              style: Typo.inter(
                17,
                a.role == DesignAlertRole.preferred ? TypoWeight.semibold : TypoWeight.regular,
                a.role == DesignAlertRole.destructive
                    ? const Color(0xFFFF8A80)
                    : (a.role == DesignAlertRole.preferred ? TruverColors.textPrimary : TruverColors.textBody),
              ),
            ),
          ),
        ),
      );

  static const _line = ColoredBox(color: TruverColors.hairlineStrong, child: SizedBox(height: 1, width: double.infinity));

  @override
  Widget build(BuildContext context) {
    if (actions.length == 2) {
      return Stack(
        children: [
          Row(children: [
            Expanded(child: _button(actions[0])),
            const ColoredBox(color: TruverColors.hairlineStrong, child: SizedBox(width: 1, height: 50)),
            Expanded(child: _button(actions[1])),
          ]),
          const Positioned(left: 0, right: 0, top: 0, child: _line),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in actions) Stack(children: [_button(a), const Positioned(left: 0, right: 0, top: 0, child: _line)]),
      ],
    );
  }
}

/// Row with swipe-left actions «Имя» (#4a5263) and «Удалить» (#e5483b), 92 pt each. `openId` / `onOpen` keep at
/// most one row of a list open (the parent holds the id).
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.id,
    required this.openId,
    required this.onOpen,
    this.showsDivider = true,
    this.rename,
    required this.delete,
    required this.child,
  });

  final String id;
  final String? openId;
  final ValueChanged<String?> onOpen;
  final bool showsDivider;

  /// null — only «Удалить» (92 pt).
  final VoidCallback? rename;
  final VoidCallback delete;
  final Widget child;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow> {
  double? _drag;

  double get _reveal => widget.rename == null ? 92 : 184;

  Widget _action(String title, AppIcon icon, Color color, VoidCallback perform) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: perform,
        child: ColoredBox(
          color: color,
          child: SizedBox(
            width: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIconView(icon, size: 18, color: const Color(0xFFFFFFFF)),
                const SizedBox(height: 2),
                Text(title, style: Typo.caption.copyWith(color: const Color(0xFFFFFFFF))),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final base = widget.openId == widget.id ? -_reveal : 0.0;
    final dragging = _drag != null;
    final target = math.min(0.0, math.max(-_reveal, base + (_drag ?? 0)));
    return Semantics(
      customSemanticsActions: {
        if (widget.rename != null) const CustomSemanticsAction(label: 'Переименовать'): widget.rename!,
        const CustomSemanticsAction(label: 'Удалить'): widget.delete,
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: widget.showsDivider ? rowDivider : const BoxDecoration(),
        child: ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: target),
            duration: dragging ? Duration.zero : Motion.base,
            curve: Motion.out,
            builder: (context, offset, child) => Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: offset < 0 ? 1 : 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.rename != null) _action('Имя', AppIcon.rename, const Color(0xFF4A5263), widget.rename!),
                        _action('Удалить', AppIcon.trash, const Color(0xFFE5483B), () {
                          widget.onOpen(null);
                          widget.delete();
                        }),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: GestureDetector(
                    onHorizontalDragStart: (_) => setState(() => _drag = 0),
                    onHorizontalDragUpdate: (d) => setState(() => _drag = (_drag ?? 0) + d.delta.dx),
                    onHorizontalDragEnd: (_) {
                      final open = base + (_drag ?? 0) < -_reveal / 2;
                      setState(() => _drag = null);
                      widget.onOpen(open ? widget.id : null);
                    },
                    onHorizontalDragCancel: () => setState(() => _drag = null),
                    child: ColoredBox(color: const Color(0xFF1A1C20).withValues(alpha: offset < 0 ? 1 : 0), child: child),
                  ),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Light haptic of a selection change (iOS `.sensoryFeedback(.selection)`).
void selectionHaptic() => HapticFeedback.selectionClick();

/// Port of Truver/Sources/Features/Thanks/ThanksChrome.swift
///
/// Page header, sheet panel and sheet host of the «Спасибо · обновления» page; links opened outside the app.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';

/// Opens a link outside the app: the platform's app or the browser (`mailto:` — the mail app).
Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No app for the link (an emulator without a mail app): nothing to do.
  }
}

/// Page header of «О Truver» and «Спасибо»: back button 40, gap 10, title 17 medium, 44 pt row 3 pt below the safe
/// area; no hairline.
class ThanksHeader extends StatelessWidget {
  const ThanksHeader({super.key, required this.title, required this.back});
  final String title;
  final VoidCallback back;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 3),
        child: SizedBox(
          height: 44,
          child: Row(children: [
            RoundIconButton(icon: AppIcon.chevronLeft, label: 'Назад', onTap: back),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.inter(17, TypoWeight.medium, TruverColors.textPrimary)),
              ),
            ),
          ]),
        ),
      );
}

/// The canvas sheet chrome (like `DesignSheet`) with an optional close button — the update notices have none.
class ThanksSheetPanel extends StatefulWidget {
  const ThanksSheetPanel({super.key, required this.title, required this.height, this.close, required this.child, this.footer});
  final String title;
  final double height;
  final VoidCallback? close;
  final Widget child;
  final List<Widget>? footer;

  @override
  State<ThanksSheetPanel> createState() => _ThanksSheetPanelState();
}

class _ThanksSheetPanelState extends State<ThanksSheetPanel> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final footer = widget.footer;
    final panel = SizedBox(
      height: widget.height,
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
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.only(top: 11, left: 20, right: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                child: Row(children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(widget.title, style: Typo.inter(18, TypoWeight.semibold, TruverColors.textPrimary)),
                    ),
                  ),
                  if (widget.close != null)
                    RoundIconButton(icon: AppIcon.close, size: 36, iconSize: 16, label: 'Закрыть', onTap: widget.close),
                ]),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(padding: EdgeInsets.only(bottom: footer == null ? 34 : 110), child: widget.child),
                ),
              ),
            ]),
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
        ]),
      ),
    );
    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _drag += d.delta.dy),
      onVerticalDragEnd: (d) {
        final predicted = _drag + (d.primaryVelocity ?? 0) * 0.25;
        if ((_drag > 120 || predicted > 260) && widget.close != null) {
          widget.close!();
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

/// Presents a sheet of this page over a screen like the app's `SheetHost`: the dim fades in (280 ms), the panel rises
/// 60 pt with a fade (340 ms) and leaves down by its own height.
class ThanksSheetHost<T> extends StatelessWidget {
  const ThanksSheetHost({super.key, required this.item, required this.dismiss, required this.builder, this.dim});
  final T? item;
  final VoidCallback dismiss;
  final Widget Function(BuildContext context, T item) builder;
  final Color? dim;

  @override
  Widget build(BuildContext context) {
    final shown = item != null;
    return Stack(children: [
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
              onTap: dismiss,
              child: GestureDetector(onTap: dismiss, child: ColoredBox(color: dim ?? TruverColors.sheetDim)),
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
          switchInCurve: Motion.out,
          switchOutCurve: Motion.out,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [...previous, ?current]),
          transitionBuilder: (child, animation) {
            final entering = child.key == ValueKey(item);
            return AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) {
                final t = animation.value;
                if (entering) {
                  return Opacity(opacity: t.clamp(0, 1), child: Transform.translate(offset: Offset(0, 60 * (1 - t)), child: child));
                }
                return FractionalTranslation(translation: Offset(0, 1 - t), child: child);
              },
            );
          },
          child: item == null
              ? const SizedBox.shrink(key: ValueKey(null))
              : KeyedSubtree(key: ValueKey(item), child: Builder(builder: (context) => builder(context, item as T))),
        ),
      ),
    ]);
  }
}

/// A row of the canvas cards with a chevron (canvas rows are `min-height` + the 1 pt bottom border: 52 → 53): title 15 body (+ subtitle 12 tertiary), trailing 14 secondary.
class ThanksRow extends StatelessWidget {
  const ThanksRow({super.key, required this.title, this.subtitle, this.minHeight = 53, this.divider = true, required this.onTap, this.value});
  final String title;
  final String? subtitle;
  final double minHeight;
  final bool divider;
  final VoidCallback onTap;
  final String? value;

  @override
  Widget build(BuildContext context) => Pressable(
        scale: 1,
        onTap: onTap,
        label: title,
        child: CardRow(
          title: title,
          subtitle: subtitle,
          showsDivider: divider,
          minHeight: minHeight,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (value != null) ...[SwiftText(value!), const SizedBox(width: 8)],
            const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
          ]),
        ),
      );
}

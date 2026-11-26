/// SwiftUI `Menu { Button(…) … } label: { … }` of the instrument and settings sheets: tapping the label opens a
/// pull-down list of actions next to it (the system menu on iOS). Not a Material menu: a dark rounded panel in the
/// app's colours, rows 44 pt, Inter 17; a long list scrolls.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/shapes.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';

class MenuItem {
  const MenuItem(this.title, this.action, {this.checked = false});
  final String title;
  final VoidCallback action;

  /// A check mark in front (the current value) — SwiftUI shows one for a `Picker` menu.
  final bool checked;
}

/// The label is tappable as a whole (`.buttonStyle(.plain)`: no press scaling).
class MenuButton extends StatelessWidget {
  const MenuButton({super.key, required this.items, required this.child, this.label});

  final List<MenuItem> Function() items;
  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) => Pressable(
        scale: 1,
        label: label,
        onTap: () => showDesignMenu(context, items()),
        child: child,
      );
}

/// Opens the menu anchored to `context`'s box (right edges aligned, below it or above when there is no room).
void showDesignMenu(BuildContext context, List<MenuItem> items) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final box = context.findRenderObject() as RenderBox?;
  if (overlay == null || box == null || items.isEmpty) return;
  final overlayBox = overlay.context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchor = topLeft & box.size;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _MenuLayer(
      anchor: anchor,
      items: items,
      dismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _MenuLayer extends StatefulWidget {
  const _MenuLayer({required this.anchor, required this.items, required this.dismiss});
  final Rect anchor;
  final List<MenuItem> items;
  final VoidCallback dismiss;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  bool _closing = false;

  static const _width = 250.0;
  static const _row = 44.0;

  Future<void> _close([VoidCallback? then]) async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    widget.dismiss();
    then?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final top = media.padding.top + 8, bottom = screen.height - media.padding.bottom - 8;
    final wanted = widget.items.length * _row + (widget.items.length - 1);
    final below = bottom - widget.anchor.bottom - 6, above = widget.anchor.top - 6 - top;
    final downward = below >= math.min(wanted, 300) || below >= above;
    final height = math.min(wanted, downward ? below : above);
    final left = (widget.anchor.right - _width).clamp(16.0, screen.width - 16 - _width);
    final y = downward ? widget.anchor.bottom + 6 : widget.anchor.top - 6 - height;
    final anyChecked = widget.items.any((i) => i.checked);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close, child: const SizedBox.expand()),
        ),
        Positioned(
          left: left,
          top: y,
          width: _width,
          height: height,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            child: ScaleTransition(
              alignment: downward ? Alignment.topRight : Alignment.bottomRight,
              scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
              child: ShapeBox(
                shape: const SwiftShape.rounded(16, continuous: true),
                shadows: [SwiftShadow(TruverColors.black(0.55), 20, y: 12)],
                fills: const [SwiftFill(Color(0xFA26282D))],
                strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                clip: true,
                child: SingleChildScrollView(
                  physics: wanted > height ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.items.length; i++) ...[
                        if (i > 0) ColoredBox(color: TruverColors.white(0.06), child: const SizedBox(height: 1)),
                        Pressable(
                          scale: 1,
                          onTap: () => _close(widget.items[i].action),
                          child: SizedBox(
                            height: _row,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  if (anyChecked)
                                    SizedBox(
                                      width: 26,
                                      child: widget.items[i].checked
                                          ? const Align(
                                              alignment: Alignment.centerLeft,
                                              child: AppIconView(AppIcon.check, size: 16, lineWidth: 2, color: TruverColors.textPrimary),
                                            )
                                          : null,
                                    ),
                                  Expanded(
                                    child: NoteText(widget.items[i].title,
                                        maxLines: 1, style: Typo.inter(17, TypoWeight.regular, TruverColors.textPrimary)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

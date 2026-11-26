/// SwiftUI `Menu` of the fretboard screens (position views, chord roots, progressions, layouts): a dark rounded
/// list over the screen next to the control that opened it. Android has no system menu with this look, so it is
/// drawn like the note menu (FretModes.swift `NoteMenu`).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/components.dart';
import '../../design/shapes.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';

class FretMenuItem {
  const FretMenuItem(this.title, this.action, {this.destructive = false, this.checked = false});
  final String title;
  final VoidCallback action;
  final bool destructive;
  final bool checked;
}

/// Opens a menu anchored to the widget of `context`.
void showFretMenu(BuildContext context, List<FretMenuItem> items) {
  final overlay = Overlay.maybeOf(context);
  final box = context.findRenderObject() as RenderBox?;
  if (overlay == null || box == null || items.isEmpty) return;
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final anchor = box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _FretMenu(
      anchor: anchor,
      bounds: overlayBox.size,
      items: items,
      close: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _FretMenu extends StatelessWidget {
  const _FretMenu({required this.anchor, required this.bounds, required this.items, required this.close});
  final Rect anchor;
  final Size bounds;
  final List<FretMenuItem> items;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    const width = 250.0, rowHeight = 44.0;
    final height = math.min(items.length * rowHeight, bounds.height - 120);
    final left = (anchor.center.dx - width / 2).clamp(12.0, bounds.width - width - 12);
    final below = anchor.bottom + 6;
    final top = below + height <= bounds.height - 40 ? below : math.max(50.0, anchor.top - 6 - height);
    return Stack(
      children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: close)),
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: ShapeBox(
            shape: const SwiftShape.rounded(14, continuous: true),
            shadows: [SwiftShadow(TruverColors.black(0.7), 25, y: 20)],
            fills: [SwiftFill(const Color(0xFF282A2F).withValues(alpha: 0.98))],
            clip: true,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < items.length; i++)
                  Pressable(
                    scale: 1,
                    onTap: () {
                      close();
                      items[i].action();
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: i == 0 ? null : Border(top: BorderSide(color: TruverColors.white(0.06))),
                      ),
                      child: SizedBox(
                        height: rowHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text.rich(
                                  Typo.notes(items[i].title,
                                      Typo.inter(15, TypoWeight.regular, items[i].destructive ? TruverColors.danger : TruverColors.textPrimary)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (items[i].checked) Text('✓', style: Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

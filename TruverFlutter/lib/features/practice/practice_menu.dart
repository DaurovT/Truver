/// SwiftUI `Menu` of the practice screens (the step's preset, the trainer's options): a dark panel anchored to
/// the button, rows with an optional check mark, groups separated by a thicker line (`Picker` sections and
/// `Toggle`s inside a menu). The system menu of iOS has no Android twin, so it is drawn here.
library;

import 'package:flutter/widgets.dart';

import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';

class MenuItem {
  const MenuItem(this.title, this.onTap, {this.checked = false});
  final String title;
  final VoidCallback onTap;

  /// Picker selection / toggle on.
  final bool checked;
}

/// Opens a menu of item groups under (or above) the widget of `anchor`.
void showPracticeMenu(BuildContext anchor, List<List<MenuItem>> groups) {
  final overlay = Overlay.of(anchor, rootOverlay: true);
  final box = anchor.findRenderObject() as RenderBox?;
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (box == null || overlayBox == null) return;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Menu(anchor: rect, groups: groups, close: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Menu extends StatefulWidget {
  const _Menu({required this.anchor, required this.groups, required this.close});
  final Rect anchor;
  final List<List<MenuItem>> groups;
  final VoidCallback close;

  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.quick)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _dismiss([VoidCallback? then]) async {
    await _c.reverse();
    widget.close();
    then?.call();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const width = 250.0;
    final rowCount = widget.groups.fold(0, (n, g) => n + g.length);
    final height = rowCount * 44.0 + (widget.groups.length - 1) * 8;
    final below = widget.anchor.bottom + 8 + height < screen.height - 40;
    final left = (widget.anchor.center.dx - width / 2).clamp(16.0, screen.width - width - 16);
    final top = below ? widget.anchor.bottom + 8 : widget.anchor.top - 8 - height;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _dismiss),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: FadeTransition(
            opacity: _c,
            child: ScaleTransition(
              scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Motion.out)),
              alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
              child: ShapeBox(
                shape: const SwiftShape.rounded(13, continuous: true),
                shadows: [SwiftShadow(TruverColors.black(0.5), 20, y: 10)],
                fills: const [SwiftFill(Color(0xFF26282D))],
                strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                clip: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var g = 0; g < widget.groups.length; g++) ...[
                      if (g > 0) Container(height: 8, color: TruverColors.black(0.25)),
                      for (var i = 0; i < widget.groups[g].length; i++) _row(widget.groups[g][i], i > 0),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(MenuItem item, bool divider) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _dismiss(item.onTap),
    child: Container(
      height: 44,
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: TruverColors.white(0.08), width: 0.5)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: item.checked ? const AppIconView(AppIcon.check, size: 14, lineWidth: 2, color: TruverColors.textPrimary) : null,
          ),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Typo.inter(16, TypoWeight.regular, TruverColors.textPrimary),
            ),
          ),
        ],
      ),
    ),
  );
}

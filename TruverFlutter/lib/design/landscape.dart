/// Port of Truver/Sources/DesignSystem/Landscape.swift
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Phone held sideways: the canvas landscape boards (844 × 390) replace the portrait screens, and the tab bar
/// with the tuning pill hides (canvas «Тюнер/Метроном/Гриф — альбом»). iOS uses the compact vertical size class;
/// here: wider than tall and shorter than 500 pt (phones only — tablets get their own layouts later).
bool isPhoneLandscape(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height && size.height < 500;
}

/// Lays content out in the canvas landscape board's points (844 × 390, top-left origin) and scales it to fit the
/// screen, edge to edge: on an 844 × 390 phone the result matches the board one to one.
class LandscapeCanvas extends StatefulWidget {
  const LandscapeCanvas({super.key, required this.child});
  static const size = Size(844, 390);
  final Widget child;

  @override
  State<LandscapeCanvas> createState() => _LandscapeCanvasState();
}

class _LandscapeCanvasState extends State<LandscapeCanvas> {
  @override
  void initState() {
    super.initState();
    // The boards run to the bottom edge: system bars hide until touched (iOS `.persistentSystemOverlays(.hidden)`).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        const board = LandscapeCanvas.size;
        final scale = math.min(constraints.maxWidth / board.width, constraints.maxHeight / board.height);
        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Center(
            child: SizedBox(
              width: board.width * scale,
              height: board.height * scale,
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                child: SizedBox(width: board.width, height: board.height, child: widget.child),
              ),
            ),
          ),
        );
      });
}

/// Places a block at the board's point (x, y), optionally with the board's width (`.board(x:y:width:)`); use
/// inside a `Stack` of a [LandscapeCanvas].
class Board extends StatelessWidget {
  const Board({super.key, required this.x, required this.y, this.width, required this.child});
  final double x;
  final double y;
  final double? width;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(left: x, top: y, width: width, child: child);
}

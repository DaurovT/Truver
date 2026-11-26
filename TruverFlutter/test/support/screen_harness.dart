import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truver/design/theme.dart' show ScreenNoise;

/// Renders screens headless in the exact geometry of the iOS reference device (iPhone 17e: 390 × 844 pt at 3×,
/// safe area 47 pt top / 34 pt bottom), so a PNG can be compared pixel by pixel with the iOS app's screenshot:
///
///   flutter test test/screens/tuner_test.dart
///   swift tool/compare.swift test/reference/ios/tuner_flat.png build/shots/tuner_flat.png build/shots/cmp_tuner_flat.jpg
///
/// Several people/agents can render at once — no device or emulator involved.
abstract final class ScreenHarness {
  static const logicalSize = Size(390, 844);
  static const pixelRatio = 3.0;
  static const topInset = 47.0;
  static const bottomInset = 34.0;

  static bool _fontsLoaded = false;

  /// Inter from the app's assets; the accidentals font (♯ ♭) is the Mac's SF registered as «Roboto», the family
  /// the app asks for — so test renders look like iOS, and the device uses its own Roboto.
  static Future<void> loadFonts() async {
    if (_fontsLoaded) return;
    final inter = FontLoader('Inter');
    for (final w in ['ExtraLight', 'Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    for (final path in ['/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf']) {
      final file = File(path);
      if (file.existsSync()) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        await loader.load();
        break;
      }
    }
    _fontsLoaded = true;
  }

  /// The canvas noise for `w × h` pixels: from memory, else from `build/noise/` (shared by all test processes, so it
  /// is computed once — ~10 s, much longer on a loaded machine), else computed and saved. Never blocks a test for
  /// more than 3 minutes: without it the screen is drawn without the 7 % noise.
  static Future<void> _noise(int w, int h) async {
    if (ScreenNoise.cached(w, h, pixelRatio) != null) return;
    final file = File('build/noise/${w}x$h.rgba');
    try {
      if (file.existsSync() && file.lengthSync() == w * h * 4) {
        await ScreenNoise.fromPixels(w, h, pixelRatio, file.readAsBytesSync());
        return;
      }
      final pixels = await Isolate.run(() => ScreenNoise.render(w, h, pixelRatio)).timeout(const Duration(minutes: 3));
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.$pid')..writeAsBytesSync(pixels);
      tmp.renameSync(file.path);
      await ScreenNoise.fromPixels(w, h, pixelRatio, pixels);
    } catch (_) {
      // Rendered without noise (below the compare threshold anyway).
    }
  }

  /// Sets the iPhone 17e view on the tester. Call before pumping.
  static void configure(WidgetTester tester, {bool landscape = false}) {
    final size = landscape ? Size(logicalSize.height, logicalSize.width) : logicalSize;
    tester.view.physicalSize = size * pixelRatio;
    tester.view.devicePixelRatio = pixelRatio;
    final insets = landscape
        ? const FakeViewPadding(left: 0, right: 0, top: 0, bottom: 21 * pixelRatio)
        : const FakeViewPadding(top: topInset * pixelRatio, bottom: bottomInset * pixelRatio);
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    addTearDown(tester.view.reset);
  }

  /// Pumps `screen` full-screen and writes `build/shots/<name>.png` (1170 × 2532).
  static Future<File> capture(WidgetTester tester, String name, Widget screen,
      {bool landscape = false, Duration settle = const Duration(milliseconds: 600)}) async {
    await loadFonts();
    configure(tester, landscape: landscape);
    // The canvas noise (ScreenBackground) is computed in an isolate on device; here once per size, before pumping,
    // so the first frame already has it.
    final px = (landscape ? Size(logicalSize.height, logicalSize.width) : logicalSize) * pixelRatio;
    await tester.runAsync(() => _noise(px.width.round(), px.height.round()));
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: screen));
    await tester.pump(settle);
    await tester.pump(const Duration(milliseconds: 16));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late File file;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory('build/shots')..createSync(recursive: true);
      file = File('${dir.path}/$name.png')..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    return file;
  }
}

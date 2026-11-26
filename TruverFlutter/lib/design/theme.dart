import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Colours of the design canvas «Truver — дизайн iOS и Mac» — a 1:1 port of `Truver/Sources/DesignSystem/Theme.swift`.
/// Change a value here and in Theme.swift together (TruverDesignTokens.swift is the shared source of truth).
abstract final class TruverColors {
  // Ground and surfaces
  static const background = Color(0xFF0A0B0D);
  static const backgroundLift = Color(0xFF1B1D21);
  static const panel = Color(0xFF141518);
  static const panelHigh = Color(0xFF26282C);
  static const faceTop = Color(0xFF1C1D20);
  static const faceBottom = Color(0xFF050506);

  // Text
  static const textPrimary = Color(0xFFF6F3EC);
  static const textBody = Color(0xFFE9E6DF);
  static const textMuted = Color(0xFFD9D6CF);
  static const textSecondary = Color(0xFFA29F97);
  static const textTertiary = Color(0xFF8A877F);

  // Lines and fills
  static const hairline = Color(0x14FFFFFF); // white 0.08
  static const hairlineStrong = Color(0x1AFFFFFF); // white 0.10
  static const fill = Color(0x0DFFFFFF); // white 0.05
  static final selectedBorder = const Color(0xFFF3EFE6).withValues(alpha: 0.6);

  // Signals
  static const inTune = Color(0xFF46E08F);
  static const flat = Color(0xFF6AA8FF);
  static const sharp = Color(0xFFFF9B52);
  static const neutralMark = Color(0x24FFFFFF); // white 0.14
  /// Warm white of metronome beats and the reference tone (canvas «Warm»).
  static const beat = Color(0xFFF3EFE6);
  static const danger = Color(0xFFFF6B5E);
  /// Characteristic degree ring on the neck and the «edited» mark (canvas #c3a6ff).
  static const characteristicNote = Color(0xFFC3A6FF);
  static final sheetDim = const Color(0xFF030304).withValues(alpha: 0.62);

  /// Light "ivory" of primary buttons and the selected segment.
  static const accent = Color(0xFFECE8DF);
  static const accentTop = Color(0xFFF6F3EC);
  static const accentBottom = Color(0xFFD9D4C8);

  // Fretboard roles (FB-3)
  static const tonic = Color(0xFFF6F3EC);
  static const chordTone = flat;
  static const characteristic = sharp;
  static const otherDegree = Color(0xFF8A877F);

  static const wood = Color(0xFF141518);
  static const fretWire = Color(0xFF8D9399);
  static const stringColor = Color(0xFFD9DCDF);

  /// Fretboard role colour: "tonic", "chordTone", "characteristic", anything else → other.
  static Color forRole(String role) => switch (role) {
        'tonic' => tonic,
        'chordTone' => chordTone,
        'characteristic' => characteristic,
        _ => otherDegree,
      };

  /// Deviation colour; always paired with a sign and a word (NFR accessibility).
  static Color deviation(double cents, {bool inTune = false}) =>
      inTune || cents.abs() <= 3 ? TruverColors.inTune : (cents < 0 ? flat : sharp);

  static Color white(double opacity) => Color.fromRGBO(255, 255, 255, opacity);
  static Color black(double opacity) => Color.fromRGBO(0, 0, 0, opacity);
}

/// Gradients of Theme.swift.
abstract final class TruverGradients {
  /// SwiftUI `RadialGradient(center: (0.5, 0.28), startRadius: 0, endRadius: 520)` — an absolute radius,
  /// so it is drawn by [ScreenBackground] in points rather than as a fraction of the box.
  static const screenCenter = Alignment(0, -0.44); // y 0.28 of the height → (0.28 − 0.5) × 2
  static const screenRadius = 520.0;

  static const cardFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.fromRGBO(255, 255, 255, 0.055), Color.fromRGBO(255, 255, 255, 0.018)],
  );
  static const keyFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.fromRGBO(255, 255, 255, 0.05), Color.fromRGBO(255, 255, 255, 0.015)],
  );
  static const keyFillSelected = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.fromRGBO(255, 255, 255, 0.09), Color.fromRGBO(255, 255, 255, 0.015)],
  );
  static const primaryFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [TruverColors.accentTop, TruverColors.accentBottom],
  );

  /// `RadialGradient(colors: [panelHigh, panel], center: (0.5, 0.35), startRadius: 0, endRadius: 40)` for a knob
  /// of `size` points.
  static RadialGradient knobFill(double size) => RadialGradient(
        center: const Alignment(0, -0.3),
        radius: 40 / size, // fraction of the shortest side in Flutter
        colors: const [TruverColors.panelHigh, TruverColors.panel],
      );

  /// Brushed metal of the dial ring: SwiftUI AngularGradient starting at 20° − 90° (clockwise from +x).
  static const metalColors = [
    Color(0xFF8D9399), Color(0xFFECEEF0), Color(0xFF9AA0A6), Color(0xFFDFE2E5), Color(0xFF7C8288), Color(0xFFF2F3F4),
    Color(0xFFA3A9AE), Color(0xFFD9DCDF), Color(0xFF858B91), Color(0xFFECEEF0), Color(0xFF8D9399),
  ];
  static const metal = SweepGradient(
    colors: metalColors,
    transform: GradientRotation((20 - 90) * math.pi / 180),
  );
}

/// The screen ground of every canvas board: `radial-gradient(90% 55% at 50% 28%, #1b1d21 0%, #0a0b0d 70%)` (an
/// ellipse with radii 90 % × 55 % of the screen, the dark colour reached at 70 % of them) and the paper-like noise
/// overlay (`feTurbulence` fractal noise at 7 %, [ScreenNoise]). Port of `ScreenBackground` (Theme.swift).
class ScreenBackground extends StatefulWidget {
  const ScreenBackground({super.key});

  @override
  State<ScreenBackground> createState() => _ScreenBackgroundState();
}

class _ScreenBackgroundState extends State<ScreenBackground> {
  ui.Image? _noise;
  String? _key;

  void _ensure(Size size, double scale) {
    final w = (size.width * scale).ceil(), h = (size.height * scale).ceil();
    if (w <= 0 || h <= 0) return;
    final key = ScreenNoise.key(w, h, scale);
    if (key == _key) return;
    _key = key;
    final cached = ScreenNoise.cached(w, h, scale);
    if (cached != null) {
      _noise = cached;
      return;
    }
    _noise = null;
    ScreenNoise.image(w, h, scale).then((image) {
      if (mounted && _key == key) setState(() => _noise = image);
    });
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: IgnorePointer(
          child: LayoutBuilder(builder: (context, constraints) {
            final size = constraints.biggest;
            final scale = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
            if (size.isFinite) _ensure(size, scale);
            return CustomPaint(painter: _ScreenBackgroundPainter(_noise, scale), size: Size.infinite);
          }),
        ),
      );
}

class _ScreenBackgroundPainter extends CustomPainter {
  _ScreenBackgroundPainter(this.noise, this.scale);
  final ui.Image? noise;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = TruverColors.background);
    final rx = size.width * 0.9, ry = size.height * 0.55;
    if (rx > 0 && ry > 0) {
      final r = rx * 0.7;
      canvas.save();
      canvas.translate(size.width * 0.5, size.height * 0.28);
      canvas.scale(1, ry / rx);
      final rect = Rect.fromCircle(center: Offset.zero, radius: r);
      canvas.drawOval(
          rect,
          Paint()
            ..shader = const RadialGradient(colors: [TruverColors.backgroundLift, TruverColors.background]).createShader(rect));
      canvas.restore();
    }
    final image = noise;
    if (image != null) {
      canvas.save();
      canvas.scale(1 / scale);
      canvas.drawImage(image, Offset.zero, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.07)..filterQuality = FilterQuality.none);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenBackgroundPainter old) => old.noise != noise || old.scale != scale;
}

/// The noise layer of the canvas boards — an SVG at opacity 0.07 whose rect is filtered by `feTurbulence`
/// (fractalNoise, baseFrequency 0.85, numOctaves 2, seed 4) and `feColorMatrix saturate 0` — over the whole screen,
/// computed with the reference algorithm of the SVG specification at the screen's pixel density (matches the canvas
/// render: residual correlation 0.98), once per screen size, in a background isolate. Port of `ScreenNoise`.
abstract final class ScreenNoise {
  static final _memory = <String, ui.Image>{};
  static final _pending = <String, Future<ui.Image>>{};

  static String key(int w, int h, double scale) => '${w}x$h@${(scale * 100).round()}';

  static ui.Image? cached(int w, int h, double scale) => _memory[key(w, h, scale)];

  /// Registers noise pixels computed elsewhere (the test harness keeps them in a file between test processes).
  static Future<ui.Image> fromPixels(int w, int h, double scale, Uint8List pixels) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, completer.complete);
    final image = await completer.future;
    _memory[key(w, h, scale)] = image;
    return image;
  }

  /// Gray + alpha noise (premultiplied RGBA8) of `w × h` device pixels at `scale` pixels per point.
  static Future<ui.Image> image(int w, int h, double scale) {
    final k = key(w, h, scale);
    final hit = _memory[k];
    if (hit != null) return Future.value(hit);
    return _pending[k] ??= () async {
      final pixels = await Isolate.run(() => render(w, h, scale));
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, completer.complete);
      final image = await completer.future;
      _memory[k] = image;
      _pending.remove(k);
      return image;
    }();
  }

  /// feTurbulence (fractalNoise, base frequency 0.85, 2 octaves, seed 4) in linearRGB, desaturated
  /// (0.2126 R + 0.7152 G + 0.0722 B), converted to sRGB; alpha is the noise's own alpha channel. WebKit samples the
  /// filter at device pixel (i, j) → user point ((i + 1) / scale, (j + 1) / scale).
  static Uint8List render(int w, int h, double scale) {
    final t = _Turbulence(4);
    final out = Uint8List(w * h * 4);
    final toSrgb = Uint8List(4096);
    for (var i = 0; i < 4096; i++) {
      final v = i / 4095;
      final s = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
      toSrgb[i] = (s * 255).round().clamp(0, 255);
    }
    final f = 0.85 / scale;
    var o = 0;
    for (var j = 0; j < h; j++) {
      final y = (j + 1) * f;
      for (var i = 0; i < w; i++) {
        final x = (i + 1) * f;
        final r = t.channel(0, x, y), g = t.channel(1, x, y), b = t.channel(2, x, y), a = t.channel(3, x, y);
        final gray = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
        final g8 = toSrgb[(gray * 4095).round()];
        final a8 = (a * 255).round();
        final c = (g8 * a8 / 255).round();
        out[o] = c;
        out[o + 1] = c;
        out[o + 2] = c;
        out[o + 3] = a8;
        o += 4;
      }
    }
    return out;
  }
}

/// The SVG 1.1 reference implementation of Perlin turbulence (lattice, gradients, `random` of the spec).
class _Turbulence {
  _Turbulence(int seed) {
    var s = seed;
    if (s <= 0) s = -(s % (2147483647 - 1)) + 1;
    if (s > 2147483647 - 1) s = 2147483647 - 1;
    int random() {
      var r = 16807 * (s % 127773) - 2836 * (s ~/ 127773);
      if (r <= 0) r += 2147483647;
      s = r;
      return r;
    }

    for (var k = 0; k < 4; k++) {
      for (var i = 0; i < 256; i++) {
        _lattice[i] = i;
        final a = ((random() % 512) - 256) / 256, b = ((random() % 512) - 256) / 256;
        final n = math.sqrt(a * a + b * b);
        _gradient[(k * 514 + i) * 2] = a / n;
        _gradient[(k * 514 + i) * 2 + 1] = b / n;
      }
    }
    for (var i = 255; i > 0; i--) {
      final k = _lattice[i], j = random() % 256;
      _lattice[i] = _lattice[j];
      _lattice[j] = k;
    }
    for (var i = 0; i < 258; i++) {
      _lattice[256 + i] = _lattice[i];
      for (var k = 0; k < 4; k++) {
        _gradient[(k * 514 + 256 + i) * 2] = _gradient[(k * 514 + i) * 2];
        _gradient[(k * 514 + 256 + i) * 2 + 1] = _gradient[(k * 514 + i) * 2 + 1];
      }
    }
  }

  final _lattice = Int32List(514);
  final _gradient = Float64List(4 * 514 * 2);

  /// Fractal sum of 2 octaves mapped to 0…1 (`(sum · 255 + 255) / 2`).
  double channel(int c, double x, double y) => ((_noise(c, x, y) + _noise(c, x * 2, y * 2) / 2 + 1) / 2).clamp(0.0, 1.0);

  double _noise(int c, double x, double y) {
    var t = x + 4096;
    final bx0 = t.toInt() & 255, bx1 = (bx0 + 1) & 255;
    final rx0 = t - t.toInt(), rx1 = rx0 - 1;
    t = y + 4096;
    final by0 = t.toInt() & 255, by1 = (by0 + 1) & 255;
    final ry0 = t - t.toInt(), ry1 = ry0 - 1;
    final i = _lattice[bx0], j = _lattice[bx1];
    final base = c * 514;
    final b00 = (base + _lattice[i + by0]) * 2, b10 = (base + _lattice[j + by0]) * 2;
    final b01 = (base + _lattice[i + by1]) * 2, b11 = (base + _lattice[j + by1]) * 2;
    final sx = rx0 * rx0 * (3 - 2 * rx0), sy = ry0 * ry0 * (3 - 2 * ry0);
    var u = rx0 * _gradient[b00] + ry0 * _gradient[b00 + 1];
    var v = rx1 * _gradient[b10] + ry0 * _gradient[b10 + 1];
    final a = u + sx * (v - u);
    u = rx0 * _gradient[b01] + ry1 * _gradient[b01 + 1];
    v = rx1 * _gradient[b11] + ry1 * _gradient[b11 + 1];
    final b = u + sx * (v - u);
    return a + sy * (b - a);
  }
}

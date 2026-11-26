import 'package:flutter/widgets.dart';

/// Inter, bundled (same files as iOS). Port of `Typography.swift`.
///
/// Sizes are canvas points = Flutter logical pixels. `scaled` fonts follow the system text size (Dynamic Type on
/// iOS ↔ font scale on Android); `fixed` ones do not (instrument numerals laid out by the canvas).
enum TypoWeight {
  extraLight(FontWeight.w200),
  light(FontWeight.w300),
  regular(FontWeight.w400),
  medium(FontWeight.w500),
  semibold(FontWeight.w600),
  bold(FontWeight.w700);

  const TypoWeight(this.fontWeight);
  final FontWeight fontWeight;
}

abstract final class Typo {
  static const family = 'Inter';

  /// `font-variant-numeric: tabular-nums` sits on the root of every canvas board, so all digits are tabular
  /// («6-струнная», «109,1 Гц», tab labels) — iOS sets the same feature in `Typo.inter` since the corrected canvas.
  static const _tabular = [FontFeature.tabularFigures()];

  /// Glyphs Inter lacks (♯ ♭ 𝄪 …) fall back to the system font, as iOS's cascade list (Typography.swift) does.
  /// «Roboto» is the Android system family; the screen harness registers the Mac's SF under that name.
  static const _fallback = ['Roboto'];

  /// SwiftUI `.monospacedDigit()`: tabular figures.
  static TextStyle monospacedDigit(TextStyle style) => style.copyWith(fontFeatures: _tabular);

  /// Inter at `size` points. Scaling with the system text size is done by Flutter's TextScaler at render time;
  /// wrap fixed layouts in `MediaQuery.withNoTextScaling` (see [fixed]).
  static TextStyle inter(double size, [TypoWeight weight = TypoWeight.regular, Color? color]) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight.fontWeight,
        color: color,
        fontFamilyFallback: _fallback,
        fontFeatures: _tabular,
        height: null,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Same style; the widget using it must not scale with the system text size (use [FixedText] / [NoTextScale]).
  static TextStyle fixed(double size, [TypoWeight weight = TypoWeight.regular, Color? color]) => inter(size, weight, color);

  // Named roles of the canvas
  /// Screen title of the canvas header: 26 semibold, letter-spacing −0.02 em (−0.52), line height 1.15.
  static TextStyle get screenTitle => inter(26, TypoWeight.semibold);
  static TextStyle get body => inter(15);
  static TextStyle get row => inter(15);
  static TextStyle get caption => inter(12);
  static TextStyle get chip => inter(12, TypoWeight.medium);
  static TextStyle get segment => inter(13, TypoWeight.medium);
  static TextStyle get segmentSelected => inter(13, TypoWeight.semibold);
  static TextStyle get status => inter(17, TypoWeight.medium);
  static TextStyle get button => inter(15, TypoWeight.semibold);
  static TextStyle get tab => inter(11);
  static TextStyle get tabSelected => inter(11, TypoWeight.semibold);

  static const _accidentals = {'♯', '♭', '𝄪', '𝄫', '♮'};

  /// Note text whose accidentals (♯ ♭ 𝄪 𝄫) are set in the platform font, as on the canvas (Inter's own ♯ looks
  /// like «#»). iOS uses SF; here the system sans (Roboto / Segoe UI) — the closest platform equivalent.
  static TextSpan notes(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    final run = StringBuffer();
    void flush() {
      if (run.isNotEmpty) {
        spans.add(TextSpan(text: run.toString()));
        run.clear();
      }
    }

    for (final ch in text.characters) {
      if (_accidentals.contains(ch)) {
        flush();
        spans.add(TextSpan(
          text: ch,
          style: TextStyle(fontFamily: null, fontFamilyFallback: const ['Roboto', 'Segoe UI Symbol', 'Noto Sans Symbols'], fontFeatures: const []),
        ));
      } else {
        run.write(ch);
      }
    }
    flush();
    return TextSpan(style: style, children: spans);
  }

  /// Numbers as on the canvas: decimal comma («109,1 Гц», «×1,6»). Port of `decimalComma` (Typography.swift).
  static String decimalComma(double value, [int digits = 1]) => value.toStringAsFixed(digits).replaceAll('.', ',');

  /// Compact chord symbols of the canvas: «G♯°», «B°», «C+», «Bø7».
  static String compactChordName(String name) {
    for (final (long, short) in const [('m7♭5', 'ø7'), ('dim7', '°7'), ('dim', '°'), ('aug', '+')]) {
      if (name.endsWith(long)) return name.substring(0, name.length - long.length) + short;
    }
    return name;
  }
}

/// `Text` with note accidentals in the platform font (see [Typo.notes]).
class NoteText extends StatelessWidget {
  const NoteText(this.text, {super.key, required this.style, this.textAlign, this.maxLines, this.scale = true});

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final int? maxLines;

  /// false: fixed size, ignores the system text size (canvas-sized instrument text).
  final bool scale;

  @override
  Widget build(BuildContext context) => Text.rich(
        Typo.notes(text, style),
        textAlign: textAlign,
        maxLines: maxLines,
        textScaler: scale ? null : TextScaler.noScaling,
      );
}

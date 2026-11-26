/// Port of Truver/Sources/Features/Thanks/SVGPath.swift
///
/// SVG path data (`d="M28 4C40 4 …z"`) as a Flutter path — the «Спасибо» page draws the canvas glyphs (the gold
/// plectrum, platform tiles, partner badges) from the same path strings. M L H V C S Q T A Z, relative and absolute.
library;

import 'package:flutter/widgets.dart';

final _cache = <String, Path>{};

/// The path in its own `viewBox` units.
Path parseSvgPath(String d) => _cache.putIfAbsent(d, () => _SvgParser(d).parse());

/// Paints SVG path data scaled from a square `viewBox` into the widget's box, filled or stroked.
class SvgGlyph extends StatelessWidget {
  const SvgGlyph(this.data, {super.key, this.viewBox = 24, this.color, this.gradient, this.stroke, this.cap = StrokeCap.butt, this.join = StrokeJoin.miter, this.size, this.offset = Offset.zero});

  final String data;
  final double viewBox;
  final Color? color;
  final Gradient? gradient;
  /// Stroke width in viewBox units; null — filled.
  final double? stroke;
  final StrokeCap cap;
  final StrokeJoin join;
  final double? size;
  /// Translation in viewBox units (SVG `transform="translate(…)"`).
  final Offset offset;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SvgPainter(data, viewBox, color ?? const Color(0xFFFFFFFF), gradient, stroke, cap, join, offset),
        ),
      );
}

class _SvgPainter extends CustomPainter {
  _SvgPainter(this.data, this.viewBox, this.color, this.gradient, this.stroke, this.cap, this.join, this.offset);
  final String data;
  final double viewBox;
  final Color color;
  final Gradient? gradient;
  final double? stroke;
  final StrokeCap cap;
  final StrokeJoin join;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (size.width < size.height ? size.width : size.height) / viewBox;
    canvas.save();
    canvas.translate(size.width / 2 - viewBox / 2 * s, size.height / 2 - viewBox / 2 * s);
    canvas.scale(s);
    canvas.translate(offset.dx, offset.dy);
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color;
    if (gradient != null) paint.shader = gradient!.createShader(Rect.fromLTWH(0, 0, viewBox, viewBox));
    if (stroke != null) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke!
        ..strokeCap = cap
        ..strokeJoin = join;
    }
    canvas.drawPath(parseSvgPath(data), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgPainter old) =>
      old.data != data || old.color != color || old.gradient != gradient || old.stroke != stroke || old.viewBox != viewBox;
}

class _SvgParser {
  _SvgParser(this.d);
  final String d;
  int i = 0;

  bool _isCommand(int c) => ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) && c != 101 && c != 69;

  void _skip() {
    while (i < d.length) {
      final c = d.codeUnitAt(i);
      if (c == 32 || c == 44 || c == 10 || c == 9 || c == 13) {
        i++;
      } else {
        break;
      }
    }
  }

  int? _command() {
    _skip();
    if (i >= d.length) return null;
    final c = d.codeUnitAt(i);
    if (_isCommand(c)) {
      i++;
      return c;
    }
    return null;
  }

  bool? _flag() {
    _skip();
    if (i >= d.length) return null;
    final c = d.codeUnitAt(i);
    if (c != 48 && c != 49) return null;
    i++;
    return c == 49;
  }

  double? _number() {
    _skip();
    final begin = i;
    if (i < d.length && (d.codeUnitAt(i) == 45 || d.codeUnitAt(i) == 43)) i++;
    var dot = false, digits = false;
    while (i < d.length) {
      final c = d.codeUnitAt(i);
      if (c >= 48 && c <= 57) {
        digits = true;
        i++;
      } else if (c == 46 && !dot) {
        dot = true;
        i++;
      } else if ((c == 101 || c == 69) && digits) {
        i++;
        if (i < d.length && (d.codeUnitAt(i) == 45 || d.codeUnitAt(i) == 43)) i++;
        while (i < d.length && d.codeUnitAt(i) >= 48 && d.codeUnitAt(i) <= 57) {
          i++;
        }
        break;
      } else {
        break;
      }
    }
    if (!digits) {
      i = begin;
      return null;
    }
    return double.parse(d.substring(begin, i));
  }

  Path parse() {
    final path = Path();
    var cur = Offset.zero, start = Offset.zero;
    Offset? lastC, lastQ;
    var command = 0;
    while (true) {
      final next = _command() ?? (command != 0 ? command : null);
      if (next == null) break;
      command = next;
      final rel = next >= 97;
      final c = rel ? next - 32 : next;
      Offset? pt() {
        final x = _number();
        if (x == null) return null;
        final y = _number();
        if (y == null) return null;
        return rel ? Offset(cur.dx + x, cur.dy + y) : Offset(x, y);
      }

      var ok = true;
      switch (String.fromCharCode(c)) {
        case 'M':
          final p = pt();
          if (p == null) {
            ok = false;
            break;
          }
          path.moveTo(p.dx, p.dy);
          cur = p;
          start = p;
          command = rel ? 108 : 76;
          lastC = lastQ = null;
        case 'L':
          final p = pt();
          if (p == null) {
            ok = false;
            break;
          }
          path.lineTo(p.dx, p.dy);
          cur = p;
          lastC = lastQ = null;
        case 'H':
          final x = _number();
          if (x == null) {
            ok = false;
            break;
          }
          cur = Offset(rel ? cur.dx + x : x, cur.dy);
          path.lineTo(cur.dx, cur.dy);
          lastC = lastQ = null;
        case 'V':
          final y = _number();
          if (y == null) {
            ok = false;
            break;
          }
          cur = Offset(cur.dx, rel ? cur.dy + y : y);
          path.lineTo(cur.dx, cur.dy);
          lastC = lastQ = null;
        case 'C':
          final c1 = pt(), c2 = pt(), p = pt();
          if (c1 == null || c2 == null || p == null) {
            ok = false;
            break;
          }
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
          cur = p;
          lastC = c2;
          lastQ = null;
        case 'S':
          final c1 = lastC == null ? cur : Offset(2 * cur.dx - lastC.dx, 2 * cur.dy - lastC.dy);
          final c2 = pt(), p = pt();
          if (c2 == null || p == null) {
            ok = false;
            break;
          }
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
          cur = p;
          lastC = c2;
          lastQ = null;
        case 'Q':
          final q = pt(), p = pt();
          if (q == null || p == null) {
            ok = false;
            break;
          }
          path.quadraticBezierTo(q.dx, q.dy, p.dx, p.dy);
          cur = p;
          lastQ = q;
          lastC = null;
        case 'T':
          final q = lastQ == null ? cur : Offset(2 * cur.dx - lastQ.dx, 2 * cur.dy - lastQ.dy);
          final p = pt();
          if (p == null) {
            ok = false;
            break;
          }
          path.quadraticBezierTo(q.dx, q.dy, p.dx, p.dy);
          cur = p;
          lastQ = q;
          lastC = null;
        case 'A':
          final rx = _number(), ry = _number(), rot = _number(), large = _flag(), sweep = _flag();
          final p = (rx == null || ry == null || rot == null || large == null || sweep == null) ? null : pt();
          if (p == null) {
            ok = false;
            break;
          }
          path.arcToPoint(p, radius: Radius.elliptical(rx!.abs(), ry!.abs()), rotation: rot!, largeArc: large!, clockwise: sweep!);
          cur = p;
          lastC = lastQ = null;
        case 'Z':
          path.close();
          cur = start;
          lastC = lastQ = null;
          command = 0;
        default:
          ok = false;
      }
      if (!ok) break;
    }
    return path;
  }
}

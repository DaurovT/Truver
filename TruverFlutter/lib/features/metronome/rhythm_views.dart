/// Port of Truver/Sources/Features/Metronome/RhythmViews.swift
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'metronome_controller.dart';
import 'metronome_sheets.dart';
import 'rhythm_library.dart';

/// A rhythmic figure drawn in notation (user: «как в Soundbrenner»): note heads with stems up, beams by value
/// (eighth — one, sixteenth — two, thirty-second — three), partial beams for mixed figures (8-16-16, 16-8-16),
/// dots, the tuplet number over the beam, eighth rests where the figure starts after the beat.
class RhythmGlyph extends StatelessWidget {
  const RhythmGlyph({super.key, required this.rhythm, this.color = TruverColors.textPrimary, this.denominator = 4});

  final RhythmInfo rhythm;
  final Color color;

  /// The beat's note value: in 6/8 or 7/8 a beat is an eighth, so one click per beat is drawn as an eighth.
  final int denominator;

  @override
  Widget build(BuildContext context) => Semantics(
    label: rhythm.spokenName,
    child: CustomPaint(painter: _GlyphPainter(rhythm, color, denominator), size: Size.infinite),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.rhythm, this.color, this.denominator);

  final RhythmInfo rhythm;
  final Color color;
  final int denominator;

  double get _nominalStepsPerQuarter {
    final spb = math.max(0.25, rhythm.stepsPerBeat);
    return math.pow(2, (math.log(spb) / math.ln2).floorToDouble()) * math.max(1, denominator) / 4;
  }

  static int _beams(double value) {
    if (value < 0.13) return 3;
    if (value < 0.26) return 2;
    if (value < 0.38) return 2; // dotted sixteenth
    if (value < 0.76) return 1; // eighth, dotted eighth
    return 0;
  }

  static bool _dotted(double value) => const [0.375, 0.75, 1.5, 3.0].any((v) => (v - value).abs() < 1e-6);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final headW = math.min(8.0, h * 0.3), headH = headW * 0.72;
    final stemTop = h * 0.12 + (rhythm.tuplet != null ? h * 0.12 : 0);
    final headY = h - headH / 2 - 1;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    Paint stroke(double w, {StrokeCap cap = StrokeCap.butt, StrokeJoin join = StrokeJoin.miter}) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = cap
      ..strokeJoin = join;

    void head(double x, {required bool hollow}) {
      canvas.save();
      canvas.translate(x, headY);
      canvas.rotate(-0.35);
      final oval = Rect.fromLTWH(-headW / 2, -headH / 2, headW, headH);
      canvas.drawOval(oval, hollow ? stroke(1.3) : fill);
      canvas.restore();
    }

    double stemX(double x) => x + headW / 2 - 0.6;
    void stem(double x) => canvas.drawLine(Offset(stemX(x), headY - 1), Offset(stemX(x), stemTop), stroke(1.2));

    // Values of the notes: steps / nominal steps per quarter (whole bar figures count in quarters of 4/4).
    final nominal = _nominalStepsPerQuarter;
    final values = [for (final d in rhythm.durations) d / nominal];
    final onsets = rhythm.onsets;
    final leadRest = onsets.isEmpty || onsets.first > 0;
    final notes = values.length;
    final slots = notes + (leadRest ? 1 : 0);
    final pad = headW / 2 + 2;
    final step = slots > 1 ? (size.width - 2 * pad - headW / 2) / (slots - 1) : 0.0;
    final xs = slots == 1 ? [size.width / 2 - headW / 2] : [for (var i = 0; i < slots; i++) pad + i * step];
    if (leadRest && xs.isNotEmpty) {
      final x = xs.first;
      // The rest drawn by its length (it was always an eighth rest): 16th, 8th, quarter, half.
      final restValue = (onsets.isNotEmpty ? onsets.first : rhythm.grid) / nominal;
      if (restValue < 0.3) {
        canvas.drawLine(Offset(x + 3, h * 0.34), Offset(x - 1, h * 0.86), stroke(1.2));
        for (final dy in const [0.30, 0.48]) {
          canvas.drawOval(Rect.fromLTWH(x - 2, h * dy, 3, 3), fill);
        }
      } else if (restValue < 0.8) {
        canvas.drawLine(Offset(x + 3, h * 0.38), Offset(x - 1, h * 0.82), stroke(1.2));
        canvas.drawOval(Rect.fromLTWH(x - 1, h * 0.32, 3, 3), fill);
      } else if (restValue < 1.6) {
        final r = Path()
          ..moveTo(x - 1, h * 0.30)
          ..lineTo(x + 3, h * 0.46)
          ..lineTo(x - 1, h * 0.60)
          ..lineTo(x + 3, h * 0.74)
          ..quadraticBezierTo(x - 3, h * 0.80, x + 1, h * 0.90);
        canvas.drawPath(r, stroke(1.4, cap: StrokeCap.round, join: StrokeJoin.round));
      } else {
        canvas.drawRect(Rect.fromLTWH(x - 3, h * 0.58, 7, 3), fill);
        canvas.drawRect(Rect.fromLTWH(x - 5, h * 0.58 + 3, 11, 1), fill);
      }
    }
    final noteXs = xs.sublist(xs.length - notes);
    final beamCounts = [for (final v in values) _beams(v)];
    for (var i = 0; i < notes; i++) {
      final x = noteXs[i], v = values[i];
      head(x, hollow: v >= 2);
      if (v < 4) stem(x);
      if (_dotted(v)) canvas.drawOval(Rect.fromLTWH(x + headW / 2 + 1.5, headY - 1.5, 2.4, 2.4), fill);
    }
    final beamH = math.max(1.8, h * 0.07);
    final gap = beamH + 1.6;
    // Beam groups: runs of neighbouring notes that have beams; a lone beamed note gets flags.
    var i = 0;
    while (i < notes) {
      if (beamCounts[i] <= 0) {
        i += 1;
        continue;
      }
      var j = i;
      while (j + 1 < notes && beamCounts[j + 1] > 0) {
        j += 1;
      }
      if (i == j) {
        final x = noteXs[i];
        for (var b = 0; b < beamCounts[i]; b++) {
          final y = stemTop + b * gap;
          final f = Path()
            ..moveTo(stemX(x), y)
            ..quadraticBezierTo(stemX(x) + 5, y + 2, stemX(x) + 5, y + 7);
          canvas.drawPath(f, stroke(1.3));
        }
      } else {
        canvas.drawRect(Rect.fromLTWH(stemX(noteXs[i]) - 0.6, stemTop, stemX(noteXs[j]) - stemX(noteXs[i]) + 1.2, beamH), fill);
        final deepest = beamCounts.sublist(i, j + 1).reduce(math.max);
        for (var level = 1; level < deepest; level++) {
          final y = stemTop + level * gap;
          for (var k = i; k <= j; k++) {
            if (beamCounts[k] <= level) continue;
            final left = k > i && beamCounts[k - 1] > level;
            final right = k < j && beamCounts[k + 1] > level;
            if (right) {
              canvas.drawRect(Rect.fromLTWH(stemX(noteXs[k]) - 0.6, y, stemX(noteXs[k + 1]) - stemX(noteXs[k]) + 1.2, beamH), fill);
            } else if (!left) {
              final w = math.min(6.0, step * 0.45);
              final x0 = k < j ? stemX(noteXs[k]) - 0.6 : stemX(noteXs[k]) - w + 0.6;
              canvas.drawRect(Rect.fromLTWH(x0, y, w, beamH), fill);
            }
          }
        }
      }
      i = j + 1;
    }
    final label = rhythm.tupletLabel;
    if (label != null) {
      final y = stemTop - h * 0.14;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontFamily: 'Roboto', fontSize: math.max(8, h * 0.28), fontWeight: FontWeight.w600, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, y - tp.height / 2));
      // Unbeamed tuplets (quarters, halves) get a bracket, so the number does not hang in the air.
      if (beamCounts.every((b) => b == 0) && noteXs.isNotEmpty && noteXs.last > noteXs.first) {
        final first = noteXs.first, last = noteXs.last;
        final w = label.length * h * 0.2 + 6;
        final br = Path()
          ..moveTo(first, y + 4)
          ..lineTo(first, y)
          ..lineTo(size.width / 2 - w / 2, y)
          ..moveTo(size.width / 2 + w / 2, y)
          ..lineTo(stemX(last), y)
          ..lineTo(stemX(last), y + 4);
        canvas.drawPath(br, stroke(0.9));
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => !old.rhythm.sameAs(rhythm) || old.color != color || old.denominator != denominator;
}

/// The note value button on the metronome screen: the current figure in notation; opens the grid. With «Лесенка
/// делений» it shows the ladder's current step (PRD 6.2.6: the chip shows the step).
class RhythmChip extends StatelessWidget {
  const RhythmChip({super.key});

  static double glyphWidth(RhythmInfo r) {
    final o = r.onsets;
    return o.length <= 1 && o.firstOrNull == 0 ? 14 : math.min(9, o.length + 1) * 7.0 + 6;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final shown = metronome.ladderRhythm ?? metronome.currentRhythm;
    // Canvas: a 36 pt chip with «♫» 18 pt; a chosen figure is drawn in notation instead.
    final plain = shown.span == 1 && shown.isPlain && shown.grid == 1;
    return Pressable(
      onTap: () => app.sheet = const AppSheet('metroRhythm'),
      label: 'Ритм: ${shown.spokenName}',
      child: SizedBox(
        height: 36,
        child: ShapeBox(
          shape: const SwiftShape.rounded(18),
          fills: const [SwiftFill(TruverColors.fill)],
          strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Center(
              widthFactor: 1,
              child: plain
                  ? Text('♫', textScaler: TextScaler.noScaling, style: Typo.inter(18, TypoWeight.regular, TruverColors.textBody))
                  : SizedBox(
                      width: glyphWidth(shown),
                      height: 22,
                      child: RhythmGlyph(rhythm: shown, denominator: metronome.meter.denominator),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Ритм»: all figures by section with jump chips and «Недавние», one tap chooses and closes (Soundbrenner-style).
/// With `beat` the choice applies to that beat only («Как у всех долей» clears it).
class RhythmSheet extends StatefulWidget {
  const RhythmSheet({super.key, this.beat});
  final int? beat;

  @override
  State<RhythmSheet> createState() => _RhythmSheetState();
}

class _RhythmSheetState extends State<RhythmSheet> {
  static const _recentKey = 'rhythm.recent';
  final Map<String, GlobalKey> _sections = {};

  List<String> _recentIds(SettingsStore store) {
    try {
      final raw = store.getString(_recentKey);
      return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  List<RhythmInfo> _recent(SettingsStore store) => [
    for (final id in _recentIds(store))
      if (RhythmLibrary.byId(id) case final r? when widget.beat == null || r.span == 1) r,
  ];

  void _remember(SettingsStore store, RhythmInfo r) {
    final ids = _recentIds(store)..remove(r.id);
    ids.insert(0, r.id);
    store.setString(_recentKey, jsonEncode(ids.take(8).toList()));
  }

  GlobalKey _key(String id) => _sections.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final metronome = app.metronome;
    final beat = widget.beat;
    final ladder = metronome.state.modes.subdivision == ModeSubdivision.ladder;
    // Nothing is marked while the ladder leads (the chip shows its step).
    final RhythmInfo? current = ladder ? null : (beat != null ? metronome.beatRhythm(beat) : metronome.currentRhythm);
    final groups = [
      for (final g in RhythmLibrary.groups)
        if (RhythmLibrary.figures(g.id).any((r) => beat == null || r.span == 1)) g,
    ];
    final recent = _recent(app.store);
    final own = metronome.meter.beatRhythms?.where((e) => e != null).length ?? 0;
    return DesignSheet(
      title: beat != null ? 'Доля ${beat + 1} · ритм' : 'Ритм',
      height: 784,
      close: () => app.sheet = null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Jump to a section: 127 figures were nine screens of scrolling.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final g in groups) ...[
                  if (g != groups.first) const SizedBox(width: 6),
                  Pressable(
                    onTap: () {
                      final ctx = _sections[g.id]?.currentContext;
                      if (ctx != null) Scrollable.ensureVisible(ctx, duration: Motion.base, curve: Motion.out);
                    },
                    child: Chip(text: g.title, style: ChipStyle.muted),
                  ),
                ],
              ],
            ),
          ),
          if (ladder) ...[
            const SizedBox(height: 16),
            SwiftText(
              'Сейчас деление ведёт «Лесенка делений» — выбор выключит её',
              style: Typo.caption.copyWith(color: TruverColors.sharp),
            ),
          ],
          if (beat != null) ...[
            const SizedBox(height: 16),
            Pressable(
              onTap: () {
                metronome.setBeatRhythm(null, beat);
                app.sheet = null;
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ShapeBox(
                  shape: SwiftShape.capsule,
                  fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                  strokes: [
                    SwiftStroke(current == null ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true),
                  ],
                  child: SizedBox(
                    height: 48,
                    child: Center(child: Text('Как у всех долей', style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody))),
                  ),
                ),
              ),
            ),
          ] else if (own > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'У $own ${MetronomeController.plural(own, 'доли', 'долей', 'долей')} свой ритм',
                  style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary),
                ),
                const Spacer(),
                Pressable(
                  onTap: metronome.clearBeatRhythms,
                  child: const Chip(text: 'Сбросить'),
                ),
              ],
            ),
          ],
          // Swing and the ME-8 second track (the canvas «Размер и деление» has no place for them).
          if (widget.beat == null) ...[const SizedBox(height: 16), const SwingCard(), const SizedBox(height: 16), const PolyTrackSection()],
          if (recent.isNotEmpty) ...[const SizedBox(height: 16), _section(app, 'Недавние', recent, current, 'recent')],
          for (final g in groups) ...[
            const SizedBox(height: 16),
            // A single beat takes only one-beat figures.
            _section(
              app,
              g.title,
              [
                for (final r in RhythmLibrary.figures(g.id))
                  if (beat == null || r.span == 1) r,
              ],
              current,
              g.id,
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(AppModel app, String title, List<RhythmInfo> items, RhythmInfo? current, String id) {
    final denominator = app.metronome.meter.denominator;
    final rows = <Widget>[];
    for (var start = 0; start < items.length; start += 4) {
      if (start > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < 4; c++) ...[
                if (c > 0) const SizedBox(width: 8),
                Expanded(child: start + c < items.length ? _cell(app, items[start + c], current, denominator) : const SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      key: _key(id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwiftText('$title · ${items.length}', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _cell(AppModel app, RhythmInfo r, RhythmInfo? current, int denominator) {
    final selected = current != null && (current.id == r.id || (current.isPlain && r.isPlain && current.grid == r.grid));
    final caption = _caption(r);
    return Pressable(
      label: r.spokenName,
      selected: selected,
      onTap: () {
        final metronome = app.metronome;
        if (metronome.state.modes.subdivision == ModeSubdivision.ladder) {
          // Through `modes`: the engine restarts with the ladder off (setting `state` did not reach it).
          metronome.updateModes((m) => m.subdivision = ModeSubdivision.none);
        }
        final beat = widget.beat;
        if (beat != null) {
          metronome.setBeatRhythm(r, beat);
        } else {
          metronome.setRhythm(r);
        }
        _remember(app.store, r);
        app.sheet = null;
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: ShapeBox(
          shape: const SwiftShape.rounded(14, continuous: true),
          fills: [selected ? const SwiftFill(TruverColors.textPrimary) : const SwiftFill.gradient(TruverGradients.cardFill)],
          strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: RhythmGlyph(
                    rhythm: r,
                    color: selected ? TruverColors.background : TruverColors.textPrimary,
                    denominator: denominator,
                  ),
                ),
                // SwiftUI's empty `Text("")` under the glyph measures 14.3 pt on the iOS screenshot (a line of the
                // system font, not of Inter 9).
                if (caption.isEmpty)
                  const SizedBox(height: 2 + 14.3)
                else ...[
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SwiftText(
                      caption,
                      maxLines: 1,
                      softWrap: false,
                      style: Typo.inter(
                        9,
                        TypoWeight.regular,
                        selected ? TruverColors.background.withValues(alpha: 0.7) : TruverColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Small caption under multi-beat and named figures («2 доли», «клаве»).
  String _caption(RhythmInfo r) {
    if (r.name != r.shortName && r.group != 'values' && r.group != 'sixteenths' && r.group != 'triplets') return r.name;
    return switch (r.span) {
      0 => 'такт',
      1 => '',
      2 => '2 доли',
      3 || 4 => '${r.span} доли',
      _ => '${r.span} долей',
    };
  }
}

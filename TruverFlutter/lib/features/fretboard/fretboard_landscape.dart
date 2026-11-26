/// Port of the landscape board of Truver/Sources/Features/Fretboard/FretboardScreen.swift (canvas «Гриф — альбом»,
/// «низкая струна сверху», «путь — альбом»; 844 × 390).
///
/// Header (top 16, from x 50, 760 wide): «Вид» 44, title 15 medium, view chip, «Сыграть» 48. Neck 780 × 300 at
/// (50, 82): the portrait neck turned −90° (nut on the left), +90° for the left-handed.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/landscape.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'fret_menu.dart';
import 'fret_modes.dart';
import 'fretboard_controller.dart';
import 'neck_portrait.dart';

class FretboardLandscape extends StatefulWidget {
  const FretboardLandscape({super.key});

  @override
  State<FretboardLandscape> createState() => _FretboardLandscapeState();
}

class _FretboardLandscapeState extends State<FretboardLandscape> {
  bool _menu = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    return LandscapeCanvas(
      child: Stack(
        children: [
          if (_canvas(app)) ...[
            // Canvas FixLandScale: the scale on the whole neck, turned −90° and scrolled along x.
            Board(x: 32, y: 16, width: 780, child: SizedBox(height: 48, child: _canvasHeader(app))),
            Positioned.fill(
              child: LandscapeWholeNeck(
                fretCount: (app.instrument['fretCount'] as num?)?.toInt() ?? 24,
                courses: app.courseCount,
                openCells: fretboard.cells().where((c) => c.fret == 0).toList(),
                capoShift: fretboard.fretsFromCapo ? ((app.instrument['capo'] as num?)?.toInt() ?? 0) : 0,
                neck: (lo, hi) {
                  final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
                  return NeckPortrait(
                    courses: app.courseCount,
                    lo: lo,
                    hi: hi,
                    cells: fretboard.cells(),
                    capo: capo > 0 ? capo : null,
                    playingMode: fretboard.isPlaying,
                    labelRotation: 90,
                    sizing: NoteSizing.scale,
                    openBand: false,
                    onTap: (course, fret) => fretboard.tap(course, fret),
                    onLongPress: (course, fret, _) {
                      fretboard.menuSpot = NeckSpot(course, fret);
                      setState(() => _menu = true);
                    },
                  );
                },
              ),
            ),
          ] else ...[
            Board(x: 50, y: 16, width: 760, child: SizedBox(height: 48, child: _header(app))),
            Positioned(left: 50, top: 82, width: 780, height: 300, child: ClipRect(child: _neck(app))),
          ],
          if (_menu && fretboard.menuSpot != null) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
                child: ColoredBox(color: const Color(0xFF030304).withValues(alpha: 0.55)),
              ),
            ),
            // A turned neck reports unturned points: the landscape menu opens mid-board.
            Positioned(
              left: math.min(math.max(16.0, LandscapeCanvas.size.width / 2 - 116), LandscapeCanvas.size.width - 248),
              top: 40,
              child: NoteMenu(spot: fretboard.menuSpot!, close: _closeMenu),
            ),
          ],
          Positioned(
            left: 0,
            right: 0,
            top: 20,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: Motion.base,
                child: fretboard.toast == null
                    ? const SizedBox.shrink()
                    : Center(key: ValueKey(fretboard.toast), child: DesignToast(icon: AppIcon.refresh, text: fretboard.toast!)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _closeMenu() {
    setState(() => _menu = false);
    final app = AppScope.read(context);
    if (app.sheet == null) app.fretboard.menuSpot = null;
  }

  bool _canvas(AppModel app) {
    final f = app.fretboard;
    return f.mode == FretMode.scale && f.pathKind == null && !f.isTraining && !f.settings.leftHanded;
  }

  /// Canvas FixLandScale header (32, 16, 780 wide): «Вид» 44, «G · Мажор» 15 medium, «Гриф | Таб», legend, ▶ 48.
  Widget _canvasHeader(AppModel app) {
    final f = app.fretboard;
    final title = () {
      final name = f.scaleTitle;
      final i = name.indexOf(' (');
      final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
      return (i < 0 ? name : name.substring(0, i)) + (capo > 0 ? ' · капо $capo' : '');
    }();
    final names = f.legendNames;
    Widget item(double dot, Color color, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: dot, height: dot, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 5),
          NoteText(text, maxLines: 1, style: Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
        ]);
    return Row(children: [
      RoundIconButton(icon: AppIcon.rename, size: 44, label: 'Вид и подписи', onTap: () => app.sheet = const AppSheet('fretView')),
      const SizedBox(width: 10),
      Pressable(
        scale: 1,
        onTap: () => app.sheet = const AppSheet('fretScale'),
        child: NoteText(title, maxLines: 1, style: Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 120,
        child: Segments<bool>(
          options: const [(false, 'Гриф'), (true, 'Таб')],
          selection: f.tabView,
          onChanged: (tab) {
            if (tab && f.pathKind == null) f.startPath(null);
            f.tabView = tab;
          },
        ),
      ),
      const Spacer(),
      const SizedBox(width: 2),
      item(12, NoteStyle.gold, '${names.tonic} тоника'),
      if (names.chord.isNotEmpty) ...[const SizedBox(width: 12), item(9, const Color.fromRGBO(143, 196, 255, 0.95), '${names.chord} аккорд')],
      const SizedBox(width: 12),
      item(7, const Color.fromRGBO(150, 156, 166, 0.7), 'остальные'),
      const SizedBox(width: 10),
      PrimaryRoundButton(
        icon: f.isPlaying ? AppIcon.pause : AppIcon.play,
        size: 48,
        iconSize: 20,
        label: f.isPlaying ? 'Пауза' : 'Сыграть',
        onTap: f.togglePlayback,
      ),
    ]);
  }

  String _scaleTitle(AppModel app) {
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    return app.fretboard.scaleTitle + (capo > 0 ? ' · капо $capo' : '') + (app.fretboard.pathKind != null ? ' · путь' : '');
  }

  String _title(AppModel app) {
    final f = app.fretboard;
    switch (f.mode) {
      case FretMode.scale:
        return _scaleTitle(app);
      case FretMode.chord:
        final name = f.chordName();
        final v = f.currentVoicing;
        return v == null ? name : '$name · ${f.voicingTitle(v)}';
      case FretMode.search:
        if (f.search.pitches.length < 3) return 'Поиск · отметьте ноты';
        final best = f.search.chords.firstOrNull;
        return best == null ? 'Ничего не найдено' : Typo.compactChordName(best.name);
      case FretMode.progression:
        final p = f.progression;
        if (p.current < p.voiced.length) return '${Typo.compactChordName(p.voiced[p.current].name)} · ${p.name}';
        return p.name;
    }
  }

  String _pathKindTitle(AppModel app) {
    final f = app.fretboard;
    return switch (f.pathKind) {
      PathKind.threePerString => '3 ноты на струну',
      PathKind.fourDiagonal => '4 ноты наискосок',
      PathKind.oneString => f.pathNotes.isEmpty ? 'По одной струне' : 'По одной струне · ${app.courseCount - f.pathNotes.first.course}-я',
      null => '',
    };
  }

  String _viewLabel(AppModel app) {
    final f = app.fretboard;
    return switch (f.settings.neckView) {
      NeckDisplay.position => f.positions.isEmpty
          ? 'Позиция —'
          : (f.positionAnchor != null ? 'От ноты' : 'Позиция ${f.settings.positionNumber}/${f.positions.length}'),
      NeckDisplay.window => 'Своё окно',
      NeckDisplay.wholeNeck => 'Весь гриф',
    };
  }

  Widget _header(AppModel app) {
    final f = app.fretboard;
    final children = <Widget>[];
    if (f.pathKind != null && f.mode == FretMode.scale) {
      children.addAll([
        RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Назад', onTap: () {
          if (f.isPlaying) f.togglePlayback();
          f.pathKind = null;
        }),
        Flexible(child: Text.rich(Typo.notes(_scaleTitle(app), Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)), maxLines: 1)),
        Pressable(onTap: () => app.sheet = const AppSheet('fretPath'), child: HeaderChip(text: _pathKindTitle(app), icon: AppIcon.chevronDown)),
        const Spacer(),
        Chip(text: '${(f.pathIndex ?? -1) + 1} / ${f.pathNotes.length}', style: ChipStyle.muted),
      ]);
    } else {
      children.addAll([
        RoundIconButton(icon: AppIcon.sliders, size: 44, label: 'Вид и подписи', onTap: () => app.sheet = const AppSheet('fretView')),
        Flexible(
          child: Pressable(
            scale: 1,
            enabled: f.mode == FretMode.scale,
            onTap: () => app.sheet = const AppSheet('fretScale'),
            child: Text.rich(Typo.notes(_title(app), Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)), maxLines: 1),
          ),
        ),
        const Spacer(),
        if (f.mode == FretMode.scale)
          Builder(
            builder: (context) => Pressable(
              onTap: () => showFretMenu(context, [
                FretMenuItem('Весь гриф', () => f.selectPosition(null)),
                for (final p in f.positions) FretMenuItem('Позиция ${p.number} · лады ${p.lo}–${p.hi}', () => f.selectPosition(p.number)),
              ]),
              child: HeaderChip(text: _viewLabel(app)),
            ),
          ),
        if (f.mode == FretMode.chord) ...[
          RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Предыдущее расположение', onTap: () {
            if (f.voicingIndex > 0) {
              f.voicingIndex -= 1;
              f.playVoicing();
            }
          }),
          RoundIconButton(icon: AppIcon.chevronRight, size: 44, label: 'Следующее расположение', onTap: () {
            if (f.voicingIndex + 1 < f.voicings.length) {
              f.voicingIndex += 1;
              f.playVoicing();
            }
          }),
        ],
        if (f.mode == FretMode.progression) ...[
          RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Предыдущий аккорд', onTap: () => f.progression.select(math.max(0, f.progression.current - 1))),
          RoundIconButton(
              icon: AppIcon.chevronRight,
              size: 44,
              label: 'Следующий аккорд',
              onTap: () => f.progression.select(math.min(f.progression.voiced.length - 1, f.progression.current + 1))),
        ],
      ]);
    }
    if (f.isDroning) children.add(RoundIconButton(icon: AppIcon.waveform, size: 44, label: 'Выключить бурдон', onTap: f.stopDrone));
    final playing = f.mode == FretMode.progression ? f.progression.isPlaying : f.isPlaying;
    children.add(PrimaryRoundButton(
      icon: playing ? (f.mode == FretMode.progression ? AppIcon.stop : AppIcon.pause) : AppIcon.play,
      size: 48,
      iconSize: 20,
      label: playing ? 'Пауза' : 'Сыграть',
      onTap: () => switch (f.mode) {
        FretMode.chord => f.playVoicing(),
        FretMode.progression => f.progression.toggle(),
        _ => f.togglePlayback(),
      },
    ));
    return Row(children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0 && children[i] is! Spacer && children[i - 1] is! Spacer) const SizedBox(width: 10), children[i]],
    ]);
  }

  /// The whole neck (or the path) on the 780 pt board; a position keeps its place among 12–13 frets.
  Widget _neck(AppModel app) {
    final f = app.fretboard;
    final s = f.settings;
    final fretCount = (app.instrument['fretCount'] as num?)?.toInt() ?? 24;
    final isPath = f.mode == FretMode.scale && f.pathKind != null;
    final whole = isPath || (s.neckView == NeckDisplay.wholeNeck && !f.hasPreview && (f.mode == FretMode.scale || f.mode == FretMode.search));
    (int, int) frets;
    if (whole) {
      frets = (0, fretCount);
    } else {
      final r = f.visibleFrets;
      if (f.mode != FretMode.scale || f.hasPreview) {
        frets = r;
      } else {
        final hi = math.min(fretCount, math.max(r.$2 + 3, math.max(0, r.$1 - 3) + 12));
        frets = (math.max(0, math.min(r.$1 - 3, hi - 12)), hi);
      }
    }
    final rotation = s.leftHanded ? 90.0 : -90.0;
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    final preview = f.chordPreview;
    final Set<int> muted;
    if (preview != null) {
      muted = {for (var i = 0; i < preview.frets.length; i++) if (preview.frets[i] == null) i};
    } else if (f.mode == FretMode.chord) {
      final v = f.currentVoicing;
      muted = v == null ? {} : {for (var i = 0; i < v.frets.length; i++) if (v.frets[i] == null) i};
    } else if (f.mode == FretMode.progression) {
      muted = f.progression.mutedCourses;
    } else {
      muted = {};
    }
    final path = isPath ? f.pathNotes : const <FretNote>[];
    return RotatedBox(
      quarterTurns: s.leftHanded ? 1 : 3,
      child: NeckPortrait(
        courses: app.courseCount,
        lo: frets.$1,
        hi: frets.$2,
        cells: f.cells(),
        // Course 0 (lowest) lands at the bottom after −90° and at the top after +90°: flipped for «низкая струна сверху».
        leftHanded: s.leftHanded != s.lowStringOnTop,
        capo: capo > 0 ? capo : null,
        strumming: f.strumming,
        strumOrder: f.strumOrder,
        strumToken: f.strumToken,
        chordMode: f.selectedChord != null || f.mode == FretMode.progression || f.chordPreview != null,
        path: [for (final n in path) NeckPathNote(n.course, n.fret)],
        pathLabels: [for (final n in path) f.pathLabel(n)],
        pathCurrent: isPath ? f.pathIndex : null,
        playingMode: f.isPlaying,
        mutedCourses: muted,
        labelRotation: -rotation,
        fan: f.data?.fan,
        overview: whole,
        onTap: (course, fret) {
          if (f.mode == FretMode.search) f.toggleMark(course, fret);
          f.tap(course, fret);
        },
        onLongPress: (course, fret, _) {
          f.menuSpot = NeckSpot(course, fret);
          setState(() => _menu = true);
        },
      ),
    );
  }
}

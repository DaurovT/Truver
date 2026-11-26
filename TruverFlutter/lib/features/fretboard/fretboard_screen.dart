/// Port of Truver/Sources/Features/Fretboard/FretboardScreen.swift
///
/// «Гриф и гаммы» by the canvas (390 × 844): scale chip + «Вид и подписи» (top 100), neck 346 × 396 (top 156),
/// key chords (top 566, 52 pt), position navigation and «Сыграть» (top 626, 52 pt). Also the sheets «Гамма»,
/// «Вид и подписи», «Проигрывание» and the playback controls they share with the path sheet.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'fret_menu.dart';
import 'fret_sheets.dart';
import 'fret_modes.dart';
import 'fret_tab_view.dart';
import 'fretboard_controller.dart';
import 'neck_portrait.dart';
import 'progression_views.dart';
import '../tour/coach_marks.dart';
export 'fret_sheets.dart';

/// Debug `-chordLibrary`: the library opens with the screen.
bool fretOpenLibraryOnStart = false;

/// Debug `-fretLoupe c:f`: the loupe is held over that cell (canvas S8Loupe).
NeckSpot? fretLoupeOnStart;

/// Debug `-capo N`: the capo notice stays on screen (canvas FretCapo).
bool fretCapoNoticeOnStart = false;

/// Debug `-leftHanded`: the left-handed notice stays on screen (canvas FretLeftHanded).
bool fretLeftNoticeOnStart = false;

class FretboardScreen extends StatefulWidget {
  const FretboardScreen({super.key});

  @override
  State<FretboardScreen> createState() => _FretboardScreenState();
}

class _FretboardScreenState extends State<FretboardScreen> {
  final _screenKey = GlobalKey();
  double _zoom = 1;
  double _pinchBase = 1;
  bool _showZoom = false;
  Timer? _zoomTimer;
  bool _editingWindow = false;
  Offset? _menuPoint;

  /// FB-20: the neck follows the current path note until the user scrolls it.
  bool _autoScroll = true;
  bool _showLibrary = false;

  /// «Гаммы ›» opens the library scrolled to «Подходящие гаммы».
  bool _libraryAtScales = false;
  bool _namingProgression = false;
  final bool _renamingProgression = false;
  final _progressionName = TextEditingController();

  /// Frets on screen while the custom window is edited.
  (int, int)? _windowContext;

  @override
  void initState() {
    super.initState();
    if (fretOpenLibraryOnStart) _showLibrary = true;
    if (fretLoupeOnStart != null) {
      final spot = fretLoupeOnStart!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final app = AppScope.read(context);
        // The cell's centre on the scrolling neck at the top (board at 42, 252; 1–12 in 356 pt).
        final g = NeckGeometry(size: const Size(ScrollingNeck.boardWidth, 1), courses: app.courseCount, lo: 0, hi: 1, leftHanded: app.fretboard.settings.leftHanded);
        final scale = 357 / NeckGeometry.unit(12);
        final y = 252 + scale * (NeckGeometry.unit(spot.fret - 1) + NeckGeometry.unit(spot.fret)) / 2 - 1;
        setState(() => _scrub = (spot, Offset((app.fretboard.settings.leftHanded ? 18 : 22) + 20 + g.x(spot.course), y - 47)));
      });
    }
    if (fretCapoNoticeOnStart || fretLeftNoticeOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCapoNotice((AppScope.read(context).instrument['capo'] as num?)?.toInt() ?? 0, hold: true);
        if (fretLeftNoticeOnStart) _showNotice('Для левши: низкая струна справа', hold: true);
      });
    }
  }

  /// Canvas S8Loupe: the cell under a held finger and its centre in the screen's coordinates.
  (NeckSpot, Offset)? _scrub;

  /// Canvas S8Loupe: a 46 pt ring under the finger and a 200 × 150 loupe 220 pt above it.
  List<Widget> _loupe(AppModel app) {
    final scrub = _scrub;
    if (scrub == null) return const [];
    final (spot, point) = scrub;
    final courses = app.courseCount;
    final c = spot.course, f = spot.fret;
    String name(int course) => app.stringName(course).replaceAll(RegExp(r'[0-9]'), '');
    final note = app.fretboard.noteInfo(spot)?.plain ?? '';
    const xs = [31.0, 100.5, 170.5];
    final left = math.min(math.max(16.0, point.dx - 100), 390.0 - 216);
    return [
      Positioned(
        left: point.dx - 23,
        top: point.dy - 23,
        width: 46,
        height: 46,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: TruverColors.textPrimary.withValues(alpha: 0.18),
              border: Border.all(color: TruverColors.textPrimary.withValues(alpha: 0.5), width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        left: left,
        top: point.dy - 220,
        width: 200,
        height: 150,
        child: IgnorePointer(
          child: ShapeBox(
            shape: const SwiftShape.rounded(22),
            shadows: [SwiftShadow(TruverColors.black(0.7), 20, y: 20)],
            fills: const [SwiftFill(Color(0xFF2B2F36))],
            strokes: [SwiftStroke(TruverColors.textPrimary.withValues(alpha: 0.7), width: 2, inside: true)],
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(clipBehavior: Clip.none, children: [
                for (var d = -1; d <= 1; d++)
                  if (c + d >= 0 && c + d < courses) ...[
                    Positioned(
                      left: xs[d + 1] - (d < 0 ? 2.0 : 1.5),
                      top: 14,
                      width: d < 0 ? 4 : 3,
                      height: 122,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF7D8186), Color(0xFFE6E8EA), Color(0xFF7D8186)])),
                      ),
                    ),
                    Positioned(
                      left: xs[d + 1] - 10,
                      top: -2,
                      width: 20,
                      child: Center(child: NoteText(name(c + d), style: Typo.inter(11, TypoWeight.regular, TruverColors.textSecondary))),
                    ),
                  ],
                for (var i = 0; i < 3; i++) ...[
                  Positioned(
                    left: 6,
                    top: 20.0 + i * 46,
                    width: 184,
                    height: 3,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF6F7378), Color(0xFFFFFFFF), Color(0xFF55595E)],
                        ),
                      ),
                    ),
                  ),
                  if (i < 2)
                    Positioned(left: 6, top: 36.0 + i * 46, child: Text('${math.max(1, f) + i}', style: Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary))),
                ],
                Positioned(
                  left: 78,
                  top: 21,
                  width: 44,
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TruverColors.textPrimary,
                      boxShadow: [BoxShadow(color: TruverColors.textPrimary.withValues(alpha: 0.25), spreadRadius: 4)],
                    ),
                    child: Center(child: NoteText(note, scale: false, style: Typo.fixed(16, TypoWeight.bold, const Color(0xFF0C0D0F)))),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ];
  }

  /// «D3 · 5-я струна (A), 5-й лад» / «ведите палец — лупа следует, отпустите — нота поставлена».
  Widget _scrubFooter(AppModel app, NeckSpot spot) {
    final info = app.fretboard.noteInfo(spot);
    final open = app.stringName(spot.course).replaceAll(RegExp(r'[0-9]'), '');
    final place = spot.fret == 0 ? 'открытая' : '${spot.fret}-й лад';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52, minWidth: double.infinity),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        NoteText('${info?.chroma ?? ''} · ${app.courseCount - spot.course}-я струна ($open), $place',
            maxLines: 1, style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary)),
        const SizedBox(height: 3),
        SwiftText('ведите палец — лупа следует, отпустите — нота поставлена', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
      ]),
    );
  }

  String? _capoNotice;
  int? _lastCapo;
  bool? _lastLeft;
  Timer? _capoTimer;

  /// Canvas FretCapo notice, 3 s.
  void _showCapoNotice(int capo, {bool hold = false}) {
    if (capo <= 0) return;
    _showNotice('Капо на $capo-м ладу · ноты и номера ладов — от капо', hold: hold);
  }

  /// Canvas FretCapo / FretLeftHanded notice at 640 for 3 s (held in screenshots).
  void _showNotice(String text, {bool hold = false}) {
    setState(() => _capoNotice = text);
    _capoTimer?.cancel();
    _capoTimer = Timer(Duration(seconds: hold ? 30 : 3), () {
      if (mounted) setState(() => _capoNotice = null);
    });
  }

  /// Left 24, right 24, top 640: #26282d .96, r 16, hairline, 13 medium, padding 11 16, shadow 0 14 30 .6.
  Widget _capoNoticeView(String text) => ShapeBox(
        shape: const SwiftShape.rounded(16),
        shadows: [SwiftShadow(TruverColors.black(0.6), 15, y: 14)],
        fills: const [SwiftFill(Color.fromRGBO(38, 40, 45, 0.96))],
        strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: SwiftText(text, style: Typo.inter(13, TypoWeight.medium, TruverColors.textBody)),
        ),
      );

  @override
  void dispose() {
    _zoomTimer?.cancel();
    _capoTimer?.cancel();
    _progressionName.dispose();
    super.dispose();
  }

  FretboardController get fretboard => AppScope.read(context).fretboard;

  /// Height of the shell below this screen (tuning pill, tab bar, home indicator).
  double _belowScreen = 0;

  void _measureBelow() {
    final box = _screenKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final below = math.max(0.0, MediaQuery.sizeOf(context).height - bottom);
    if ((below - _belowScreen).abs() > 0.5) setState(() => _belowScreen = below);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fretboard = app.fretboard;
    final mode = fretboard.mode;
    if (_showLibrary) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureBelow();
      });
    }
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    if (_lastCapo != null && _lastCapo != capo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCapoNotice(capo);
      });
    }
    _lastCapo = capo;
    final left = fretboard.settings.leftHanded;
    if (_lastLeft != null && _lastLeft != left && left) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNotice('Для левши: низкая струна справа');
      });
    }
    _lastLeft = left;
    final legacy = mode == FretMode.scale && (fretboard.isTraining || fretboard.pathKind != null || _editingWindow);
    final children = <Widget>[
      // Canvas FretLeftHanded keeps the title; the mirror is announced by a notice.
      ScreenHeader(title: 'Гриф и гаммы', subtitle: app.title),
      // Canvas: the mode segments at 108, 14 below the 44 pt header row.
      Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 14),
        child: Segments<FretMode>(
          options: const [(FretMode.scale, 'Гамма'), (FretMode.chord, 'Аккорд'), (FretMode.search, 'Поиск'), (FretMode.progression, 'Прогрессия')],
          selection: mode,
          onChanged: (value) {
            // «Гамма» while on the path leaves the path (iPhone UX check: it stayed in «· путь»).
            if (fretboard.pathKind != null && (value == FretMode.scale || value != fretboard.mode)) {
              if (fretboard.isPlaying) fretboard.stopPlayback();
              if (value == FretMode.scale) fretboard.pathKind = null;
            }
            fretboard.mode = value;
          },
        ),
      ),
      if (legacy) ...[
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
          child: _editingWindow ? _windowBar(app) : _scaleRow(app),
        ),
        Expanded(
          child: Padding(padding: const EdgeInsets.only(left: 22, right: 22, top: 12), child: _neck(app)),
        ),
        ..._bottom(app),
      ] else
        ..._canvasContent(app),
    ];

    return Stack(
      key: _screenKey,
      clipBehavior: Clip.none,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ..._loupe(app),
        if (_capoNotice != null)
          Positioned(left: 24, right: 24, top: 640 - 47, child: IgnorePointer(child: Align(alignment: Alignment.topCenter, child: _capoNoticeView(_capoNotice!)))),
        if (fretboard.noteSpot != null && mode == FretMode.scale && !legacy)
          Positioned(left: 0, right: 0, bottom: 0, height: 234, child: _notePanel(app, fretboard.noteSpot!)),
        if (_menuPoint != null && fretboard.menuSpot != null) Positioned.fill(child: _noteMenu(app, fretboard.menuSpot!)),
        if (_namingProgression)
          Positioned.fill(
            child: TextFieldAlert(
              title: 'Название прогрессии',
              controller: _progressionName,
              cancel: () => setState(() => _namingProgression = false),
              save: () {
                if (_renamingProgression) {
                  fretboard.progression.renameActive(_progressionName.text);
                } else {
                  fretboard.progression.saveAs(_progressionName.text);
                }
                setState(() => _namingProgression = false);
              },
            ),
          ),
        // The library scrolls on under the tuning pill and the tab bar, as the iOS ScrollView does.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: -_belowScreen,
          child: IgnorePointer(
            ignoring: !_showLibrary,
            child: AnimatedSlide(
              offset: _showLibrary ? Offset.zero : const Offset(1, 0),
              duration: Motion.base,
              curve: Motion.out,
              child: _showLibrary
                  ? ChordLibraryView(atScales: _libraryAtScales, bottomInset: _belowScreen, close: () => setState(() => _showLibrary = false))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 60,
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: Motion.base,
              switchInCurve: Motion.out,
              switchOutCurve: Motion.out,
              child: fretboard.toast == null
                  ? const SizedBox.shrink()
                  : Center(key: ValueKey(fretboard.toast), child: DesignToast(icon: AppIcon.refresh, text: fretboard.toast!)),
            ),
          ),
        ),
      ],
    );
  }

  // MARK: Canvas 2026-11-25 (S6/S7/S8Whole, FixFretWhole, FretCapo, FretLeftHanded, FlowNote1, FretChordTab,
  // FixFretSearch, FlowNote3)

  (int, int) _shownFretRange = (1, 12);
  bool _dismissedNoPositions = false;

  int _fretCount(AppModel app) => (app.instrument['fretCount'] as num?)?.toInt() ?? 24;

  List<Widget> _canvasContent(AppModel app) {
    final fretboard = app.fretboard;
    Widget row(Widget pill) => Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 8),
          child: SizedBox(
            height: 38,
            child: Row(children: [
              Expanded(child: pill),
              const SizedBox(width: 8),
              _neckTabSwitch(app),
              const SizedBox(width: 8),
              RoundIconButton(icon: AppIcon.rename, size: 36, label: 'Вид и подписи', onTap: () => app.sheet = const AppSheet('fretView')),
            ]),
          ),
        );
    switch (fretboard.mode) {
      case FretMode.scale:
        final edited = fretboard.isEdited;
        final scaleRow = row(CoachAnchor(
          id: CoachAnchors.scalePill,
          child: _pickerPill(app, _scalePillTitle(app), edited: edited, onTap: () => app.sheet = const AppSheet('fretScale')),
        ));
        if (fretboard.noteSpot != null) {
          // Canvas FlowNote1: no legend, the neck at 200 (30 + 370), the note panel over the tab bar.
          return [scaleRow, Padding(padding: const EdgeInsets.only(top: 8), child: _wholeNeck(app, 370, NoteSizing.allNotes)), const Spacer()];
        }
        return [
          scaleRow,
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 10), child: SizedBox(height: 20, child: Opacity(opacity: _scrub == null ? 1 : 0, child: Align(alignment: Alignment.topLeft, child: _legend(app))))),
          _wholeNeck(app, 356, NoteSizing.scale),
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 10), child: CoachAnchor(id: CoachAnchors.keyChords, child: _chordStrip(app))),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
            child: _scrub == null ? _scaleFooter(app) : _scrubFooter(app, _scrub!.$1),
          ),
          const Spacer(),
        ];
      case FretMode.chord:
        // Canvas FretChordTab: chips at 154, neck 400 at 200, «Am7 · баррэ на 5-м» + ‹ › at 622.
        return [
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 8), child: SizedBox(height: 34, child: _chordChips(app))),
          Padding(padding: const EdgeInsets.only(top: 12), child: _modeNeck(app, NoteSizing.large)),
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 22), child: _chordFooter(app)),
          const Spacer(),
        ];
      case FretMode.search:
        // Canvas FixFretSearch: «Отмечено 4 ноты ▾» row, neck 400 at 206 (the result is a sheet).
        return [
          row(_pickerPill(app, _searchTitle(app), onTap: () => app.sheet = const AppSheet('searchResults'))),
          Padding(padding: const EdgeInsets.only(top: 14), child: _modeNeck(app, NoteSizing.large)),
          const Spacer(),
        ];
      case FretMode.progression:
        // Canvas FlowNote3: «A · I–V–vi–IV ▾» row, neck 400 at 204, chords 56 at 616, footer at 686.
        final progressionRow = row(_pickerPill(app, _progressionTitle(app), onTap: () => app.sheet = const AppSheet('fretProgressions')));
        if (fretboard.tabView) return [progressionRow, const Expanded(child: ProgressionTabBody())];
        return [
          progressionRow,
          Padding(padding: const EdgeInsets.only(top: 12), child: _modeNeck(app, NoteSizing.progression)),
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 12), child: _progressionChords(app)),
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 14), child: _progressionFooter(app)),
          const Spacer(),
        ];
    }
  }

  /// «G · Мажор» — the pill drops the scale's parenthesised alias («Мажор (ионийский)»).
  String _scalePillTitle(AppModel app) {
    final name = app.fretboard.scaleTitle;
    final i = name.indexOf(' (');
    final short = i < 0 ? name : name.substring(0, i);
    return short; // canvas FretCapo: the capo is on the neck and in a notice, not in the title
  }

  /// Canvas pill: 36 pt, radius 18, card fill + hairline, 14 medium, chevron 14 tertiary; padding 0 12 0 14, gap 6.
  Widget _pickerPill(AppModel app, String title, {bool edited = false, required VoidCallback onTap}) => Pressable(
        label: title,
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: ShapeBox(
            shape: SwiftShape.capsule,
            fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
            strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
            child: Padding(
              // Canvas: padding 0 12 0 14 inside a 1 pt border.
              padding: const EdgeInsets.only(left: 15, right: 13),
              child: Row(children: [
                if (edited) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: TruverColors.characteristicNote,
                      boxShadow: [BoxShadow(color: TruverColors.characteristicNote, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: NoteText(title, maxLines: 1, style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary)),
                ),
                const SizedBox(width: 6),
                const AppIconView(AppIcon.chevronDown, size: 14, color: TruverColors.textTertiary),
              ]),
            ),
          ),
        ),
      );

  /// «Гриф | Таб» (120 pt).
  Widget _neckTabSwitch(AppModel app) => SizedBox(
        width: 120,
        child: Segments<bool>(
          options: const [(false, 'Гриф'), (true, 'Таб')],
          selection: app.fretboard.tabView,
          onChanged: (tab) {
            final fretboard = app.fretboard;
            if (tab && fretboard.pathKind == null) fretboard.startPath(null);
            fretboard.tabView = tab;
          },
        ),
      );

  /// «● G тоника  ● B D аккорд  ● остальные» (11 pt, dots 12 / 9 / 7, gap 12).
  Widget _legend(AppModel app) {
    final names = app.fretboard.legendNames;
    Widget item(double dot, Color color, String text) => SizedBox(
          height: 13,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: dot, height: dot, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 5),
            NoteText(text, maxLines: 1, style: Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
          ]),
        );
    // The canvas legend starts 2 pt in (inline-flex spans).
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 2),
      item(12, NoteStyle.gold, '${names.tonic} тоника'),
      if (names.chord.isNotEmpty) ...[const SizedBox(width: 12), item(9, const Color.fromRGBO(143, 196, 255, 0.95), '${names.chord} аккорд')],
      const SizedBox(width: 12),
      item(7, const Color.fromRGBO(150, 156, 166, 0.7), 'остальные'),
    ]);
  }

  /// Open strings (fixed row, 30 pt) and the scrolling neck — canvas «весь гриф, листается».
  Widget _wholeNeck(AppModel app, double height, NoteSizing sizing) {
    final fretboard = app.fretboard;
    final lh = fretboard.settings.leftHanded;
    final cells = fretboard.cells();
    final fretCount = _fretCount(app);
    return SizedBox(
      width: 390,
      height: height + 30,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 20,
          top: 0,
          width: 350,
          height: height + 30,
          child: Column(children: [
            _openRow(app, cells.where((c) => c.fret == 0).toList(), lh),
            ScrollingNeck(
              courses: app.courseCount,
              fretCount: fretCount,
              window: (1, math.min(12, fretCount)),
              height: height,
              openRowOutside: true,
              leftHanded: lh,
              capoShift: fretboard.fretsFromCapo ? ((app.instrument['capo'] as num?)?.toInt() ?? 0) : 0,
              onVisible: (lo, hi) {
                fretboard.playFrets = (lo, hi);
                if (_shownFretRange != (lo, hi)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _shownFretRange = (lo, hi));
                  });
                }
              },
              neck: (lo, hi) => _canvasNeck(app, cells, lo, hi, sizing, openBand: false),
            ),
          ]),
        ),
        if (fretboard.positions.isEmpty && !_dismissedNoPositions) Positioned.fill(child: Center(child: _noPositionsCard())),
      ]),
    );
  }

  /// Canvas «Открытые струны»: «0» 11 semibold, circles on #0d0e10 with a 2 pt ring — tonic 24 gold, chord tones 14
  /// blue with the name, the rest 10 grey.
  Widget _openRow(AppModel app, List<NeckCell> cells, bool leftHanded) {
    final fretboard = app.fretboard;
    final boardX = leftHanded ? 18.0 : 22.0;
    final g = NeckGeometry(size: const Size(ScrollingNeck.boardWidth, 30), courses: app.courseCount, lo: 0, hi: 1, leftHanded: leftHanded);
    final plain = fretboard.noteSpot != null;
    return SizedBox(
      width: 350,
      height: 30,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: leftHanded ? 332 : 0,
          width: 18,
          top: 5,
          height: 20,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('0', style: Typo.inter(11, TypoWeight.semibold, TruverColors.textSecondary)),
          ),
        ),
        for (final cell in cells)
          () {
            final tonic = !plain && cell.role == DegreeRole.tonic, chord = !plain && cell.role == DegreeRole.chordTone;
            final size = tonic ? 24.0 : (chord ? 14.0 : 10.0);
            final color = tonic ? NoteStyle.gold : (chord ? const Color(0xFF8FC4FF) : const Color.fromRGBO(150, 156, 166, 0.8));
            final x = boardX + g.x(cell.course);
            return Positioned(
              left: x - size / 2,
              top: 15 - size / 2,
              width: size,
              height: size,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final spot = NeckSpot(cell.course, 0);
                  fretboard.noteSpot = fretboard.noteSpot == spot ? null : spot;
                  fretboard.tap(cell.course, 0);
                },
                child: Opacity(
                  opacity: cell.emphasis == NeckEmphasis.faint ? 0.4 : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0D0E10), border: Border.all(color: color, width: 2)),
                    child: Center(
                      child: tonic || chord
                          ? NoteText(cell.label, scale: false, maxLines: 1, style: Typo.fixed(10, TypoWeight.bold, color))
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            );
          }(),
      ]),
    );
  }

  /// Canvas «Удобных позиций нет» (FretNoPositions).
  Widget _noPositionsCard() => SizedBox(
        width: 310,
        child: ShapeBox(
          shape: const SwiftShape.rounded(20, continuous: true),
          fills: [SwiftFill(const Color(0xFF141518).withValues(alpha: 0.96))],
          strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwiftText('Удобных позиций нет', style: Typo.inter(16, TypoWeight.semibold, TruverColors.textPrimary)),
              const SizedBox(height: 8),
              SwiftText('В этом строе гамма не укладывается в 4 лада. Покажем все ноты на грифе.',
                  textAlign: TextAlign.center, style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary)),
              const SizedBox(height: 14),
              Pressable(
                label: 'Показать все ноты',
                onTap: () => setState(() => _dismissedNoPositions = true),
                child: SizedBox(
                  height: 44,
                  child: ShapeBox(
                    shape: SwiftShape.capsule,
                    fills: const [SwiftFill(TruverColors.textPrimary)],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(widthFactor: 1, child: Text('Показать все ноты', style: Typo.inter(15, TypoWeight.semibold, TruverColors.background))),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );

  /// «Лады 1–12 из 24» / «листайте вверх-вниз · нажмите ноту» + «Сыграть».
  Widget _scaleFooter(AppModel app) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              SwiftText('Лады ${_shownFretRange.$1}–${_shownFretRange.$2} из ${_fretCount(app)}',
                  style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary)),
              const SizedBox(height: 2),
              SwiftText('листайте вверх-вниз · нажмите ноту', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
            ]),
          ),
          const SizedBox(width: 10),
          _playButton(app),
        ]),
      );

  /// Canvas FlowNote1 panel (top 610 to the bottom, #141518, r 26).
  Widget _notePanel(AppModel app, NeckSpot spot) {
    final fretboard = app.fretboard;
    final info = fretboard.noteInfo(spot);
    final name = info?.chroma ?? '';
    final letter = name.replaceAll(RegExp(r'[0-9]'), '');
    final string = app.courseCount - spot.course;
    final place = spot.fret == 0 ? 'открытая' : '${spot.fret}-й лад';
    // CSS `flex: 1` with `white-space: nowrap`: a label wider than the share keeps its width (padding 18).
    Widget button(String title, VoidCallback onTap, {bool primary = false}) => Flexible(
          fit: FlexFit.tight,
          flex: primary ? 0 : 1,
          child: Pressable(
            label: title,
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                fills: [primary ? const SwiftFill.gradient(TruverGradients.primaryFill) : const SwiftFill.gradient(TruverGradients.cardFill)],
                strokes: primary ? const [] : const [SwiftStroke(TruverColors.hairline, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Center(
                    widthFactor: 1,
                    child: Text(title,
                        maxLines: 1,
                        style: Typo.inter(14, primary ? TypoWeight.semibold : TypoWeight.medium, primary ? TruverColors.background : TruverColors.textBody)),
                  ),
                ),
              ),
            ),
          ),
        );
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 200) fretboard.noteSpot = null;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TruverColors.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: TruverColors.white(0.08))),
          boxShadow: [BoxShadow(color: TruverColors.black(0.6), blurRadius: 40, offset: const Offset(0, -20))],
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: TruverColors.white(0.2), borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: TruverColors.textPrimary),
                child: Center(child: NoteText(letter, scale: false, style: Typo.fixed(18, TypoWeight.bold, const Color(0xFF0C0D0F)))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NoteText('$name · $string-я струна, $place', maxLines: 1, style: Typo.inter(17, TypoWeight.semibold, TruverColors.textPrimary)),
                  const SizedBox(height: 2),
                  SwiftText('что построить от этой ноты?', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                ]),
              ),
              const SizedBox(width: 12),
              RoundIconButton(icon: AppIcon.play, size: 36, iconSize: 14, label: 'Сыграть ноту', onTap: () => fretboard.tap(spot.course, spot.fret)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 14),
            child: Row(children: [
              button('Гамма', () => app.sheet = AppSheet('scaleFromNote', spot)),
              const SizedBox(width: 8),
              button('Аккорды', () => app.sheet = AppSheet('chordsFromNote', spot)),
              const SizedBox(width: 8),
              button('Прогрессия', () => app.sheet = AppSheet('progressionFromNote', spot), primary: true),
            ]),
          ),
        ]),
      ),
    );
  }

  /// The window the mode's neck scrolls to: «Аккорд» 9 frets from two below the shape, «Поиск» 9 from one below the
  /// marks, «Прогрессия» 11 from the current chord.
  (int, int) _modeWindow(AppModel app) {
    final fretboard = app.fretboard;
    final maxFret = _fretCount(app);
    (int, int) window(int lo, int count) {
      final start = math.max(1, math.min(lo, maxFret - count + 1));
      return (start, math.min(maxFret, start + count - 1));
    }

    switch (fretboard.mode) {
      case FretMode.chord:
        final fretted = (fretboard.currentVoicing?.notes ?? const <VoicingNote>[]).map((n) => n.fret).where((f) => f > 0);
        return window((fretted.isEmpty ? 3 : fretted.reduce(math.min)) - 2, 9);
      case FretMode.search:
        final frets = fretboard.marked.map((m) => m.fret);
        return window((frets.isEmpty ? 4 : frets.reduce(math.min)) - 1, 9);
      case FretMode.progression:
        // Canvas FlowNote3: the A barre at 5–7 shows frets 2–12.
        final p = fretboard.progression;
        final v = p.current < p.voiced.length ? p.voiced[p.current].voicing : null;
        final fretted = (v?.notes ?? const <VoicingNote>[]).map((n) => n.fret).where((f) => f > 0);
        return window(fretted.isEmpty ? p.visibleFrets.$1 : fretted.reduce(math.min) - 3, 11);
      case FretMode.scale:
        return (1, math.min(12, maxFret));
    }
  }

  Widget _modeNeck(AppModel app, NoteSizing sizing) {
    final fretboard = app.fretboard;
    // Canvas FlowNote3 shows only the sounding chord (no faint next chord).
    final cells = fretboard.cells().where((c) => sizing != NoteSizing.progression || c.emphasis != NeckEmphasis.faint).toList();
    Set<int> muted = const {};
    if (fretboard.mode == FretMode.chord) {
      final v = fretboard.currentVoicing;
      muted = v == null ? {} : {for (var i = 0; i < v.frets.length; i++) if (v.frets[i] == null) i};
    } else if (fretboard.mode == FretMode.progression) {
      muted = fretboard.progression.mutedCourses;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ScrollingNeck(
        courses: app.courseCount,
        fretCount: _fretCount(app),
        window: _modeWindow(app),
        height: 400,
        leftHanded: fretboard.settings.leftHanded,
        capoShift: fretboard.fretsFromCapo ? ((app.instrument['capo'] as num?)?.toInt() ?? 0) : 0,
        neck: (lo, hi) => _canvasNeck(app, cells, lo, hi, sizing, muted: muted),
      ),
    );
  }

  /// The canvas neck for a range of frets (steel board, canvas note sizes).
  NeckPortrait _canvasNeck(AppModel app, List<NeckCell> cells, int lo, int hi, NoteSizing sizing, {bool openBand = true, Set<int> muted = const {}}) {
    final fretboard = app.fretboard;
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    return NeckPortrait(
      courses: app.courseCount,
      lo: lo,
      hi: hi,
      cells: cells,
      leftHanded: fretboard.settings.leftHanded,
      capo: capo > 0 ? capo : null,
      strumming: fretboard.strumming,
      strumOrder: fretboard.strumOrder,
      strumToken: fretboard.strumToken,
      chordMode: fretboard.selectedChord != null || fretboard.mode == FretMode.progression || fretboard.chordPreview != null,
      playingMode: fretboard.isPlaying,
      mutedCourses: muted,
      fan: fretboard.data?.fan,
      sizing: sizing,
      openBand: openBand,
      coachCell: sizing == NoteSizing.scale ? CoachCatalog.firstTonic(cells)?.pair : null,
      onTap: (course, fret) {
        if (fretboard.mode == FretMode.search) fretboard.toggleMark(course, fret);
        if (fretboard.mode == FretMode.scale && fretboard.pathKind == null && !fretboard.isTraining) {
          // «нажмите ноту» → FlowNote1; the same note again closes it.
          final spot = NeckSpot(course, fret);
          fretboard.noteSpot = fretboard.noteSpot == spot ? null : spot;
        }
        fretboard.tap(course, fret);
      },
      onLongPress: (course, fret, global) {
        fretboard.menuSpot = NeckSpot(course, fret);
        final box = _screenKey.currentContext?.findRenderObject() as RenderBox?;
        setState(() => _menuPoint = box?.globalToLocal(global) ?? global);
      },
      scrubs: fretboard.mode == FretMode.scale && fretboard.pathKind == null && !fretboard.isTraining && fretboard.noteSpot == null,
      onScrub: (cell, global) {
        if (cell != null) {
          final spot = NeckSpot(cell.$1, cell.$2);
          if (_scrub?.$1 != spot) fretboard.tap(spot.course, spot.fret);
          final box = _screenKey.currentContext?.findRenderObject() as RenderBox?;
          setState(() => _scrub = (spot, box?.globalToLocal(global) ?? global));
        } else if (_scrub != null) {
          // «отпустите — нота поставлена»: the held note opens FlowNote1.
          final last = _scrub!.$1;
          setState(() => _scrub = null);
          fretboard.noteSpot = last;
        }
      },
    );
  }

  /// Root chips (the root and the next two letters) and the quick chord types; 32 pt chips, gap 6.
  Widget _chordChips(AppModel app) {
    final fretboard = app.fretboard;
    final root = fretboard.chordRoot;
    final letter = (root['letter'] as num?)?.toInt() ?? 0;
    final roots = <Map<String, dynamic>>[root, for (var i = 1; i < 3; i++) {'letter': (letter + i) % 7, 'accidental': 0}];
    final library = FretLibrary.load(app);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < roots.length; i++) ...[
          Pressable(
            label: app.noteName(roots[i]),
            onTap: () {
              fretboard.chordAnchor = null;
              fretboard.chordRoot = roots[i];
            },
            child: Chip(text: app.noteName(roots[i]), style: i == 0 ? ChipStyle.emphasized : ChipStyle.plain),
          ),
          const SizedBox(width: 6),
        ],
        for (final id in const ['m', 'm7', '7', 'maj7', 'sus4', 'dim', 'aug', 'sus2'])
          if (library.chords.where((c) => c.id == id).firstOrNull case final chord?) ...[
            Pressable(
              label: chord.chipName,
              onTap: () => fretboard.chordId = id,
              child: Chip(text: chord.chipName, style: fretboard.chordId == id ? ChipStyle.emphasized : ChipStyle.plain),
            ),
            const SizedBox(width: 6),
          ],
        Pressable(
          label: 'ещё…',
          onTap: () => setState(() {
            _libraryAtScales = false;
            _showLibrary = true;
          }),
          child: const Chip(text: 'ещё…'),
        ),
      ]),
    );
  }

  /// «Am7 · баррэ на 5-м» / «расположение 2 из 4 · A E G C E A» + ‹ › (44).
  Widget _chordFooter(AppModel app) {
    final fretboard = app.fretboard;
    final v = fretboard.currentVoicing;
    final title = fretboard.chordName() + (v == null ? '' : ' · ${v.barreFret != null ? 'баррэ на ${v.barreFret}-м' : fretboard.voicingTitle(v)}');
    final notes = [...?v?.notes]..sort((a, b) => a.course.compareTo(b.course));
    final caption = v == null
        ? 'расположений нет'
        : 'расположение ${fretboard.voicingIndex + 1} из ${fretboard.voicings.length} · ${notes.map((n) => n.plain).join(' ')}';
    return Row(children: [
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _libraryAtScales = false;
            _showLibrary = true;
          }),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NoteText(title, maxLines: 1, style: Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary)),
            const SizedBox(height: 2),
            NoteText(caption, maxLines: 1, style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      CoachAnchor(
        id: CoachAnchors.voicingPrev,
        child: RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Предыдущее расположение', onTap: () => fretboard.stepVoicing(-1)),
      ),
      const SizedBox(width: 10),
      CoachAnchor(
        id: CoachAnchors.voicingNext,
        child: RoundIconButton(icon: AppIcon.chevronRight, size: 44, label: 'Следующее расположение', onTap: () => fretboard.stepVoicing(1)),
      ),
    ]);
  }

  String _searchTitle(AppModel app) {
    final n = app.fretboard.marked.length;
    return n == 0 ? 'Отметьте ноты' : 'Отмечено $n ${ruPlural(n, 'нота', 'ноты', 'нот')}';
  }

  String _progressionTitle(AppModel app) {
    final p = app.fretboard.progression;
    final key = p.voiced.isEmpty ? '' : p.voiced.first.letterName.replaceAll(RegExp(r'm$|°$'), '');
    final numerals = p.rows.map((r) => r.numeral).join('–');
    return key.isEmpty ? p.name : '$key · $numerals';
  }

  /// Four chords, 56 pt, radius 14, gap 6: name 17 semibold, numeral 11 tertiary; the current one lit.
  Widget _progressionChords(AppModel app) {
    final p = app.fretboard.progression;
    return Row(children: [
      for (var i = 0; i < p.voiced.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Pressable(
            label: p.voiced[i].name,
            selected: i == p.current,
            onTap: () {
              if (i == p.current && !p.isPlaying) {
                app.sheet = AppSheet('progressionChord', i);
              } else {
                p.select(i);
              }
            },
            child: SizedBox(
              height: 56,
              child: ShapeBox(
                shape: const SwiftShape.rounded(14),
                fills: [SwiftFill(i == p.current ? TruverColors.textPrimary.withValues(alpha: 0.12) : TruverColors.white(0.04))],
                strokes: [SwiftStroke(i == p.current ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true)],
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Fit(child: NoteText(Typo.compactChordName(p.voiced[i].name), maxLines: 1, style: Typo.inter(17, TypoWeight.semibold, TruverColors.textPrimary))),
                  const SizedBox(height: 2),
                  NoteText(i < p.rows.length ? p.rows[i].numeral : '', maxLines: 1, style: Typo.inter(11, TypoWeight.regular, TruverColors.textTertiary)),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  /// «A · баррэ от 5-го лада» / «такт 1 из 4 · следующий E — рядом, 7-й лад» + «Сыграть».
  Widget _progressionFooter(AppModel app) {
    final p = app.fretboard.progression;
    final v = p.current < p.voiced.length ? p.voiced[p.current] : null;
    final next = p.voiced.isEmpty ? null : p.voiced[(p.current + 1) % p.voiced.length];
    String shape(ChordVoicing voicing) {
      if (voicing.usesOpenStrings && voicing.lowestFret <= 4) return 'открытый';
      return '${voicing.barreFret != null ? 'баррэ от ' : 'от '}${voicing.lowestFret}-го лада';
    }

    final title = (v == null ? '' : Typo.compactChordName(v.name)) + (v?.voicing == null ? '' : ' · ${shape(v!.voicing!)}');
    var caption = 'такт ${p.current + 1} из ${math.max(1, p.voiced.length)}';
    final nv = next?.voicing, cv = v?.voicing;
    if (next != null && nv != null && cv != null) {
      final near = (nv.lowestFret - cv.lowestFret).abs() <= 2;
      caption += ' · следующий ${Typo.compactChordName(next.name)} — ${near ? 'рядом' : 'сдвиг'}, ${nv.lowestFret}-й лад';
    }
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          NoteText(title, maxLines: 1, style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary)),
          const SizedBox(height: 2),
          NoteText(caption, style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
        ]),
      ),
      const SizedBox(width: 10),
      Pressable(
        label: p.isPlaying ? 'Стоп' : 'Сыграть',
        onTap: p.toggle,
        child: SizedBox(
          height: 52,
          child: ShapeBox(
            shape: SwiftShape.capsule,
            shadows: [SwiftShadow(TruverColors.black(0.35), 9, y: 6)],
            fills: const [SwiftFill(TruverColors.textPrimary)],
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 18),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIconView(p.isPlaying ? AppIcon.stop : AppIcon.play, size: 18, color: TruverColors.background),
                const SizedBox(width: 8),
                Text(p.isPlaying ? 'Стоп' : 'Сыграть', style: Typo.inter(16, TypoWeight.semibold, TruverColors.background)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  List<Widget> _bottom(AppModel app) {
    final fretboard = app.fretboard;
    switch (fretboard.mode) {
      case FretMode.scale:
        if (fretboard.isTraining) {
          return [Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 10), child: _trainingBar(app))];
        } else if (fretboard.pathKind != null) {
          return [Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 10), child: _pathBar(app))];
        }
        return [
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 14), child: _chordStrip(app)),
          Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 10), child: _navigation(app)),
        ];
      case FretMode.chord:
        return [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 14),
            child: ChordInversionRow(showsLabels: true, showScales: () => setState(() {
                  _libraryAtScales = true;
                  _showLibrary = true;
                })),
          ),
          const Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 10), child: ChordNavigationRow()),
        ];
      case FretMode.search:
        return [const Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 10), child: SearchResultCard())];
      case FretMode.progression:
        return [
          const Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 14), child: ProgressionRibbon()),
          const Padding(padding: EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 10), child: ProgressionControlRow()),
        ];
    }
  }

  // MARK: Scale row

  String _scaleTitle(AppModel app) {
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    return app.fretboard.scaleTitle + (capo > 0 ? ' · капо $capo' : '') + (app.fretboard.pathKind != null ? ' · путь' : '');
  }

  /// «E · Фригийский доминант ▾» (44 pt capsule), reset when edited, «Путь», «Вид и подписи».
  Widget _scaleRow(AppModel app) {
    final fretboard = app.fretboard;
    final title = _scaleTitle(app);
    return Row(
      children: [
        if (fretboard.pathKind != null) ...[
          // Visible way out of the path (it was only inside the path sheet).
          RoundIconButton(icon: AppIcon.close, size: 44, label: 'Выйти из пути', onTap: () {
            if (fretboard.isPlaying) fretboard.stopPlayback();
            fretboard.pathKind = null;
          }),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Pressable(
            label: 'Гамма: $title',
            onTap: () => app.sheet = const AppSheet('fretScale'),
            child: SizedBox(
              height: 44,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 10),
                  child: Row(
                    children: [
                      if (fretboard.isEdited) ...[
                        const SizedBox(
                          width: 8,
                          height: 8,
                          child: ShapeBox(
                            shape: SwiftShape.circle,
                            shadows: [SwiftShadow(TruverColors.characteristicNote, 4)],
                            fills: [SwiftFill(TruverColors.characteristicNote)],
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: _Fit(
                          minScale: 0.8,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            Typo.notes(title, Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary).copyWith(letterSpacing: -0.14)),
                            maxLines: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const AppIconView(AppIcon.chevronDown, size: 14, color: TruverColors.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (fretboard.isEdited) ...[
          const SizedBox(width: 8),
          Pressable(
            label: 'Сбросить изменения',
            onTap: fretboard.resetEdits,
            child: SizedBox(
              width: 44,
              height: 44,
              child: ShapeBox(
                shape: SwiftShape.circle,
                shadows: [SwiftShadow(TruverColors.black(0.6), 9, y: 8)],
                fills: [SwiftFill.gradient(TruverGradients.knobFill(44))],
                strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                child: const Center(child: AppIconView(AppIcon.refresh, size: 18, color: TruverColors.characteristicNote)),
              ),
            ),
          ),
        ],
        if (fretboard.pathKind == null) ...[
          const SizedBox(width: 8),
          // Visible way into «Путь» (it was only in the note's long-press menu — user: «не вижу пути»).
          Pressable(
            label: 'Путь по грифу',
            onTap: () {
              fretboard.startPath(null);
              app.sheet = const AppSheet('fretPath');
            },
            child: SizedBox(
              height: 44,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(widthFactor: 1, child: Text('Путь', style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary))),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        RoundIconButton(
          icon: AppIcon.rename,
          size: 44,
          label: fretboard.pathKind != null ? 'Путь по грифу' : 'Вид и подписи',
          onTap: () => app.sheet = AppSheet(fretboard.pathKind != null ? 'fretPath' : 'fretView'),
        ),
      ],
    );
  }

  /// FB-14 while training: the result strip, tempo ± and «Стоп».
  Widget _trainingBar(AppModel app) {
    final fretboard = app.fretboard;
    return Column(
      children: [
        // TODO(android): PlayCheckPanel(height: 56) of the metronome port («Проверка игры»).
        SizedBox(
          height: 56,
          child: ShapeBox(
            shape: const SwiftShape.rounded(16, continuous: true),
            fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
            strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            RoundIconButton(icon: AppIcon.minus, size: 44, label: 'Медленнее', onTap: () => fretboard.bpm -= 1),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${fretboard.bpm.round()}', style: Typo.monospacedDigit(Typo.inter(22, TypoWeight.semibold, TruverColors.textPrimary))),
                  Text('BPM', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RoundIconButton(icon: AppIcon.plus, size: 44, label: 'Быстрее', onTap: () => fretboard.bpm += 1),
            const SizedBox(width: 8),
            Pressable(
              onTap: fretboard.stopTraining,
              child: SizedBox(
                height: 52,
                child: ShapeBox(
                  shape: SwiftShape.capsule,
                  fills: const [SwiftFill(TruverColors.textPrimary)],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const AppIconView(AppIcon.stop, size: 16, color: TruverColors.background),
                      const SizedBox(width: 8),
                      Text('Стоп', style: Typo.inter(16, TypoWeight.semibold, TruverColors.background)),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// «Своё окно · лады 5–8 · тяните за ручки» + «Готово» (canvas «правка своего окна ладов»).
  Widget _windowBar(AppModel app) {
    final r = app.fretboard.visibleFrets;
    return SizedBox(
      height: 44,
      child: ShapeBox(
        shape: SwiftShape.capsule,
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(
            children: [
              Expanded(
                child: Text('Своё окно · лады ${r.$1}–${r.$2} · тяните за ручки',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.inter(13, TypoWeight.medium, TruverColors.textPrimary)),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: () => setState(() => _editingWindow = false),
                child: SizedBox(
                  height: 32,
                  child: ShapeBox(
                    shape: SwiftShape.capsule,
                    fills: const [SwiftFill(TruverColors.textPrimary)],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Center(widthFactor: 1, child: Text('Готово', style: Typo.inter(13, TypoWeight.semibold, TruverColors.background))),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: Note menu

  /// Note menu under the pressed note (canvas «меню ноты»), kept on screen.
  Widget _noteMenu(AppModel app, NeckSpot spot) {
    final point = _menuPoint!;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      const menuHeight = 256.0;
      final below = point.dy + 38;
      final y = below + menuHeight <= size.height ? below : math.max(8.0, point.dy - 38 - menuHeight);
      final x = math.min(math.max(16.0, point.dx - 116), size.width - 248);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
              child: ColoredBox(color: const Color(0xFF030304).withValues(alpha: 0.55)),
            ),
          ),
          // Canvas «меню ноты»: the pressed note grows to 52 pt with a halo.
          Positioned(
            left: point.dx - 29,
            top: point.dy - 29,
            width: 58,
            height: 58,
            child: IgnorePointer(
              child: ShapeBox(
                shape: SwiftShape.circle,
                strokes: [const SwiftStroke(Color.fromRGBO(246, 243, 236, 0.18), width: 6)],
                child: Center(
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: ShapeBox(
                      shape: SwiftShape.circle,
                      shadows: [SwiftShadow(TruverColors.black(0.7), 15, y: 14)],
                      fills: const [SwiftFill(Color.fromRGBO(245, 239, 227, 0.98))],
                      strokes: const [SwiftStroke(Color(0xFFFFFFFF), width: 2, inside: true)],
                      child: Center(
                        child: _Fit(
                          minScale: 0.6,
                          child: Text.rich(
                            Typo.notes(app.fretboard.noteName(spot), Typo.fixed(17, TypoWeight.bold, const Color(0xFF0C0D0F))),
                            textScaler: TextScaler.noScaling,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: x, top: y, child: NoteMenu(spot: spot, close: _closeMenu)),
        ],
      );
    });
  }

  void _closeMenu() {
    setState(() => _menuPoint = null);
    final app = AppScope.read(context);
    if (app.sheet == null) app.fretboard.menuSpot = null;
  }

  // MARK: Neck

  (int, int) _shownFrets(AppModel app) {
    // Editing the window: the frets around it stay in view, dimmed (canvas «правка своего окна»).
    if (_editingWindow && _windowContext != null) return _windowContext!;
    final r = app.fretboard.visibleFrets;
    if (_zoom <= 1.01 || app.fretboard.settings.neckView == NeckDisplay.wholeNeck) return r;
    final countAll = r.$2 - r.$1 + 1;
    final count = math.max(2, (countAll / _zoom).round());
    final start = r.$1 + (countAll - count) ~/ 2;
    return (start, start + count - 1);
  }

  Widget _neck(AppModel app) {
    final fretboard = app.fretboard;
    final cells = fretboard.cells();
    final s = fretboard.settings;
    final fretCount = (app.instrument['fretCount'] as num?)?.toInt() ?? 24;
    Widget neck;
    if (fretboard.mode == FretMode.scale && fretboard.pathKind != null) {
      // The whole neck with the whole path on one screen (FB-20).
      neck = _neckView(app, cells, (0, fretCount), path: fretboard.pathNotes, pathCurrent: fretboard.pathIndex, overview: true);
    } else if (s.neckView == NeckDisplay.wholeNeck && !fretboard.hasPreview && (fretboard.mode == FretMode.scale || fretboard.mode == FretMode.search)) {
      // The whole neck on one screen (user: «нужен режим, где я вижу весь гриф, а не кусок»).
      neck = _neckView(app, cells, fretboard.visibleFrets, overview: true);
    } else {
      neck = _neckView(app, cells, _shownFrets(app));
    }
    return GestureDetector(
      onScaleStart: (d) {
        if (d.pointerCount >= 2) _pinchBase = _zoom;
      },
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        setState(() {
          _zoom = (_pinchBase * d.scale).clamp(1.0, 2.5);
          _showZoom = true;
        });
        _zoomTimer?.cancel();
      },
      onScaleEnd: (_) {
        _pinchBase = _zoom;
        _zoomTimer?.cancel();
        _zoomTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted) setState(() => _showZoom = false);
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: neck),
          if (fretboard.positions.isEmpty && s.neckView != NeckDisplay.window)
            Center(
              child: IgnorePointer(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: ShapeBox(
                    shape: const SwiftShape.rounded(18, continuous: true),
                    fills: [SwiftFill(const Color(0xFF141518).withValues(alpha: 0.92))],
                    strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SwiftText('Для этой гаммы позиции не строятся',
                            textAlign: TextAlign.center, style: Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
                        const SizedBox(height: 6),
                        SwiftText('Показан весь гриф', textAlign: TextAlign.center, style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 82,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showZoom ? 1 : 0,
                duration: Motion.base,
                child: Center(
                  child: SizedBox(
                    height: 30,
                    child: ShapeBox(
                      shape: SwiftShape.capsule,
                      fills: [SwiftFill(const Color(0xFF141518).withValues(alpha: 0.95))],
                      strokes: [SwiftStroke(TruverColors.white(0.2), inside: true)],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const AppIconView(AppIcon.search, size: 12, color: TruverColors.textTertiary),
                          const SizedBox(width: 6),
                          Text('×${_zoom.toStringAsFixed(1).replaceAll('.', ',')}', style: Typo.chip.copyWith(color: TruverColors.textPrimary)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _neckView(AppModel app, List<NeckCell> cells, (int, int) frets,
      {List<FretNote> path = const [], int? pathCurrent, bool overview = false}) {
    final fretboard = app.fretboard;
    final s = fretboard.settings;
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    final preview = fretboard.chordPreview;
    final Set<int> muted;
    if (preview != null) {
      muted = {for (var i = 0; i < preview.frets.length; i++) if (preview.frets[i] == null) i};
    } else if (fretboard.mode == FretMode.chord) {
      final v = fretboard.currentVoicing;
      muted = v == null ? {} : {for (var i = 0; i < v.frets.length; i++) if (v.frets[i] == null) i};
    } else if (fretboard.mode == FretMode.progression) {
      muted = fretboard.progression.mutedCourses;
    } else {
      muted = {};
    }
    final neck = NeckPortrait(
      courses: app.courseCount,
      lo: frets.$1,
      hi: frets.$2,
      cells: cells,
      leftHanded: s.leftHanded,
      capo: capo > 0 ? capo : null,
      strumming: fretboard.strumming,
      strumOrder: fretboard.strumOrder,
      strumToken: fretboard.strumToken,
      chordMode: fretboard.selectedChord != null || fretboard.mode == FretMode.progression || fretboard.chordPreview != null,
      path: [for (final n in path) NeckPathNote(n.course, n.fret)],
      pathLabels: [for (final n in path) fretboard.pathLabel(n)],
      pathCurrent: pathCurrent,
      playingMode: fretboard.isPlaying,
      mutedCourses: muted,
      fan: fretboard.data?.fan,
      overview: overview,
      onTap: (course, fret) {
        if (fretboard.mode == FretMode.search) fretboard.toggleMark(course, fret);
        fretboard.tap(course, fret);
      },
      onLongPress: (course, fret, global) {
        fretboard.menuSpot = NeckSpot(course, fret);
        final box = _screenKey.currentContext?.findRenderObject() as RenderBox?;
        setState(() => _menuPoint = box?.globalToLocal(global) ?? global);
      },
    );
    final label = _positionLabel(app).replaceAll('\n', ', ');
    return Semantics(
      label: 'Гриф, ${_scaleTitle(app)}',
      value: label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: neck),
          if (_editingWindow) Positioned.fill(child: _windowFrame(app, frets)),
        ],
      ),
    );
  }

  /// Window frame with two drag handles (top and bottom) moving the window by frets.
  Widget _windowFrame(AppModel app, (int, int) frets) => LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final g = NeckGeometry(size: size, courses: app.courseCount, lo: frets.$1, hi: frets.$2, fan: app.fretboard.data?.fan);
        final s = app.fretboard.settings;
        final start = s.windowStart;
        final end = start + s.windowLength - 1;
        final top = start <= frets.$1 ? 0.0 : g.wire(start - 1);
        final bottom = math.min(size.height, g.wire(math.min(end, frets.$2)) + 4);
        final row = math.max(12.0, (bottom - top) / math.max(1, s.windowLength));
        final height = math.max(24.0, bottom - top);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -6,
              right: -6,
              top: top,
              height: height,
              child: const IgnorePointer(
                child: ShapeBox(shape: SwiftShape.rounded(6), strokes: [SwiftStroke(TruverColors.textPrimary, width: 2, inside: true)]),
              ),
            ),
            // `.overlay(alignment: .top) { handle.offset(y: -22) }`: the handle's centre sits on the frame's edge.
            Positioned(left: size.width / 2 - 44, top: top - 22, width: 88, height: 44, child: _handle(app, true, row)),
            Positioned(left: size.width / 2 - 44, top: top + height - 22, width: 88, height: 44, child: _handle(app, false, row)),
          ],
        );
      });

  Widget _handle(AppModel app, bool top, double row) {
    var dy = 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => dy = 0,
      onVerticalDragUpdate: (d) => dy += d.delta.dy,
      onVerticalDragEnd: (_) {
        final steps = (dy / row).round();
        if (steps == 0) return;
        final maxFret = (app.instrument['fretCount'] as num?)?.toInt() ?? 24;
        app.fretboard.updateSettings((s) {
          if (top) {
            final start = (s.windowStart + steps).clamp(0, s.windowStart + s.windowLength - 2);
            s.windowLength += s.windowStart - start;
            s.windowStart = start;
          } else {
            s.windowLength = (s.windowLength + steps).clamp(2, maxFret - s.windowStart + 1);
          }
        });
        final s = app.fretboard.settings;
        final c = _windowContext;
        // The frets around follow only when the window reaches the edge of what is shown.
        if (c != null && (s.windowStart <= c.$1 || s.windowStart + s.windowLength - 1 >= c.$2)) {
          setState(() => _windowContext = _context(app, s.windowStart, s.windowLength));
        }
      },
      child: Center(
        child: SizedBox(
          width: 48,
          height: 18,
          child: ShapeBox(
            shape: SwiftShape.capsule,
            shadows: [SwiftShadow(TruverColors.black(0.5), 4, y: 3)],
            fills: const [SwiftFill(TruverColors.textPrimary)],
            child: const Center(
              child: SizedBox(width: 22, height: 3, child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.background)])),
            ),
          ),
        ),
      ),
    );
  }

  (int, int) _context(AppModel app, int start, int length) {
    final maxFret = (app.instrument['fretCount'] as num?)?.toInt() ?? 24;
    return (math.max(0, start - 3), math.min(maxFret, start + length - 1 + 3));
  }

  // MARK: Path bar

  /// «14 / 20 · автопрокрутка … · ❙❙» and «↓ К текущей ноте» (canvas «путь, портрет»).
  Widget _pathBar(AppModel app) {
    final fretboard = app.fretboard;
    final index = fretboard.pathIndex;
    final text = _autoScroll
        ? (index == null ? '${fretboard.pathSummary} · ▶ — сыграть' : _pathKindTitle(app))
        : 'Автопрокрутка на паузе — вы листали гриф';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_autoScroll) ...[
          Pressable(
            onTap: () => setState(() => _autoScroll = true),
            child: SizedBox(
              height: 40,
              child: ShapeBox(
                shape: SwiftShape.capsule,
                fills: [SwiftFill(TruverColors.background.withValues(alpha: 0.85)), const SwiftFill.gradient(TruverGradients.cardFill)],
                strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('↓', style: Typo.inter(13, TypoWeight.semibold, TruverColors.textPrimary)),
                    const SizedBox(width: 6),
                    Text('К текущей ноте', style: Typo.inter(14, TypoWeight.medium, TruverColors.textPrimary)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Chip(text: '${(index ?? 0) + 1} / ${fretboard.pathNotes.length}'),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(Typo.notes(text, Typo.caption.copyWith(color: TruverColors.textSecondary)), textAlign: TextAlign.center),
            ),
            const SizedBox(width: 10),
            RoundIconButton(icon: AppIcon.sliders, size: 44, label: 'Путь по грифу', onTap: () => app.sheet = const AppSheet('fretPath')),
            const SizedBox(width: 10),
            PrimaryRoundButton(
              icon: fretboard.isPlaying ? AppIcon.pause : AppIcon.play,
              size: 44,
              iconSize: 18,
              label: fretboard.isPlaying ? 'Пауза' : 'Сыграть путь',
              onTap: () {
                setState(() => _autoScroll = true);
                fretboard.togglePlayback();
              },
            ),
          ],
        ),
      ],
    );
  }

  String _pathKindTitle(AppModel app) {
    final fretboard = app.fretboard;
    switch (fretboard.pathKind) {
      case PathKind.threePerString:
        return 'Путь: 3 ноты на струну';
      case PathKind.fourDiagonal:
        return 'Путь: 4 ноты наискосок';
      case PathKind.oneString:
        // «По одной струне · 5-я»: strings count from the highest (canvas «путь по одной струне»).
        final course = fretboard.pathNotes.firstOrNull?.course;
        if (course == null) return 'Путь: по одной струне';
        return 'Путь: по одной струне · ${app.courseCount - course}-я';
      case null:
        return '';
    }
  }

  // MARK: Chords (7 columns, gap 5, 52 pt)

  Widget _chordStrip(AppModel app) {
    final fretboard = app.fretboard;
    final chords = fretboard.keyChords;
    final strip = Row(
      children: [
        for (var index = 0; index < chords.length; index++) ...[
          if (index > 0) const SizedBox(width: 5),
          Expanded(child: _chordCell(app, index, chords[index])),
        ],
      ],
    );
    return IgnorePointer(ignoring: _editingWindow, child: Opacity(opacity: _editingWindow ? 0.4 : 1, child: strip));
  }

  Widget _chordCell(AppModel app, int index, KeyChord chord) {
    final fretboard = app.fretboard;
    final selected = fretboard.selectedChord == index;
    return Pressable(
      label: '${chord.spoken}, ${chord.roman}',
      selected: selected,
      onTap: () => fretboard.tapChord(index),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ShapeBox(
            shape: const SwiftShape.rounded(12, continuous: true),
            fills: [SwiftFill(selected ? TruverColors.textPrimary.withValues(alpha: 0.12) : TruverColors.white(0.04))],
            strokes: [SwiftStroke(selected ? TruverColors.textPrimary.withValues(alpha: 0.7) : TruverColors.hairline, inside: true)],
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52, minWidth: double.infinity),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Canvas «Обозначения — гриф»: chord symbols stay in letters in solfège.
                  _Fit(
                    minScale: 0.6,
                    child: notesText(Typo.compactChordName(chord.name),
                          Typo.inter(15, TypoWeight.semibold, selected ? TruverColors.textPrimary : TruverColors.textMuted),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  notesText(chord.roman, Typo.inter(10, TypoWeight.regular, TruverColors.textTertiary), maxLines: 1),
                ],
              ),
            ),
          ),
          if (selected && fretboard.strumming.isNotEmpty)
            const Positioned(
              left: -4,
              right: -4,
              top: -4,
              bottom: -4,
              child: IgnorePointer(
                child: ShapeBox(
                  shape: SwiftShape.rounded(14, continuous: true),
                  strokes: [SwiftStroke(Color.fromRGBO(246, 243, 236, 0.9), width: 2)],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: Navigation

  /// «лады 3–8», with a capo counted from it (PRD 6.2.5): «от капо 0–5».
  String _fretsText(AppModel app, (int, int) r) {
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    if (capo <= 0) return 'лады ${r.$1}–${r.$2}';
    return 'от капо ${math.max(0, r.$1 - capo)}–${math.max(0, r.$2 - capo)}';
  }

  String _positionLabel(AppModel app) {
    final fretboard = app.fretboard;
    final r = fretboard.visibleFrets;
    final capo = (app.instrument['capo'] as num?)?.toInt() ?? 0;
    final position = fretboard.currentPosition;
    final shown = capo > 0 ? (position == null ? _shownFrets(app) : (position.lo, position.hi)) : _shownFrets(app);
    switch (fretboard.settings.neckView) {
      case NeckDisplay.position:
        if (fretboard.positions.isEmpty) return 'Позиция —\n${_fretsText(app, r)}';
        if (fretboard.positionAnchor != null) return 'От ноты\n${_fretsText(app, shown)}';
        // The last positions are cut by the last fret — say so.
        final edge = position?.isTruncated == true ? ' · край грифа' : '';
        return 'Позиция ${fretboard.settings.positionNumber}/${fretboard.positions.length}\n${_fretsText(app, shown)}$edge';
      case NeckDisplay.window:
        return 'Своё окно\n${_fretsText(app, r)}';
      case NeckDisplay.wholeNeck:
        return 'Весь гриф\n${_fretsText(app, r)}';
    }
  }

  Widget _navigation(AppModel app) {
    final fretboard = app.fretboard;
    final label = _positionLabel(app);
    final row = Row(
      children: [
        RoundIconButton(icon: AppIcon.chevronLeft, size: 44, label: 'Предыдущая позиция', onTap: () => fretboard.stepPosition(-1)),
        const SizedBox(width: 8),
        // One visible choice of the view instead of a hidden tap / long press on the label.
        Expanded(
          child: Builder(
            builder: (context) => Pressable(
              scale: 1,
              label: 'Вид грифа: ${label.replaceAll('\n', ', ')}',
              onTap: () => showFretMenu(context, [
                FretMenuItem('Позиции', () => fretboard.selectPosition(math.max(1, fretboard.settings.positionNumber))),
                FretMenuItem('Весь гриф', () => fretboard.selectPosition(null)),
                FretMenuItem('Своё окно ладов…', () => _startEditingWindow(app)),
                FretMenuItem('Путь по грифу', () {
                  fretboard.startPath(null);
                  app.sheet = const AppSheet('fretPath');
                }),
                FretMenuItem('Тренировать с проверкой', fretboard.startTraining),
              ]),
              child: _positionText(label),
            ),
          ),
        ),
        const SizedBox(width: 8),
        RoundIconButton(icon: AppIcon.chevronRight, size: 44, label: 'Следующая позиция', onTap: () => fretboard.stepPosition(1)),
        const SizedBox(width: 8),
        // Visible entry to the playback settings; while the drone sounds the button is lit and turns it off.
        if (fretboard.isDroning)
          PrimaryRoundButton(icon: AppIcon.waveform, size: 44, iconSize: 18, label: 'Выключить бурдон', onTap: fretboard.stopDrone)
        else
          RoundIconButton(icon: AppIcon.sliders, size: 44, label: 'Настройки проигрывания', onTap: () => app.sheet = const AppSheet('fretPlay')),
        const SizedBox(width: 8),
        _playButton(app),
      ],
    );
    return IgnorePointer(ignoring: _editingWindow, child: Opacity(opacity: _editingWindow ? 0.4 : 1, child: row));
  }

  void _startEditingWindow(AppModel app) {
    final r = app.fretboard.visibleFrets;
    app.fretboard.updateSettings((s) {
      s.neckView = NeckDisplay.window;
      s.windowStart = math.max(1, r.$1);
      s.windowLength = math.max(2, math.min(r.$2 - r.$1 + 1, 6));
    });
    final s = app.fretboard.settings;
    setState(() {
      _windowContext = _context(app, s.windowStart, s.windowLength);
      _editingWindow = true;
    });
  }

  Widget _positionText(String label) {
    final lines = label.split('\n');
    final first = lines.first;
    final space = first.indexOf(' ');
    final head = space < 0 ? first : first.substring(0, space);
    final rest = space < 0 ? '' : first.substring(space + 1);
    final style = Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary);
    // `.lineLimit(1).minimumScaleFactor(0.75)` shrinks each line on its own; `.lineSpacing` does not apply between
    // the lines of a VStack.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Fit(
          minScale: 0.75,
          child: SwiftText.rich(
            style: style,
            TextSpan(style: style, children: [
              TextSpan(text: head),
              if (rest.isNotEmpty) const TextSpan(text: ' '),
              if (rest.isNotEmpty) TextSpan(text: rest, style: Typo.inter(12, TypoWeight.semibold, TruverColors.textPrimary)),
            ]),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ),
        // iOS draws the second line at 15 pt (the label's `.font(12)` does not reach it).
        _Fit(
          minScale: 0.75,
          child: SwiftText(lines.length > 1 ? lines[1] : '',
              style: Typo.inter(15, TypoWeight.regular, TruverColors.textTertiary), maxLines: 1, textAlign: TextAlign.center),
        ),
      ],
    );
  }

  /// «▶ Сыграть» / «❙❙ Пауза»: ivory pill 52 pt, 16 semibold; long press — the playback sheet.
  Widget _playButton(AppModel app) {
    final fretboard = app.fretboard;
    return GestureDetector(
      onLongPress: () => app.sheet = const AppSheet('fretPlay'),
      child: Pressable(
        label: fretboard.isPlaying ? 'Пауза' : 'Сыграть гамму',
        onTap: fretboard.togglePlayback,
        child: SizedBox(
          height: 52,
          child: ShapeBox(
            shape: SwiftShape.capsule,
            shadows: [SwiftShadow(TruverColors.black(0.35), 9, y: 6)],
            fills: const [SwiftFill(TruverColors.textPrimary)],
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 18),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIconView(fretboard.isPlaying ? AppIcon.pause : AppIcon.play, size: 18, color: TruverColors.background),
                const SizedBox(width: 8),
                Text(fretboard.isPlaying ? 'Пауза' : (fretboard.canResume ? 'Дальше' : 'Сыграть'),
                    style: Typo.inter(16, TypoWeight.semibold, TruverColors.background)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// SwiftUI `.lineLimit(1).minimumScaleFactor(x)`: the text shrinks (down to `minScale`) instead of wrapping.
class _Fit extends StatelessWidget {
  const _Fit({required this.child, this.minScale = 0.6, this.alignment = Alignment.center});
  final Widget child;
  final double minScale;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);
}

/// Public for the other fretboard files.
class FitText extends StatelessWidget {
  const FitText({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, child: child);
}

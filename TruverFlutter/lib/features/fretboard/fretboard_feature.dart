/// Registration of the fretboard feature in the app shell (screens, sheets, debug arguments) — the fretboard part
/// of `AppModel.swift`'s launch hooks (`-fretDemo`, `-resetFretboard`, `-neckWhole`, `-lowTop`, `-fan`,
/// `-fretMode …`, `-chordLibrary`, `-fretPlay`, `-progPlay`, `-trainingDemo`, `-sheet fret…`).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/feature_registry.dart';
import '../../app/storage.dart';
import 'fret_modes.dart';
import 'fret_tab_view.dart';
import 'fretboard_controller.dart';
import 'fretboard_landscape.dart';
import 'fretboard_screen.dart';
import 'progression_views.dart';
import 'user_theory_sheets.dart';

void registerFretboard() {
  // «Таб» (FretTabView): the tablature instead of the neck, full screen without the tab bar.
  FeatureRegistry.tabScreens[AppTab.fretboard] =
      (context) => FretboardTabSwitch(landscape: false, neck: (_) => const FretboardScreen());
  FeatureRegistry.landscapeScreens[AppTab.fretboard] =
      (context) => FretboardTabSwitch(landscape: true, neck: (_) => const FretboardLandscape());
  FeatureRegistry.hidesTabBar[AppTab.fretboard] = (app) => app.fretboard.hidesTabBar;

  FeatureRegistry.sheets['fretScale'] = (context, _) => const FretScaleSheet();
  FeatureRegistry.sheets['fretView'] = (context, _) => const FretViewSheet();
  FeatureRegistry.sheets['fretPlay'] = (context, _) => const FretPlaySheet();
  FeatureRegistry.sheets['fretPath'] = (context, _) => const FretPathSheet();
  FeatureRegistry.sheets['searchResults'] = (context, _) => const SearchResultsSheet();
  FeatureRegistry.sheets['chordsFromNote'] =
      (context, sheet) => ChordsFromNoteSheet(key: ValueKey(sheet.arg), spot: sheet.arg as NeckSpot? ?? const NeckSpot(0, 0));
  FeatureRegistry.sheets['scaleFromNote'] =
      (context, sheet) => ScaleFromNoteSheet(key: ValueKey(sheet.arg), spot: sheet.arg as NeckSpot? ?? const NeckSpot(0, 0));
  FeatureRegistry.sheets['fretProgression'] = (context, _) => const FretProgressionSheet();
  FeatureRegistry.sheets['fretProgressions'] = (context, _) => const FretProgressionsSheet();
  FeatureRegistry.sheets['progressionFromNote'] =
      (context, sheet) => ProgressionFromNoteSheet(key: ValueKey(sheet.arg), spot: sheet.arg as NeckSpot? ?? const NeckSpot(0, 0));
  FeatureRegistry.sheets['progressionChord'] =
      (context, sheet) => ProgressionChordSheet(key: ValueKey(sheet), index: sheet.arg as int?);
  FeatureRegistry.sheets['progressionInsert'] =
      (context, sheet) => ProgressionChordSheet(key: ValueKey(sheet), insertAt: sheet.arg as int?);
  FeatureRegistry.sheets['scaleBuilder'] = (context, sheet) => ScaleBuilderSheet(key: ValueKey(sheet), editingId: sheet.arg as String?);
  FeatureRegistry.sheets['chordBuilder'] = (context, sheet) => ChordBuilderSheet(key: ValueKey(sheet), editingId: sheet.arg as String?);

  FeatureRegistry.debugSheets['chordsFromNote'] = (app) => app.sheet = const AppSheet('chordsFromNote', NeckSpot(2, 5));
  FeatureRegistry.debugSheets['scaleFromNote'] = (app) => app.sheet = const AppSheet('scaleFromNote', NeckSpot(2, 5));
  FeatureRegistry.debugSheets['progressionFromNote'] = (app) => app.sheet = const AppSheet('progressionFromNote', NeckSpot(2, 5));
  FeatureRegistry.debugSheets['progressionChord'] = (app) => app.sheet = const AppSheet('progressionChord', 1);
  FeatureRegistry.debugSheets['progressionAdd'] = (app) => app.sheet = const AppSheet('progressionChord');
  FeatureRegistry.debugSheets['userScales'] = (app) {
    final draft = coreCall(app, 'fretboard.scaleDraft', {
      'id': 'user-demo',
      'name': 'Фригийский с ♮7',
      'semitones': [0, 1, 3, 5, 7, 8, 11],
      'tonic': app.settings.fretboard.tonic,
    });
    if (draft is Map && draft['scale'] is Map) {
      app.updateSettings((s) => s.customScales = [Map<String, dynamic>.from(draft['scale'] as Map)]);
    }
    app.fretboard.setScale('user-demo');
    app.sheet = const AppSheet('fretScale');
  };

  FeatureRegistry.debugHooks.add((app, args) {
    final fretboard = app.fretboard;
    fretOpenLibraryOnStart = args.has('-chordLibrary');
    fretCapoNoticeOnStart = args.has('-capo');
    fretLeftNoticeOnStart = args.has('-leftHanded');
    final loupe = args.value('-fretLoupe')?.split(':').map(int.tryParse).whereType<int>().toList();
    fretLoupeOnStart = loupe != null && loupe.length == 2 ? NeckSpot(loupe[0], loupe[1]) : null;
    if (args.has('-resetFretboard')) {
      app.updateSettings((s) => s.fretboard = FretboardSettings());
      fretboard.recompute();
    }
    if (args.has('-fretDemo')) {
      app.updateSettings((s) {
        final f = s.fretboard;
        f.scaleId = 'phrygian-dominant';
        f.tonic = {'letter': 2, 'accidental': 0};
        f.neckView = NeckDisplay.position;
        f.positionNumber = 2;
        f.labels = LabelMode.degrees;
      });
      fretboard.recompute();
    }
    if (args.has('-neckWhole') || args.has('-lowTop')) {
      app.updateSettings((s) {
        if (args.has('-neckWhole')) s.fretboard.neckView = NeckDisplay.wholeNeck;
        if (args.has('-lowTop')) s.fretboard.lowStringOnTop = true;
      });
      fretboard.recompute();
    }
    // Screenshot hook: `-fan` — the first typical fan of this instrument (PR-7).
    if (args.has('-fan')) {
      final r = coreCall(app, 'fretboard.fanPreset', {});
      if (r is Map) {
        final lengths = (r['lengths'] as List).map((e) => (e as num).toDouble()).toList();
        app.updateInstrument((inst) {
          inst['multiscale'] = r['multiscale'];
          final courses = inst['courses'] as List;
          for (var c = 0; c < courses.length; c++) {
            final strings = ((courses[c] as Map)['strings'] as List? ?? const []);
            for (final s in strings) {
              if (s is Map && c < lengths.length) s['scaleLength'] = lengths[c];
            }
          }
        });
      }
    }
    switch (args.value('-fretMode')) {
      case 'chord':
        fretboard.mode = FretMode.chord;
        fretboard.chordRoot = {'letter': 5, 'accidental': 0};
        fretboard.chordId = 'm7';
      case 'progression':
        fretboard.mode = FretMode.progression;
      case 'chordNone':
        fretboard.mode = FretMode.chord;
        fretboard.chordRoot = {'letter': 0, 'accidental': 0};
        fretboard.chordId = '13#11';
      case 'path':
        fretboard.pathKind = PathKind.threePerString;
      case 'path1':
        fretboard.pathKind = PathKind.oneString;
      case 'path4':
        fretboard.pathKind = PathKind.fourDiagonal;
      case 'search':
        // A C E G on an 8-string in Drop E: A on the 6th string, 5th fret; C, E, G nearby.
        fretboard.marked = const [NeckSpot(2, 5), NeckSpot(3, 7), NeckSpot(4, 5), NeckSpot(5, 5)];
        fretboard.mode = FretMode.search;
    }
    if (args.has('-fretTab')) fretboard.tabView = true;
    // Main boards: FlowNote1 — `-fretNote 2:5` (course:fret); FlowNote3 — `-fretProg` («A · I–V–vi–IV» on the neck).
    final note = args.value('-fretNote')?.split(':').map(int.tryParse).whereType<int>().toList();
    if (note != null && note.length == 2) {
      fretboard.mode = FretMode.scale;
      fretboard.noteSpot = NeckSpot(note[0], note[1]);
    }
    if (args.has('-leftHanded')) app.updateSettings((s) => s.fretboard.leftHanded = true);
    // FretChordTab: «Am7 · баррэ на 5-м» — `-fretVoicing 5` picks the first barre voicing at that fret.
    final barre = int.tryParse(args.value('-fretVoicing') ?? '');
    if (barre != null) {
      final i = fretboard.voicings.indexWhere((v) => v.barreFret == barre);
      if (i >= 0) fretboard.voicingIndex = i;
    }
    if (args.has('-fretProg')) {
      fretboard.mode = FretMode.progression; // first: entering the mode takes the scale's tonic
      fretboard.progression.templateId = 'pop';
      // FlowNote2 → «Показать на грифе»: from A on the 6th string, 5th fret — the hand stays there.
      fretboard.progression.start(NeckSpot(math.max(0, app.courseCount - 6), 5));
    }
    // Sheet boards (fork «S»): `-fretBpm 100` — the tempo of «Проигрывание»; `-progressionsDemo` — three saved
    // progressions of «Прогрессии» (FretProgressionList).
    final bpm = args.intValue('-fretBpm');
    if (bpm != null) fretboard.bpm = bpm.toDouble();
    if (args.has('-progressionsDemo')) fretboard.progression.injectSavedDemo();
    // Tab boards: S6/S7/S8Tab — `-fretTabDemo`; Tab* boards — `-fretTabDemoTonic`; FlowNote3Tab — `-fretProgTab`;
    // TabLargeText adds `-fretTabLarge`.
    if (args.has('-fretTabDemo') || args.has('-fretTabDemoTonic')) fretboard.tabDemo(lowest: args.has('-fretTabDemo'));
    if (args.has('-fretProgTab')) fretboard.progressionTabDemo();
    if (args.has('-trainingDemo')) fretboard.trainingDemo();
    if (args.has('-fretPlay')) Timer(const Duration(seconds: 1), fretboard.startPlayback);
    if (args.has('-progPlay')) Timer(const Duration(milliseconds: 1500), fretboard.progression.play);
  });
}

/// Registration of the instrument feature in the app shell: the sheets of «Инструмент и строи» (the tuning pill
/// opens `AppSheet('tunings')`), their `-sheet …` launch arguments and `-fan` (AppModel.swift).
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/feature_registry.dart';
import 'tunings_sheet.dart';

void registerInstrument() {
  final sheets = FeatureRegistry.sheets;
  sheets['tunings'] = (context, _) => const TuningsSheet();
  sheets['tuningsAdd'] = (context, _) => const TuningsAddSheet();
  sheets['tuningEditor'] = (context, sheet) => TuningEditorSheet(key: ValueKey(sheet.arg), tuningId: sheet.arg as String);
  sheets['library'] = (context, _) => const LibrarySheet();
  sheets['templateCard'] = (context, sheet) => TemplateCardSheet(templateId: sheet.arg as String);
  sheets['generator'] = (context, _) => const GeneratorSheet();
  sheets['instrument'] = (context, _) => const InstrumentSheet();
  sheets['instrumentRebuild'] = (context, sheet) => InstrumentRebuildSheet(key: ValueKey(sheet.arg), newCount: sheet.arg as int);
  sheets['instrumentStrings'] = (context, _) => const InstrumentStringsSheet();

  // Screenshot hooks (AppModel.swift `-sheet …`).
  final debug = FeatureRegistry.debugSheets;
  debug['tuningEditor'] = (app) => app.sheet = AppSheet('tuningEditor', app.tuning['id']);
  debug['templateCard'] = (app) => app.sheet = const AppSheet('templateCard', 'g8-standard-fs');
  debug['instrumentRebuild'] = (app) => app.sheet = AppSheet('instrumentRebuild', app.courseCount + 1);

  // Canvas boards of «Инструмент и строи» (TuningsDebug in TuningsSheet.swift): `-tuningsDemo` — five tunings of a
  // 6-string, `-sheet tuningsLastOne | tuningsDelete | tuningUnsaved | libraryDrop | generatorDropC`.
  FeatureRegistry.debugHooks.add((app, args) {
    if (args.has('-tuningsDemo')) {
      try {
        final r = app.core?.call('instrument.demo');
        if (r is Map) {
          final next = Map<String, dynamic>.from(r);
          app.updateInstrument((i) => i
            ..clear()
            ..addAll(next));
        }
      } catch (_) {}
    }
    switch (args.value('-sheet')) {
      case 'tuningsLastOne':
        TuningsDebug.lastOneToast = true;
        app.sheet = const AppSheet('tunings');
      case 'tuningsDelete':
        TuningsDebug.deleteLast = true;
        app.sheet = const AppSheet('tunings');
      case 'tuningUnsaved':
        TuningsDebug.unsaved = true;
        app.sheet = AppSheet('tuningEditor', app.tuning['id']);
      case 'libraryDrop':
        TuningsDebug.libraryCategory = 'drop';
        app.sheet = const AppSheet('library');
      case 'generatorDropC':
        TuningsDebug.generator = (4, 2);
        app.sheet = const AppSheet('generator');
    }
  });

  // `-fan` — the first typical fan of this instrument (PR-7); the fretboard draws it from the instrument.
  FeatureRegistry.debugHooks.add((app, args) {
    if (!args.has('-fan')) return;
    try {
      final r = app.core?.call('instrument.applyFan', {'preset': 0});
      if (r is Map) {
        final next = Map<String, dynamic>.from(r);
        app.updateInstrument((i) => i
          ..clear()
          ..addAll(next));
      }
    } catch (_) {}
  });
}

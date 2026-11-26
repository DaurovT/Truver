/// Port of Truver/Sources/App/AppModel.swift
///
/// Root state: settings, the instrument with its tunings, audio, the shell state (tab, sheet, toasts, covers)
/// and the feature controllers. Widgets read it with `AppScope.of(context)` (rebuilds on change) or
/// `AppScope.read(context)` (no subscription).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../core/truver_core.dart';
import '../design/icons.dart';
import '../design/theme.dart';
import '../features/fretboard/fretboard_controller.dart';
import '../features/metronome/metronome_controller.dart';
import '../features/metronome/play_check_controller.dart';
import '../features/practice/fret_trainer_controller.dart';
import '../features/practice/practice_session_controller.dart';
import '../features/practice/practice_tracker.dart';
import '../features/tuner/tuner_controller.dart';
import 'audio_services.dart';
import 'debug_args.dart';
import 'feature_registry.dart';
import 'storage.dart';

/// Sheets drawn by the app itself (canvas chrome) rather than by the system. iOS `AppSheet` cases become
/// `kind` names with the associated value in `arg`: `AppSheet('metroTimer')`, `AppSheet('tuningEditor', id)`,
/// `AppSheet('metroModeParams', 'speedUp')`, `AppSheet('chordsFromNote', (2, 5))`…
@immutable
class AppSheet {
  const AppSheet(this.kind, [this.arg]);
  final String kind;
  final Object? arg;

  @override
  bool operator ==(Object other) => other is AppSheet && other.kind == kind && other.arg == arg;

  @override
  int get hashCode => Object.hash(kind, arg);

  @override
  String toString() => arg == null ? 'AppSheet($kind)' : 'AppSheet($kind, $arg)';
}

class AppModel extends ChangeNotifier {
  AppModel({required this.store, required this.args, TruverCore? core, bool loadCore = true})
      : core = core ?? (loadCore ? TruverCore.instance : null) {
    audio = AudioServices(this.core);
    var s = AppSettings.load(store);
    if (args.has('-resetSettings')) s = AppSettings();
    if (args.has('-skipOnboarding')) s.onboarded = true;
    final tab = AppTab.byName(args.value('-tab'));
    if (tab != null) s.lastTab = tab;
    _settings = s;
    _showOnboarding = !s.onboarded;
    onboardingStep = args.intValue('-onboardingStep') ?? 0;
    audio.latencyOffsets = s.latencyOffsets;

    _instrument = StoredInstrument.load(store) ?? _templateInstrument('g6-standard-e') ?? _fallbackInstrument;
    StoredInstrument.save(store, _instrument);
    _pushSession();
    _pushUserLibrary();

    tuner = TunerController()..app = this;
    metronome = MetronomeController()..app = this;
    fretboard = FretboardController()..app = this;
    practice = PracticeTracker()..app = this;
    trainer = FretTrainerController()..app = this;
    playCheck = PlayCheckController()..app = this;
    session = PracticeSessionController()..app = this;
    audio.onConfigurationChange = tuner.handleAudioRestart;
    // TODO(android): interruptions (calls) → metronome.interrupt() + fretboard.stopPlayback(), route changes
    // («Интерфейс отключён…», Bluetooth) — when the audio host reports them through `audio.poll` notices.

    // Screenshot / test hook: start with a given template.
    final template = args.value('-template');
    if (template != null) replaceInstrument(template);
    fretboard.recompute();

    // SND-7 volumes (settings «Громкость»).
    audio.setVolumes(
      click: store.getDouble('vol.click') ?? 0.8,
      notes: store.getDouble('vol.notes') ?? 0.6,
      reference: store.getDouble('vol.reference') ?? 0.5,
      sound: s.metronome.sound,
    );
    // UI checks stay silent.
    if (args.has('-muteAudio')) audio.setVolumes(click: 0, notes: 0, reference: 0);

    final notation = args.value('-notation');
    if (notation != null && const ['international', 'german', 'solfege'].contains(notation)) {
      updateSettings((s) => s.notation = notation);
    }
    final capo = args.intValue('-capo');
    if (capo != null) updateInstrument((i) => i['capo'] = capo);

    final sheetArg = args.value('-sheet');
    if (sheetArg != null) {
      final hook = FeatureRegistry.debugSheets[sheetArg];
      if (hook != null) {
        hook(this);
      } else if (FeatureRegistry.sheets.containsKey(sheetArg)) {
        _sheet = AppSheet(sheetArg);
      }
    }
    if (args.has('-showSettings') || args.has('-settingsPage')) _showSettings = true;
    for (final hook in FeatureRegistry.debugHooks) {
      hook(this, args);
    }
  }

  final SettingsStore store;
  final DebugArgs args;

  /// The Swift core; null only when the library failed to load.
  final TruverCore? core;
  late final AudioServices audio;

  late final TunerController tuner;
  late final MetronomeController metronome;
  late final FretboardController fretboard;
  late final PracticeTracker practice;

  /// FB-12 «Тренажёр грифа» (full screen from «Занятия»).
  late final FretTrainerController trainer;

  /// Stage SM «Проверка игры» on the metronome.
  late final PlayCheckController playCheck;

  /// PL-1, PL-2 «Занятие».
  late final PracticeSessionController session;

  // MARK: Settings

  late AppSettings _settings;
  AppSettings get settings => _settings;

  /// Replaces the settings (saved, side effects applied, listeners notified).
  set settings(AppSettings value) => updateSettings((s) => _settings = value);

  /// Mutates the settings in place: `app.updateSettings((s) => s.vibration = true)`.
  void updateSettings(void Function(AppSettings s) mutate) {
    final before = _settings.copy();
    final beforeJson = before.encode();
    mutate(_settings);
    if (_settings.encode() == beforeJson) return;
    _settings.save(store);
    if (jsonEncode(_settings.metronome.toJson()) != jsonEncode(before.metronome.toJson())) {
      // TODO(android): publish to the home-screen widget / quick settings tile (iOS `schedulePublish`).
    }
    if (jsonEncode(_settings.latencyOffsets) != jsonEncode(before.latencyOffsets)) audio.latencyOffsets = _settings.latencyOffsets;
    if (jsonEncode([_settings.customScales, _settings.customChords]) != jsonEncode([before.customScales, before.customChords])) {
      _pushUserLibrary();
    }
    if (_settings.notation != before.notation || _settings.defaultA4 != before.defaultA4) _pushSession();
    if (_settings.lastTab != before.lastTab) updateListening();
    notifyListeners();
  }

  AppTab get tab => _settings.lastTab;
  set tab(AppTab value) => updateSettings((s) => s.lastTab = value);

  // MARK: Shell state

  bool _showOnboarding = true;
  bool get showOnboarding => _showOnboarding;
  set showOnboarding(bool v) {
    if (v == _showOnboarding) return;
    _showOnboarding = v;
    updateListening();
    notifyListeners();
  }

  /// `-onboardingStep N` (debug): the onboarding step to open (0 welcome, 1 instrument, 2 microphone).
  int onboardingStep = 0;

  bool _showSettings = false;
  bool get showSettings => _showSettings;
  set showSettings(bool v) => _set(() => _showSettings = v, v != _showSettings);

  bool _showSession = false;
  bool get showSession => _showSession;
  set showSession(bool v) => _set(() => _showSession = v, v != _showSession);

  bool _showTrainer = false;
  bool get showTrainer => _showTrainer;
  set showTrainer(bool v) => _set(() => _showTrainer = v, v != _showTrainer);

  /// Canvas-style sheet over the whole app (dim + panel), see `SheetHost`.
  AppSheet? _sheet;
  AppSheet? get sheet => _sheet;
  set sheet(AppSheet? v) => _set(() => _sheet = v, v != _sheet);

  /// «Копией текущего»: the copy lives here until «Сохранить» — closing the editor leaves no trace.
  Map<String, dynamic>? unsavedTuning;

  /// The tuning editor was opened from the tuner's pro panel: closing it returns to the tuner, not to the list.
  bool tuningEditorFromTuner = false;
  bool showTunings = false;

  String? _notice;
  String? get notice => _notice;

  /// Icon of the current notice (canvas toasts: lock, Bluetooth, warning); null = the plain capsule.
  AppIcon? noticeIcon;
  Color noticeIconColor = TruverColors.textSecondary;
  Timer? _noticeTimer;

  /// Shows a toast for 2.5 s; a new one replaces the old in place.
  void show(String text, {AppIcon? icon, Color iconColor = TruverColors.textSecondary}) {
    noticeIcon = icon;
    noticeIconColor = iconColor;
    _notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(milliseconds: 2500), () {
      if (_notice == text) {
        _notice = null;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// Refresh listeners after a controller changed shared state.
  void changed() => notifyListeners();

  void _set(VoidCallback apply, bool changed) {
    if (!changed) return;
    apply();
    notifyListeners();
  }

  // MARK: Instrument

  late Map<String, dynamic> _instrument;

  /// The core's `Instrument` JSON (name, type, courses, fretCount, capo, multiscale, tunings, currentTuningId).
  /// Read-only: change it with [updateInstrument] / [replaceInstrument].
  Map<String, dynamic> get instrument => _instrument;

  /// The current `Tuning` JSON (name, openCents, a4, accidentalPreference, templateId…).
  Map<String, dynamic> get tuning {
    final tunings = (_instrument['tunings'] as List).cast<Map<String, dynamic>>();
    final id = _instrument['currentTuningId'];
    return tunings.where((t) => t['id'] == id).firstOrNull ?? tunings.first;
  }

  List<Map<String, dynamic>> get tunings => (_instrument['tunings'] as List).cast<Map<String, dynamic>>();

  String get tuningName => tuning['name'] as String? ?? '';

  /// A4 in effect: the tuning's own or the app default (PR-5).
  double get a4 => (tuning['a4'] as num?)?.toDouble() ?? _settings.defaultA4;

  int get courseCount => (_instrument['courses'] as List).length;

  /// Tuning pill (canvas «8-струнная · Drop E»): the instrument word is dropped when the name starts with the
  /// string count; a custom name is shown as is.
  String get title => '${shortInstrumentName(_instrument['name'] as String? ?? '')} · $tuningName';

  /// «8-струнная гитара» → «8-струнная»; old default names «Гитара, 8 струн» too (the switcher and the journal).
  static String shortInstrumentName(String full) {
    var name = full;
    final match = RegExp(r'^Гитара, (\d+) струн[аы]?$').firstMatch(name);
    if (match != null) name = '${match.group(1)}-струнная гитара';
    for (final word in [' гитара', ' бас']) {
      if (name.endsWith(word) && name.isNotEmpty && RegExp(r'^\d').hasMatch(name)) {
        name = name.substring(0, name.length - word.length);
      }
    }
    return name;
  }

  /// A note in the app's notation: core `NoteName` JSON, with an octave for a spelled note («F♯1», «соль♯2»).
  String noteName(Map<String, dynamic> name, {int? octave}) =>
      _coreString('shell.noteName', {'name': name, 'octave': ?octave}) ?? '';

  /// Name of a string of the current tuning ("B1", "F♯1" or "H1" in German notation).
  String stringName(int course, [int string = 0]) => _coreString('shell.stringName', {'course': course, 'string': string}) ?? '';

  /// Chromatic note name of `cents` (from A4 = 440) with the tuning's accidental family.
  String chromaticName(double cents) => _coreString('shell.chromaticName', {'cents': cents}) ?? '';

  String? _coreString(String method, Map<String, dynamic> params) {
    try {
      return core?.call(method, params) as String?;
    } catch (_) {
      return null;
    }
  }

  // MARK: Instrument edits

  bool get isSmartModeRunning => false; // stage SM

  /// Mutates a copy of the instrument JSON; saves, pushes it to the core and tells the tuner / fretboard.
  void updateInstrument(void Function(Map<String, dynamic> instrument) mutate) {
    final copy = jsonCopy(_instrument);
    mutate(copy);
    if (jsonEncode(copy) == jsonEncode(_instrument)) return;
    final oldTuning = jsonEncode(tuning), oldCourses = jsonEncode(_instrument['courses']);
    final neckChanged = copy['capo'] != _instrument['capo'] || copy['fretCount'] != _instrument['fretCount'];
    _instrument = copy;
    final tuningChanged = jsonEncode(tuning) != oldTuning || jsonEncode(copy['courses']) != oldCourses;
    StoredInstrument.save(store, copy);
    _pushSession();
    if (tuningChanged) tuner.tuningChanged();
    if (tuningChanged || neckChanged) fretboard.recompute(notifyPosition: true);
    notifyListeners();
  }

  void selectTuning(String id) => updateInstrument((i) => i['currentTuningId'] = id);

  /// A template of the same type and string count is added (and becomes current); another one replaces the
  /// instrument (6.1 п. 19).
  void addTemplate(String templateId) {
    final result = _call('shell.addTemplate', {'id': templateId});
    if (result is! Map) return;
    if (result['incompatible'] == true) {
      replaceInstrument(templateId);
    } else if (result['instrument'] is Map) {
      final next = Map<String, dynamic>.from(result['instrument'] as Map);
      updateInstrument((i) => i
        ..clear()
        ..addAll(next));
    }
  }

  /// 6.1 п. 19: a template of another type or string count replaces the instrument; the journal keeps its names.
  /// `fretCount`: the user's choice; null keeps the current instrument's frets when the new one is of the same
  /// kind (a 22-fret guitar stays 22-fret after picking another guitar template).
  void replaceInstrument(String templateId, {int? fretCount}) {
    final result = _call('shell.replaceInstrument', {'id': templateId, 'fretCount': ?fretCount});
    if (result is! Map) return;
    _instrument = Map<String, dynamic>.from(result);
    StoredInstrument.save(store, _instrument);
    _pushSession();
    tuner.tuningChanged();
    fretboard.recompute(notifyPosition: false);
    notifyListeners();
  }

  void deleteTuning(String id) => updateInstrument((i) {
        final tunings = (i['tunings'] as List).cast<Map<String, dynamic>>();
        if (tunings.length <= 1) return; // the last tuning cannot be deleted (6.2.3)
        tunings.removeWhere((t) => t['id'] == id);
        if (i['currentTuningId'] == id) i['currentTuningId'] = tunings.first['id'];
      });

  /// The tuner listens only while its tab is open and onboarding is done (AU-4, 6.1 п. 1, 4).
  void updateListening() {
    // 6.1 п. 5: the tuner must not listen to the drone through the speaker.
    if (_settings.lastTab == AppTab.tuner) fretboard.stopDrone();
    if ((_settings.lastTab == AppTab.tuner || trainer.needsMicrophone || playCheck.isOn) && !_showOnboarding) {
      tuner.start();
    } else if (tuner.isListening) {
      tuner.stop();
    }
  }

  // MARK: Core session

  dynamic _call(String method, Map<String, dynamic> params) {
    try {
      return core?.call(method, params);
    } catch (e) {
      debugPrint('$method: $e');
      return null;
    }
  }

  /// The core formats names and computes everything for the current instrument, notation and A4.
  void _pushSession() =>
      _call('session.set', {'instrument': _instrument, 'notation': _settings.notation, 'defaultA4': _settings.defaultA4});

  void _pushUserLibrary() =>
      _call('shell.userLibrary', {'scales': _settings.customScales, 'chords': _settings.customChords});

  Map<String, dynamic>? _templateInstrument(String id) {
    final r = _call('theory.instrumentFromTemplate', {'id': id});
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  /// Only when the core library is missing: enough for the shell to draw.
  static final _fallbackInstrument = <String, dynamic>{
    'id': '00000000-0000-4000-8000-000000000000',
    'name': '6-струнная гитара',
    'type': 'guitar',
    'courses': [for (var i = 0; i < 6; i++) {'startFret': 0, 'pairing': 'single', 'strings': [{}]}],
    'frets': {'equalTempered': {}},
    'fretCount': 24,
    'capo': 0,
    'tunings': [
      {
        'id': '00000000-0000-4000-8000-000000000001',
        'name': 'Стандарт E',
        'openCents': [[-2900], [-2400], [-1900], [-1400], [-1000], [-500]],
        'offsetsCents': [],
        'temperament': {'equal': {}},
        'accidentalPreference': 'auto',
        'isTemplateCopy': true,
        'templateId': 'g6-standard-e',
      },
    ],
    'currentTuningId': '00000000-0000-4000-8000-000000000001',
  };

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }
}

/// Provides the [AppModel] to the widget tree (SwiftUI `.environment(model)`).
class AppScope extends InheritedNotifier<AppModel> {
  const AppScope({super.key, required AppModel app, required super.child}) : super(notifier: app);

  /// The model, rebuilding the caller on every change.
  static AppModel of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// The model without subscribing (callbacks, initState).
  static AppModel read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Port of Truver/Sources/Features/Metronome/MetronomeController.swift
///
/// Metronome screen state (6.2.6): playback, modes, presets, timer, beat strip driven by the timeline (ME-12).
/// The meter is the core `MeterSettings` JSON; figures, tap tempo, the flash rule and the modes → `TrainingModes`
/// conversion come from the core (`metronome.*`, TruverBridge/MetronomeCommands.swift); playback through
/// `audio.startMetronome` / `audio.updateMetronome` / `audio.stopMetronome`, ticks and notices from `audio.poll`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/app_model.dart';
import '../../app/audio_services.dart';
import '../../app/storage.dart';
import '../../design/icons.dart';
import 'rhythm_library.dart';

/// AccentLevel raw values of the core.
abstract final class Accent {
  static const off = 0, soft = 1, normal = 2, strong = 3;

  /// `AccentLevel.next`: strong → normal → soft → off → strong.
  static int next(int level) => switch (level) {
    strong => normal,
    normal => soft,
    soft => off,
    _ => strong,
  };
}

/// Typed reads of a core `MeterSettings` JSON map.
extension MeterJson on Map<String, dynamic> {
  double get bpm => (this['bpm'] as num?)?.toDouble() ?? 120;
  int get numerator => (this['numerator'] as num?)?.toInt() ?? 4;
  int get denominator => (this['denominator'] as num?)?.toInt() ?? 4;
  List<int>? get grouping => (this['grouping'] as List?)?.map((e) => (e as num).toInt()).toList();
  List<int> get accents => [for (final a in (this['accents'] as List? ?? const [])) (a as num).toInt()];
  int get subdivision => (this['subdivision'] as num?)?.toInt() ?? 1;
  double get swing => (this['swing'] as num?)?.toDouble() ?? 0.5;
  Map<String, dynamic>? get rhythm => this['rhythm'] is Map ? Map<String, dynamic>.from(this['rhythm'] as Map) : null;
  List<Map<String, dynamic>?>? get beatRhythms =>
      (this['beatRhythms'] as List?)?.map((e) => e is Map ? Map<String, dynamic>.from(e) : null).toList();
  Map<String, dynamic>? get poly => this['poly'] is Map ? Map<String, dynamic>.from(this['poly'] as Map) : null;

  /// `MeterSettings.isSwingAvailable`.
  bool get isSwingAvailable => subdivision % 2 == 0;

  /// `rhythm(forBeat:)`: the beat's own figure, else the common one.
  Map<String, dynamic>? rhythmForBeat(int beat) {
    final own = beatRhythms;
    if (own != null && beat < own.length && own[beat] != null) return own[beat];
    return rhythm;
  }

  /// Writes an optional key the way Swift's Codable does (absent when nil).
  void put(String key, Object? value) => value == null ? remove(key) : this[key] = value;
}

class MetronomeToast {
  const MetronomeToast({required this.icon, required this.text});
  final AppIcon icon;
  final String text;

  @override
  bool operator ==(Object other) => other is MetronomeToast && other.icon == icon && other.text == text;
  @override
  int get hashCode => Object.hash(icon, text);
}

enum ChipKind { plain, mode, target, timer, warning }

enum ChipAction { modes, timer, meter }

/// The modes of the canvas «Режимы» (one at a time) and the app's other modes.
enum ModeChoice { normal, speedUp, twoForward, fastSlow, songMap, gapBars, randomMute, displaced, ladder }

/// «Занятие закончено»: «20 минут · Риф 7/8 · темп вырос с 142 до 156. Записали в «Занятия».»
class SessionEnd {
  const SessionEnd({required this.minutes, this.name, required this.startBPM, required this.endBPM});
  final int minutes;
  final String? name;
  final double startBPM, endBPM;

  String get message {
    final parts = ['$minutes ${MetronomeController.plural(minutes, 'минута', 'минуты', 'минут')}', ?name];
    final a = startBPM.round(), b = endBPM.round();
    parts.add(a == b ? 'темп $b' : (b > a ? 'темп вырос с $a до $b' : 'темп с $a до $b'));
    return '${parts.join(' · ')}. Записали в «Занятия».';
  }
}

class MetronomeChip {
  const MetronomeChip({required this.kind, required this.text, this.action});
  final ChipKind kind;
  final String text;
  final ChipAction? action;
  String get id => text;
}

/// `FlashRule` of the core.
class FlashRule {
  const FlashRule(this.kind, [this.n]);
  final String kind;
  final int? n;
}

class MetronomeController extends ChangeNotifier {
  late AppModel app;

  static const bpmMin = 20.0, bpmMax = 400.0;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  int? _currentBeat;

  /// Beat index within the bar while playing (the tab bar dot is bright on 0).
  int? get currentBeat => _currentBeat;
  int currentBar = 0;

  /// The beat that flashes now (6.1 п. 9); null between flashes.
  int? flashBeat;
  bool flashOn = false;
  bool silentBar = false;
  double? liveBPM;
  double? timerRemaining;
  bool timerExpired = false;
  bool targetReached = false;

  /// Stopped by a call or another app (6.1 п. 6): the screen offers «Продолжить».
  bool interrupted = false;

  /// Where the interruption caught the metronome: «Продолжить с 150 BPM, такт 12».
  double? interruptedBPM;
  int interruptedBar = 1;

  /// Canvas «Таймер — время вышло»: the session summary alert after the timer stops the metronome.
  SessionEnd? sessionEnd;

  /// Tempo at the start of this session (for «темп вырос с 142 до 156»).
  double? _sessionStartBPM;

  /// Debug (screenshots): a beat kept lit, as on the canvas boards.
  int? debugLitBeat;

  /// Debug: the preset row shown swiped open (`-metroSwipe`).
  String? debugOpenPreset;

  /// Bars since the last tempo step — for «до 146 через 2 такта».
  int barsSinceTempoChange = 0;

  /// Карта песни: the playing part, the bar inside it, the count-in bar.
  int songSection = 0;
  int songBar = 0;
  bool songCountIn = false;

  static String parts(int n) => plural(n, 'часть', 'части', 'частей');
  double secondsSinceTempoChange = 0;

  /// Started by scale playback (6.1 п. 14), stopped together with it.
  bool startedByPlayback = false;

  /// Screen toast (canvas: top of the screen, over the beat strip).
  MetronomeToast? toast;

  final List<Map<String, dynamic>> _pending = [];
  bool _listening = false;
  DateTime? timerEnd;
  bool _stopAtNextBar = false;
  bool _stopAfterSong = false;
  bool _restarting = false;
  DateTime _lastTempoChange = DateTime.now();
  DateTime _lastActivity = DateTime.now();
  Timer? _toastTimer;
  Timer? _flashTimer;

  // MARK: Settings

  /// The metronome settings (`AppSettings.metronome`).
  MetronomeSettingsState get state => app.settings.metronome;

  /// Swift `state = …`: mutates the settings; a playing metronome takes the new meter from the next beat.
  void updateState(void Function(MetronomeSettingsState s) change) {
    app.updateSettings((s) => change(s.metronome));
    if (isPlaying) _send('audio.updateMetronome', {'settings': state.meter});
    notifyListeners();
  }

  Map<String, dynamic> get meter => state.meter;

  /// `MeterSettings.defaultAccents` from the core.
  List<int> defaultAccents(int numerator, List<int>? grouping) {
    try {
      final r = app.core?.call('metronome.defaultAccents', {'numerator': numerator, 'grouping': ?grouping});
      if (r is List) return [for (final a in r) (a as num).toInt()];
    } catch (_) {}
    return [Accent.strong, for (var i = 1; i < numerator; i++) Accent.normal];
  }

  /// Swift `meter` setter: accents follow the numerator; beats that no longer exist lose their own figure.
  set meter(Map<String, dynamic> value) {
    final m = jsonCopy(value);
    if (m.accents.length != m.numerator) m['accents'] = defaultAccents(m.numerator, m.grouping);
    // Beats that no longer exist lose their own figure (it came back after 4 → 3 → 4 — UX check).
    final own = m.beatRhythms;
    if (own != null && own.length > m.numerator) {
      final kept = own.take(m.numerator).toList();
      m.put('beatRhythms', kept.every((e) => e == null) ? null : kept);
    }
    updateState((s) => s.meter = m);
  }

  /// A copy of the meter changed by `change` and stored.
  void updateMeter(void Function(Map<String, dynamic> m) change) {
    final m = jsonCopy(meter);
    change(m);
    meter = m;
  }

  double get bpm => meter.bpm;
  set bpm(double value) => updateMeter((m) => m['bpm'] = value.roundToDouble().clamp(bpmMin, bpmMax));

  MetronomeModes get modes => MetronomeModes.fromJson(state.modes.toJson());
  set modes(MetronomeModes value) {
    updateState((s) => s.modes = MetronomeModes.fromJson(value.toJson()));
    restartIfPlaying();
  }

  /// A copy of the modes changed by `change` and stored (restarts a playing metronome).
  void updateModes(void Function(MetronomeModes m) change) {
    final m = modes;
    change(m);
    modes = m;
  }

  /// The tempo shown on the knob: the live one while a mode changes it.
  /// Before the start a tempo mode shows its starting tempo (it jumped from 100 to 120 on start — iPhone UX check).
  double get displayBPM {
    if (isPlaying) return liveBPM ?? bpm;
    final m = state.modes;
    if (m.tempo == ModeTempo.songMap) {
      final first = m.song.firstOrNull;
      return first == null ? bpm : (first['bpm'] as num).toDouble();
    }
    return m.tempo != ModeTempo.none ? m.start.clamp(bpmMin, bpmMax) : bpm;
  }

  /// The core's `TrainingModes` JSON for the engine (`metronome.trainingModes`).
  Map<String, dynamic>? get trainingModes {
    try {
      final r = app.core?.call('metronome.trainingModes', {'modes': state.modes.toJson()});
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (e) {
      debugPrint('metronome.trainingModes: $e');
      return null;
    }
  }

  bool get atMaximum => displayBPM >= bpmMax;
  bool get atMinimum => displayBPM <= bpmMin;

  /// Flash thinning at fast tempos (6.1 п. 9).
  FlashRule get flashRule => _rule(_meterForFlash);

  Map<String, dynamic> get _meterForFlash => {...meter, 'bpm': displayBPM};

  String? _ruleKey;
  FlashRule _ruleCache = const FlashRule('everyBeat');

  FlashRule _rule(Map<String, dynamic> m) {
    final key = jsonEncode([m.bpm, m.numerator, m.accents]);
    if (key == _ruleKey) return _ruleCache;
    _ruleKey = key;
    try {
      final r = app.core?.call('metronome.flashRule', {'settings': m});
      if (r is Map) _ruleCache = FlashRule(r['kind'] as String, (r['n'] as num?)?.toInt());
    } catch (_) {}
    return _ruleCache;
  }

  /// `FlashPolicy.flashes`.
  static bool flashes(Map<String, dynamic> tick, FlashRule rule, List<int> accents) {
    final beat = (tick['beat'] as num).toInt(), bar = (tick['bar'] as num).toInt();
    if (tick['silent'] == true || tick['tick'] != 0 || tick['level'] == Accent.off) return false;
    return switch (rule.kind) {
      'strongBeats' => beat < accents.length && accents[beat] == Accent.strong,
      'firstBeat' => beat == 0,
      'everyNthBar' => beat == 0 && bar % (rule.n ?? 1) == 0,
      _ => true,
    };
  }

  // MARK: Status line and chips (canvas «Метроном — остановлен / играет / цель»)

  /// One grey line under the beat strip: a silent bar, the tempo limits, otherwise the mode at work
  /// («Разгон: 142 → 160 · +2 каждые 4 такта», «Разгон завершён · держим 160»).
  String? get statusText {
    if (isPlaying && silentBar) {
      return state.modes.sound == ModeSound.randomMute ? 'Пропуск · держите темп сами' : 'Тихий такт · держите темп сами';
    }
    if (atMaximum) return '400 BPM — максимум';
    if (atMinimum) return '20 BPM — минимум';
    return _modeStatus;
  }

  String? get _modeStatus {
    final m = state.modes;
    switch (m.tempo) {
      case ModeTempo.speedUp || ModeTempo.twoForward:
        final title = m.tempo == ModeTempo.speedUp ? 'Разгон' : 'Два вперёд';
        if (targetReached && isPlaying) return '$title завершён · держим ${m.target.toInt()}';
        final every = m.tempo == ModeTempo.speedUp && m.interval == ModeInterval.seconds
            ? 'каждые ${m.everySeconds} с'
            : 'каждые ${m.every} ${bars(m.every)}';
        return '$title: ${m.start.toInt()} → ${m.target.toInt()} · +${m.step.toInt()} $every';
      case ModeTempo.fastSlow:
        return 'Быстро / медленно: ${m.start.toInt()} ↔ ${m.fast.toInt()} · по ${m.fastSlowBars} ${bars(m.fastSlowBars)}';
      case ModeTempo.songMap:
        return _tempoChipText;
      case ModeTempo.none:
        break;
    }
    switch (m.sound) {
      case ModeSound.gapBars:
        return 'Тренировка пропусков: играет ${m.gapOn} ${bars(m.gapOn)}, молчит ${m.gapOff}';
      case ModeSound.randomMute:
        return 'Случайный пропуск: ${m.muteChance} % долей молчат';
      case ModeSound.displaced:
        return 'Перенос щелчка: ${patternTitle(m.pattern)}';
      case ModeSound.none:
        break;
    }
    if (m.subdivision == ModeSubdivision.ladder) {
      return 'Лесенка делений: 1 → 2 → 3 → 4 · по ${m.ladderBarsPerStep} ${bars(m.ladderBarsPerStep)}';
    }
    return null;
  }

  /// The mode chip: «Режим», or the active mode («↑ Разгон»), emphasized.
  MetronomeChip get modeChip {
    final m = state.modes;
    final String? title = switch (m.tempo) {
      ModeTempo.speedUp => 'Разгон',
      ModeTempo.twoForward => 'Два вперёд',
      ModeTempo.fastSlow => 'Быстро / медленно',
      ModeTempo.songMap => 'Карта песни',
      ModeTempo.none => switch (m.sound) {
        ModeSound.gapBars => 'Тренировка пропусков',
        ModeSound.randomMute => 'Случайный пропуск',
        ModeSound.displaced => 'Перенос щелчка',
        ModeSound.none => m.subdivision == ModeSubdivision.ladder ? 'Лесенка делений' : null,
      },
    };
    if (title == null) return const MetronomeChip(kind: ChipKind.plain, text: 'Режим', action: ChipAction.modes);
    return MetronomeChip(kind: ChipKind.mode, text: title, action: ChipAction.modes);
  }

  /// Chips after «♫ · Проверка · 7/8 · Режим»: the second track, the timer, flash thinning.
  List<MetronomeChip> get chips {
    final mt = meter;
    final result = <MetronomeChip>[];
    final poly = mt.poly;
    if (poly != null) {
      final count = (poly['count'] as num).toInt();
      result.add(
        MetronomeChip(
          kind: ChipKind.plain,
          text: poly['kind'] == 'rhythm' ? 'Полиритм $count:${mt.numerator}' : 'Полиметр $count/${mt.numerator}',
          action: ChipAction.meter,
        ),
      );
    }
    if (timerExpired) {
      result.add(MetronomeChip(kind: ChipKind.timer, text: 'Таймер ${clock(state.timerMinutes * 60.0)} · истёк', action: ChipAction.timer));
    } else if (timerRemaining != null) {
      result.add(MetronomeChip(kind: ChipKind.timer, text: clock(timerRemaining!), action: ChipAction.timer));
    } else if (state.timerEnabled) {
      result.add(MetronomeChip(kind: ChipKind.timer, text: clock(state.timerMinutes * 60.0), action: ChipAction.timer));
    }
    final note = _flashNote;
    if (isPlaying && state.flash != FlashTarget.off && note != null) {
      result.add(MetronomeChip(kind: ChipKind.warning, text: note));
    }
    return result;
  }

  /// The beat lit on the strip now.
  int? get litBeat => debugLitBeat ?? (flashOn && state.flash != FlashTarget.off ? flashBeat : null);

  /// Canvas «Прервано звонком»: «Остановлено звонком. Продолжить с 150 BPM, такт 12».
  String get interruptionText =>
      'Остановлено звонком. Продолжить с ${(interruptedBPM ?? bpm).round()} BPM, такт $interruptedBar';

  String? get _flashNote {
    final rule = flashRule;
    return switch (rule.kind) {
      'strongBeats' => 'Вспышка: только сильные доли',
      'firstBeat' => 'Вспышка: только первая доля',
      'everyNthBar' => 'Вспышка: раз в ${rule.n} ${bars(rule.n ?? 1)}',
      _ => null,
    };
  }

  String get _tempoChipText {
    final m = state.modes;
    if (m.tempo == ModeTempo.songMap) {
      final part = songSection >= 0 && songSection < m.song.length ? m.song[songSection] : null;
      if (!isPlaying || part == null) return 'Карта песни · ${m.song.length} ${parts(m.song.length)}';
      if (songCountIn) return 'Отсчёт · затем ${part['name']}';
      final partBars = (part['bars'] as num).toInt();
      return '${part['name']} · такт ${(songBar + 1).clamp(-1 << 31, partBars)}/$partBars';
    }
    if (m.tempo == ModeTempo.fastSlow) {
      final range = '${m.start.toInt()} ↔ ${m.fast.toInt()}';
      if (!isPlaying) return 'Быстро / медленно · $range';
      final other = displayBPM.round() == m.start.round() ? m.fast : m.start;
      final left = (m.fastSlowBars - barsSinceTempoChange).clamp(1, 1 << 31);
      return '$range · ${other.toInt()} через $left ${bars(left)}';
    }
    final title = m.tempo == ModeTempo.speedUp ? 'Разгон' : 'Два вперёд';
    if (!isPlaying) return '$title · ${m.start.toInt()} → ${m.target.toInt()}';
    final current = displayBPM;
    final next = (current + m.step) < m.target ? current + m.step : m.target;
    if (m.tempo == ModeTempo.speedUp && m.interval == ModeInterval.seconds) {
      final left = (m.everySeconds - secondsSinceTempoChange).ceil().clamp(1, 1 << 31);
      return '$title · до ${next.toInt()} через $left с';
    }
    final left = (m.every - barsSinceTempoChange).clamp(1, 1 << 31);
    return '$title · до ${next.toInt()} через $left ${bars(left)}';
  }

  String patternTitle(String pattern) => switch (pattern) {
    'offbeats' => 'только «и»',
    'downbeat' => 'только раз',
    _ => 'только 2 и 4',
  };

  /// «Продолжить · 142 BPM · Разгон».
  String get resumeTitle => ['Продолжить', '${bpm.toInt()} BPM', ...state.modes.activeTitles.take(1)].join(' · ');

  static String bars(int n) => plural(n, 'такт', 'такта', 'тактов');

  /// `ModeParamsSheet.plural`.
  static String plural(int n, String one, String few, String many) {
    final n10 = n % 10, n100 = n % 100;
    if (n10 == 1 && n100 != 11) return one;
    if (n10 >= 2 && n10 <= 4 && !(n100 >= 12 && n100 <= 14)) return few;
    return many;
  }

  static String clock(double seconds) {
    final total = seconds.ceil();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  // MARK: Playback

  void toggle() => isPlaying ? stop() : start();

  void start({bool byPlayback = false}) {
    if (isPlaying) return;
    final settings = jsonCopy(meter);
    if (state.modes.tempo != ModeTempo.none && !byPlayback) settings['bpm'] = state.modes.start.clamp(bpmMin, bpmMax);
    app.audio.ensurePlayback();
    app.audio.setVolumes(sound: state.sound, accentDB: state.accentDB);
    if (interrupted && interruptedBPM != null) settings['bpm'] = interruptedBPM;
    final error = _send('audio.startMetronome', {'settings': settings, 'modes': ?trainingModes});
    if (error != null) {
      show(MetronomeToast(icon: AppIcon.warning, text: 'Метроном не запустился: $error'));
      return;
    }
    _setPlaying(true);
    interrupted = false;
    interruptedBPM = null;
    sessionEnd = null;
    if (!byPlayback) _sessionStartBPM = settings.bpm;
    timerExpired = false;
    targetReached = false;
    startedByPlayback = byPlayback;
    liveBPM = settings.bpm;
    _pending.clear();
    _stopAtNextBar = false;
    _stopAfterSong = false;
    currentBar = 0; // the play-check panel shows «Отсчёт» in bar 0 of every start
    songSection = 0;
    songBar = 0;
    songCountIn = state.modes.tempo == ModeTempo.songMap && state.modes.songCountIn;
    barsSinceTempoChange = 0;
    secondsSinceTempoChange = 0;
    _lastTempoChange = DateTime.now();
    if (state.timerEnabled && !byPlayback) {
      timerEnd = DateTime.now().add(Duration(minutes: state.timerMinutes));
      timerRemaining = state.timerMinutes * 60.0;
    }
    _startLoop();
    // TODO(android): foreground-service notification (iOS Live Activity «Метроном», MetronomeActivityController).
    notifyListeners();
  }

  void stop() {
    _send('audio.stopMetronome');
    _setPlaying(false);
    startedByPlayback = false;
    _setBeat(null);
    flashBeat = null;
    flashOn = false;
    silentBar = false;
    timerEnd = null;
    timerRemaining = null;
    _stopLoop();
    notifyListeners();
    if (!_restarting) app.playCheck.metronomeStopped();
  }

  /// 6.1 п. 6: a call stops the metronome; it waits for «Продолжить» with the same tempo and mode.
  void interrupt() {
    if (!isPlaying) return;
    final live = liveBPM;
    final bar = currentBar + 1;
    stop();
    interrupted = true;
    interruptedBPM = live;
    interruptedBar = bar;
    notifyListeners();
  }

  /// «Ещё 5 мин» of the session-end alert: play on with a 5-minute timer.
  void extendSession({int minutes = 5}) {
    sessionEnd = null;
    start();
    timerEnd = DateTime.now().add(Duration(minutes: minutes));
    timerRemaining = minutes * 60.0;
    notifyListeners();
  }

  void dismissSessionEnd() {
    sessionEnd = null;
    notifyListeners();
  }

  /// Screenshot poses of the canvas boards: «играет», «цель», «прервано звонком», «время вышло».
  void debugPose(String pose) {
    switch (pose) {
      case 'playing' || 'target' || 'landscape':
        _setPlaying(true);
        liveBPM = pose == 'target' ? state.modes.target : (pose == 'landscape' ? 150 : displayBPM);
        targetReached = pose == 'target';
        if (pose == 'target') {
          show(MetronomeToast(icon: AppIcon.check, text: 'Цель ${state.modes.target.toInt()} достигнута — держим темп'),
              duration: const Duration(hours: 1));
        }
      case 'interrupted':
        interrupted = true;
        interruptedBPM = 150;
        interruptedBar = 12;
      case 'timerEnd':
        sessionEnd = SessionEnd(minutes: 20, name: state.currentPreset?.name, startBPM: 142, endBPM: 156);
    }
    notifyListeners();
  }

  void restartIfPlaying() {
    if (!isPlaying) return;
    final byPlayback = startedByPlayback;
    _restarting = true; // a settings change is not the end of a «Проверка игры» attempt
    stop();
    _restarting = false;
    start(byPlayback: byPlayback);
  }

  /// Tempo ± `delta` BPM (knob, ± buttons, keys ← → and ⇧).
  void step(double delta) {
    final value = (displayBPM + delta).clamp(bpmMin, bpmMax);
    if (!isPlaying && state.modes.tempo == ModeTempo.songMap && state.modes.song.isNotEmpty) {
      updateState((s) => s.modes.song[0]['bpm'] = value); // the knob sets the first part's tempo, which is what is shown
      return;
    }
    if (!isPlaying && state.modes.tempo != ModeTempo.none) {
      // Stopped with a tempo mode: the knob and ± set the mode's starting tempo, which is what is shown.
      updateState((s) => s.modes.start = value);
      return;
    }
    bpm = value;
    liveBPM = bpm;
    notifyListeners();
  }

  /// The figure shown on the metronome screen: the chosen one, or the even subdivision as a figure.
  RhythmInfo get currentRhythm {
    final r = meter.rhythm;
    if (r != null) return RhythmLibrary.describe(r);
    return RhythmLibrary.plain(meter.subdivision);
  }

  /// A beat's own figure (Soundbrenner-style: tap a beat); null — back to the common one.
  void setBeatRhythm(RhythmInfo? r, int beat) {
    final m = jsonCopy(meter);
    final own = m.beatRhythms ?? [];
    while (own.length < m.numerator) {
      own.add(null);
    }
    if (beat >= own.length) return;
    own[beat] = r != null && r.span == 1 ? r.json : null;
    m.put('beatRhythms', own.every((e) => e == null) ? null : own);
    meter = m;
  }

  RhythmInfo? beatRhythm(int beat) {
    final own = meter.beatRhythms;
    if (own == null || beat >= own.length || own[beat] == null) return null;
    return RhythmLibrary.describe(own[beat]!);
  }

  /// The ladder's current step while «Лесенка делений» plays.
  int? ladderSubdivision;

  RhythmInfo? get ladderRhythm {
    if (state.modes.subdivision != ModeSubdivision.ladder) return null;
    return RhythmLibrary.plain(isPlaying ? (ladderSubdivision ?? 1) : 1);
  }

  void clearBeatRhythms() => updateMeter((m) => m.remove('beatRhythms'));

  /// Quick note value (Soundbrenner-style grid): even values set the subdivision, figures set the rhythm.
  void setRhythm(RhythmInfo r) {
    final m = jsonCopy(meter);
    if (r.span == 1 && r.isPlain) {
      m.remove('rhythm');
      m['subdivision'] = r.grid.clamp(1, 9);
    } else {
      m['rhythm'] = r.json;
      m['subdivision'] = (r.span == 1 ? r.grid : 1).clamp(1, 9);
    }
    if (!m.isSwingAvailable) m['swing'] = 0.5;
    meter = m;
  }

  void tapTempo() {
    try {
      final r = app.core?.call('metronome.tap', {'time': DateTime.now().microsecondsSinceEpoch / 1e6});
      final value = r is Map ? (r['bpm'] as num?)?.toDouble() : null;
      if (value != null) {
        bpm = value;
        liveBPM = bpm;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Accent cycle on a beat (ME-3): strong → normal → soft → off.
  void cycleAccent(int beat) {
    final a = meter.accents;
    if (beat < 0 || beat >= a.length) return;
    setAccent(beat, Accent.next(a[beat]));
  }

  void setAccent(int beat, int level) {
    final m = jsonCopy(meter);
    final a = m.accents;
    if (beat < 0 || beat >= a.length) return;
    a[beat] = level;
    m['accents'] = a;
    meter = m;
  }

  // MARK: Presets

  void savePreset(String name) {
    final preset = MetronomePreset(name: name, settings: jsonCopy(meter), modes: modes);
    updateState((s) {
      s.presets.add(preset);
      s.currentPresetId = preset.id;
    });
  }

  /// Loads a preset; while playing, from the next bar (6.2.6).
  void load(MetronomePreset preset) {
    app.updateSettings((s) {
      s.metronome.meter = jsonCopy(preset.settings);
      s.metronome.modes = MetronomeModes.fromJson(preset.modes.toJson());
      s.metronome.currentPresetId = preset.id;
    });
    if (isPlaying) _send('audio.updateMetronome', {'settings': preset.settings, 'at': 'nextBar'});
    notifyListeners();
  }

  void renamePreset(String id, String name) {
    if (name.isEmpty || !state.presets.any((p) => p.id == id)) return;
    updateState((s) => s.presets.firstWhere((p) => p.id == id).name = name);
  }

  void deletePreset(String id) => updateState((s) {
    s.presets.removeWhere((p) => p.id == id);
    if (s.currentPresetId == id) s.currentPresetId = null;
  });

  /// «7/8 · 2+2+3 · Разгон», «4/4 · восьмые», «6/8», «4/4 · 16-е».
  String presetSubtitle(MetronomePreset preset) {
    final m = preset.settings;
    final out = <String>['${m.numerator}/${m.denominator}'];
    final grouping = m.grouping;
    if (grouping != null && grouping.length > 1 && grouping.fold<int>(0, (a, b) => a + b) == m.numerator) out.add(grouping.join('+'));
    // The figure, not a plain value (16-16-8 or triplets on a beat were shown as plain sixteenths).
    final figure = m.rhythm == null ? null : RhythmLibrary.describe(m.rhythm!);
    final value = subdivisionName(m);
    if (figure != null && !figure.isPlain) {
      out.add(figure.name);
    } else if (value != null) {
      out.add(value);
    }
    if (m['beatRhythms'] != null) out.add('свои доли');
    out.addAll(preset.modes.activeTitles.take(1));
    return out.join(' · ');
  }

  /// The even subdivision in words: «восьмые», «16-е», «триоли»; null without one.
  static String? subdivisionName(Map<String, dynamic> m) {
    final n = m.subdivision;
    if (n <= 1) return null;
    return switch (n) {
      3 => 'триоли',
      5 => 'квинтоли',
      6 => 'секстоли',
      7 => 'септоли',
      9 => 'по 9',
      _ => m.denominator * n == 8 ? 'восьмые' : '${m.denominator * n}-е',
    };
  }

  /// Deleted presets come back with «Отменить» for 5 s (canvas «Пресеты — свайп»).
  ({MetronomePreset preset, int index, bool wasCurrent})? deletedPreset;
  Timer? _undoTimer;

  void deletePresetUndoable(String id) {
    final i = state.presets.indexWhere((p) => p.id == id);
    if (i < 0) return;
    deletedPreset = (preset: state.presets[i], index: i, wasCurrent: state.currentPresetId == id);
    deletePreset(id);
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 5), () {
      deletedPreset = null;
      notifyListeners();
    });
  }

  void undoDelete() {
    final d = deletedPreset;
    if (d == null) return;
    updateState((s) {
      s.presets.insert(math.min(d.index, s.presets.length), d.preset);
      if (d.wasCurrent) s.currentPresetId = d.preset.id;
    });
    deletedPreset = null;
    _undoTimer?.cancel();
  }

  // MARK: Modes (canvas «Режимы»: one mode at a time)

  ModeChoice get modeChoice {
    final m = state.modes;
    switch (m.tempo) {
      case ModeTempo.speedUp:
        return ModeChoice.speedUp;
      case ModeTempo.twoForward:
        return ModeChoice.twoForward;
      case ModeTempo.fastSlow:
        return ModeChoice.fastSlow;
      case ModeTempo.songMap:
        return ModeChoice.songMap;
      case ModeTempo.none:
        break;
    }
    switch (m.sound) {
      case ModeSound.gapBars:
        return ModeChoice.gapBars;
      case ModeSound.randomMute:
        return ModeChoice.randomMute;
      case ModeSound.displaced:
        return ModeChoice.displaced;
      case ModeSound.none:
        break;
    }
    return m.subdivision == ModeSubdivision.ladder ? ModeChoice.ladder : ModeChoice.normal;
  }

  /// Chooses one mode and switches the others off.
  void choose(ModeChoice choice) => updateModes((m) {
    m
      ..tempo = ModeTempo.none
      ..sound = ModeSound.none
      ..subdivision = ModeSubdivision.none;
    switch (choice) {
      case ModeChoice.normal:
        break;
      case ModeChoice.speedUp:
        m.tempo = ModeTempo.speedUp;
      case ModeChoice.twoForward:
        m.tempo = ModeTempo.twoForward;
      case ModeChoice.fastSlow:
        m.tempo = ModeTempo.fastSlow;
      case ModeChoice.songMap:
        m.tempo = ModeTempo.songMap;
      case ModeChoice.gapBars:
        m.sound = ModeSound.gapBars;
      case ModeChoice.randomMute:
        m.sound = ModeSound.randomMute;
      case ModeChoice.displaced:
        m.sound = ModeSound.displaced;
      case ModeChoice.ladder:
        m.subdivision = ModeSubdivision.ladder;
    }
  });

  // MARK: Toast

  void show(MetronomeToast t, {Duration duration = const Duration(milliseconds: 3400)}) {
    toast = t;
    _toastTimer?.cancel();
    _toastTimer = Timer(duration, () {
      toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Hides the toast at once (tests, poses).
  void clearToast() {
    _toastTimer?.cancel();
    toast = null;
    notifyListeners();
  }

  // MARK: Timeline

  /// Calls an engine command; returns an error text when the core refused (not when there is no audio host).
  String? _send(String method, [Map<String, dynamic>? params]) {
    final audio = app.audio;
    if (audio.core == null || !audio.available) return null;
    try {
      audio.core!.call(method, params);
      return null;
    } catch (e) {
      final text = '$e';
      if (text.contains('not available')) {
        audio.available = false;
        return null;
      }
      return text.replaceFirst('TruverCore: ', '');
    }
  }

  void _setPlaying(bool value) {
    if (value == _isPlaying) return;
    _isPlaying = value;
    app.changed(); // the tab bar dot
  }

  void _setBeat(int? beat) {
    final wasFirst = _currentBeat == 0;
    _currentBeat = beat;
    if (wasFirst != (beat == 0)) app.changed(); // the tab bar dot: bright on the first beat
  }

  void _startLoop() {
    _lastActivity = DateTime.now();
    if (_listening) return;
    _listening = true;
    app.audio.addPollListener(_poll);
  }

  void _stopLoop() {
    if (!_listening) return;
    _listening = false;
    app.audio.removePollListener(_poll);
  }

  List<Object?> get _signature => [
    _currentBeat,
    currentBar,
    flashBeat,
    flashOn,
    silentBar,
    liveBPM,
    timerRemaining?.ceil(),
    timerExpired,
    targetReached,
    songSection,
    songBar,
    songCountIn,
    ladderSubdivision,
    secondsSinceTempoChange.ceil(),
    barsSinceTempoChange,
  ];

  void _poll(AudioPoll poll) {
    if (!isPlaying) return;
    final before = _signature;
    for (final t in (poll['ticks'] as List? ?? const [])) {
      _pending.add(Map<String, dynamic>.from(t as Map));
    }
    final now = (poll['now'] as num?)?.toInt() ?? 0;
    final settings = _meterForFlash;
    final rule = _rule(settings); // ≤ 3 flashes/s on the strip and on the full screen (6.1 п. 9)
    final accents = settings.accents;
    while (_pending.isNotEmpty && (_pending.first['hostNanos'] as num).toInt() <= now) {
      final tick = _pending.removeAt(0);
      if (tick['track'] == 0) app.playCheck.expect(tick); // SM-2: every main-track tick is an expected note
      if (tick['tick'] != 0 || tick['track'] != 0) continue; // the ME-8 second track neither flashes nor counts
      final beat = (tick['beat'] as num).toInt(), bar = (tick['bar'] as num).toInt();
      if (_stopAfterSong && beat == 0) {
        stop();
        return;
      }
      if (_stopAtNextBar && beat == 0) {
        final end = liveBPM ?? bpm;
        stop();
        timerExpired = true;
        sessionEnd = SessionEnd(
          minutes: state.timerMinutes,
          name: state.currentPreset?.name,
          startBPM: _sessionStartBPM ?? end,
          endBPM: end,
        );
        notifyListeners();
        return;
      }
      if (beat == 0 && bar != currentBar) {
        barsSinceTempoChange += 1;
        songBar += 1;
      }
      _setBeat(beat);
      currentBar = bar;
      // A rest of the rhythmic figure is not a silent bar (the screen said «Тихий такт» on off-beat figures).
      silentBar = tick['silent'] == true && tick['rest'] != true;
      liveBPM = (tick['bpm'] as num).toDouble();
      if (state.flash != FlashTarget.off && flashes(tick, rule, accents)) _flash(beat);
      final level = (tick['level'] as num).toInt();
      // «Вибрация на сильной доле».
      if (app.settings.vibration && tick['silent'] != true && level == Accent.strong) HapticFeedback.heavyImpact();
    }
    app.playCheck.update();
    if (DateTime.now().difference(_lastActivity) >= const Duration(seconds: 1)) {
      _lastActivity = DateTime.now();
      app.practice.activity(tuned: false, bpm: liveBPM);
    }
    secondsSinceTempoChange = DateTime.now().difference(_lastTempoChange).inMicroseconds / 1e6;
    for (final n in (poll['notices'] as List? ?? const [])) {
      final notice = Map<String, dynamic>.from(n as Map);
      final value = (notice['value'] as num?)?.toDouble();
      switch (notice['kind']) {
        case 'tempoChanged':
          liveBPM = value;
          barsSinceTempoChange = 0;
          _lastTempoChange = DateTime.now();
        case 'targetReached':
          targetReached = true;
          _send('audio.event', {'sound': 'targetReached'}); // SND-3
          show(MetronomeToast(icon: AppIcon.check, text: 'Цель ${state.modes.target.toInt()} достигнута — держим темп'));
        case 'subdivisionChanged':
          ladderSubdivision = value?.toInt();
        case 'sectionChanged':
          final index = value?.toInt() ?? 0;
          songSection = index;
          songBar = -1; // the downbeat that follows is bar 1 of the part
          songCountIn = false;
          final song = state.modes.song;
          if (index >= 0 && index < song.length) {
            final part = song[index];
            show(
              MetronomeToast(
                icon: AppIcon.music,
                text: '${part['name']} · ${(part['bpm'] as num).toInt()} · ${part['numerator']}/${part['denominator']}',
              ),
            );
          }
        case 'songEnded':
          _stopAfterSong = true;
          show(const MetronomeToast(icon: AppIcon.check, text: 'Песня сыграна'));
        default:
          break;
      }
    }
    final end = timerEnd;
    if (end != null) {
      final remaining = end.difference(DateTime.now()).inMicroseconds / 1e6;
      timerRemaining = remaining < 0 ? 0 : remaining;
      // 6.1 п. 10: the timer expires — the metronome finishes the bar and stops.
      if (remaining <= 0 && !_stopAtNextBar) {
        _stopAtNextBar = true;
        _send('audio.event', {'sound': 'timerEnded'}); // SND-3
      }
    }
    if (!listEquals(before, _signature)) notifyListeners();
  }

  /// Flash: lit at once, fades out (canvas `beatseq`: on for 10 %, gone by 22 % of the beat).
  void _flash(int beat) {
    flashBeat = beat;
    flashOn = true;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 60), () {
      flashOn = false;
      notifyListeners();
    });
  }

  /// Test hook: the playing look at a given beat with its flash lit (no audio host in widget tests).
  @visibleForTesting
  void debugShowBeat(int beat, {bool flash = true}) {
    _setPlaying(true);
    _setBeat(beat);
    currentBar = 1;
    flashBeat = flash ? beat : null;
    flashOn = flash;
    notifyListeners();
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _toastTimer?.cancel();
    _flashTimer?.cancel();
    _stopLoop();
    super.dispose();
  }
}

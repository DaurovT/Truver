/// Port of Truver/Sources/Features/Tuner/TunerScreen.swift
///
/// Tuner (canvas «Тюнер», 6.2.4; corrected «Fix…» boards of 2026-11-25): header, dial with the needle on the
/// scale, status line (or the state's action / strobe strips), large string keys with the octave inline (or the
/// chromatic note strip), mode segments with the reference tone and «Ещё» (strobe, stage, noise gate); the
/// large-text and landscape boards, the route notices, the «Ещё» sheet, the stage mode (TU-12) and the TalkBack
/// semantics of the dial.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../app/app_model.dart';
import '../../app/audio_services.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/landscape.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import '../root/root_view.dart' show isAccessibilityTextSize;
import 'tuner_controller.dart';
import 'tuner_demo.dart';
import 'tuner_dial.dart';
import '../tour/coach_marks.dart';

/// Everything the tuner views derive from the controller (the computed properties of `TunerScreen.swift`), shared
/// by the portrait, large-text and landscape boards and the stage cover.
class TunerPresenter {
  TunerPresenter(this.app);
  final AppModel app;

  TunerController get tuner => app.tuner;
  TunerDemo? get demo => tuner.demo;

  bool get showsDone => demo?.done ?? (tuner.allTuned && tuner.display.kind == TunerDisplayKind.idle);

  bool get micBlocked => tuner.permission == MicPermission.denied || tuner.permission == MicPermission.restricted;
  bool get micUnavailable {
    final d = demo;
    if (d != null) return d.action != null;
    return micBlocked || tuner.needsMicrophoneButton || tuner.error != null;
  }

  TunerReading? get reading => tuner.display.kind == TunerDisplayKind.reading ? tuner.display.reading : null;

  bool get hasReading {
    final d = demo;
    if (d != null) return d.cents != null;
    return reading != null && !tuner.isReferencePlaying;
  }

  /// TU-10: the strobe view replaces the needle by strips under the dial.
  bool get strobeOn => demo?.strobe ?? tuner.strobeView;

  bool get frozen => demo != null;

  /// Deviation shown by the needle (and the stage marker): a string or a chromatic-mode note.
  double? get needleCents {
    final d = demo;
    if (d != null) return d.cents;
    final r = reading;
    if (r == null || tuner.isReferencePlaying || micUnavailable) return null;
    if (!r.target.isString && tuner.mode != TunerMode.chromatic) return null;
    return r.target.deviationCents.clamp(-50.0, 50.0).toDouble();
  }

  /// Colour of the needle and the strobe band; null — the idle band.
  Color? get dialColor {
    final d = demo;
    if (d != null) return d.color;
    if (showsDone) return TruverColors.inTune;
    final r = reading;
    if (needleCents == null || r == null) return null;
    return TruverColors.deviation(r.target.deviationCents, inTune: r.isInTune);
  }

  /// Strobe band speed: only while a reading is not in tune.
  double? get bandCents {
    if (demo != null) return null;
    final c = needleCents, r = reading;
    if (c == null || r == null || r.isInTune) return null;
    return c;
  }

  /// The canvas render: 0.05 s into the 3 s countdown.
  double? get referenceProgress => demo == null ? null : (demo!.center is DialReference ? 1 - 0.05 / 3 : null);

  DateTime? get countdownUntil => demo == null && tuner.isReferencePlaying ? tuner.referenceUntil : null;

  DialCenter get dialCenter {
    final d = demo;
    if (d != null) return d.center;
    if (tuner.permission == MicPermission.restricted) {
      return const DialMessage(
        icon: AppIcon.lock,
        iconColor: TruverColors.textSecondary,
        title: 'Доступ ограничен',
        detail: 'Микрофон запрещён профилем или родительским контролем',
      );
    }
    if (tuner.permission == MicPermission.denied) {
      return const DialMessage(
        icon: AppIcon.micOff,
        iconColor: TruverColors.sharp,
        title: 'Нужен микрофон',
        detail: 'Тюнер слышит струну. Звук не записывается',
      );
    }
    if (tuner.needsMicrophoneButton) {
      return const DialMessage(icon: AppIcon.micOff, iconColor: TruverColors.textSecondary, title: 'Микрофон выключен', detail: 'Сейчас играет метроном');
    }
    if (tuner.error != null) {
      return const DialMessage(
        icon: AppIcon.warning,
        iconColor: TruverColors.sharp,
        title: 'Звук недоступен',
        detail: 'Микрофон занят другим приложением или звонком',
      );
    }
    final ref = tuner.referenceString;
    if (tuner.isReferencePlaying && ref != null) {
      return DialReference(title: 'Эталон ${tuner.stringName(ref)}', detail: '${hz(tuner.openFrequency(ref))} Гц · анализ на паузе');
    }
    if (showsDone) {
      final total = tuner.courses.length;
      return DialDone(detail: '$total из $total струн в строю');
    }
    switch (tuner.display.kind) {
      case TunerDisplayKind.listening:
        return const DialListening();
      case TunerDisplayKind.outOfRange:
        return const DialMessage(
          icon: AppIcon.warning,
          iconColor: TruverColors.textBody,
          title: 'Вне диапазона',
          detail: 'Ниже 25 Гц или выше последнего лада',
        );
      case TunerDisplayKind.idle:
        final last = tuner.lastReading;
        if (last != null) {
          final (name, octave) = noteParts(last);
          return DialNote(name: name, octave: octave, cents: '', centsColor: const Color(0x00000000), detail: '', dimmed: true);
        }
        // Canvas «Ожидание»: the first string still to tune, dimmed, with «начните с 6-й струны».
        final courses = tuner.courses;
        var course = 0;
        while (course < courses.length && tuner.tuned.contains(StringRef(course))) {
          course++;
        }
        if (course >= courses.length) course = 0;
        final c = courses.isEmpty ? null : courses[course];
        final detail = tuner.mode == TunerMode.chromatic ? '' : 'начните с ${courses.length - course}-й струны';
        return DialNote(name: c?.name ?? 'E', octave: '${c?.octave ?? 2}', cents: '', centsColor: const Color(0x00000000), detail: detail, dimmed: true);
      case TunerDisplayKind.reading:
        final r = tuner.display.reading!;
        final (name, octave) = noteParts(r);
        final t = r.target;
        final deviation = t.deviationCents;
        if (strobeOn && deviation.abs() < 100) {
          final line = r.isInTune ? 'полосы почти стоят' : (deviation < 0 ? 'ниже — подтяните' : 'выше — ослабьте');
          return DialStrobeNote(
            name: name,
            octave: octave,
            line: '${centsText(deviation)} · $line',
            color: TruverColors.deviation(deviation, inTune: r.isInTune),
          );
        }
        if (t.isString && t.string != null) {
          final ref = t.string!;
          final color = TruverColors.deviation(deviation, inTune: r.isInTune);
          if (deviation.abs() >= 100) {
            // Manual mode far from the target: the dial keeps the target, the line names the note played.
            return DialNote(name: name, octave: octave, cents: tones(deviation), centsColor: color, detail: 'сейчас ${r.pitch.label} · ${hz(r.frequency)} Гц');
          }
          final strings = _stringsIn(ref.course);
          final detail = strings > 1
              ? '${hz(r.frequency)} Гц · струна ${ref.string + 1} из $strings'
              : '${hz(r.frequency)} Гц · цель ${hz(t.target.frequency(app.a4))}';
          return DialNote(name: name, octave: octave, cents: centsText(deviation), centsColor: color, detail: detail);
        }
        if (tuner.mode == TunerMode.chromatic) {
          return DialNote(
            name: name,
            octave: octave,
            cents: centsText(deviation),
            centsColor: TruverColors.deviation(deviation, inTune: r.isInTune),
            detail: '${hz(r.frequency)} Гц',
          );
        }
        final hint = t.hintTarget;
        final detail = hint != null ? 'ближайшая ${hint.label} · ${signed((t.hintDeviation ?? 0).round())} ц' : '${hz(r.frequency)} Гц';
        return DialNote(name: name, octave: octave, cents: 'вне строя', centsColor: TruverColors.textSecondary, detail: detail);
    }
  }

  Color get statusColor => demo?.statusColor ?? _statusPair.$2;

  String get statusText => demo?.status ?? _statusPair.$1;

  (String, Color) get _statusPair {
    if (micUnavailable) return ('', TruverColors.textBody);
    if (tuner.isReferencePlaying) return ('Звучит эталон · ${math.max(1, tuner.referenceSecondsLeft)} с', TruverColors.textBody);
    if (showsDone) return ('Все струны в строю', TruverColors.inTune);
    switch (tuner.display.kind) {
      case TunerDisplayKind.idle:
        return (tuner.mode == TunerMode.chromatic ? 'Сыграйте ноту' : 'Сыграйте струну', TruverColors.textBody);
      case TunerDisplayKind.listening:
        return ('Дайте струне прозвучать', TruverColors.textBody);
      case TunerDisplayKind.outOfRange:
        return ('Сыграйте открытую струну', TruverColors.textBody);
      case TunerDisplayKind.reading:
        if (strobeOn) return ('', TruverColors.textBody);
        final r = tuner.display.reading!;
        final t = r.target;
        if (t.isString && t.string != null) {
          final ref = t.string!;
          final deviation = t.deviationCents;
          final paired = _stringsIn(ref.course) > 1;
          final number = tuner.courses.length - ref.course;
          if (r.isInTune) {
            if (paired) return ('Курс ${ref.course + 1} в строю', TruverColors.inTune);
            // Canvas «Ручной»: the mode explains itself once the string is in tune.
            if (tuner.mode.kind == TunerModeKind.manual) {
              return ('Ручной: только ${tuner.stringName(ref)} — другие ноты не мешают', TruverColors.inTune);
            }
            return ('В строю', TruverColors.inTune);
          }
          if (deviation.abs() >= 100) {
            final verb = deviation < 0 ? 'подтяните' : 'ослабьте';
            return ('Струна $number · $verb на ${tones(deviation).substring(1)}', TruverColors.deviation(deviation));
          }
          return deviation < 0 ? ('Ниже — подтяните', TruverColors.flat) : ('Выше — ослабьте', TruverColors.sharp);
        }
        return tuner.mode == TunerMode.chromatic
            ? ('Хроматический: любая нота, не только струны строя', TruverColors.textBody)
            : ('Нота не из этого строя', TruverColors.textBody);
    }
  }

  // MARK: Chromatic strip (canvas «Тюнер — хроматический»)

  bool get showsChromaticStrip => (demo?.choice ?? tuner.choice) == TunerChoice.chromatic;

  static int _pitchClass(double cents) => (((cents / 100).round() + 9) % 12 + 12) % 12;

  /// Pitch class of the note in the middle of the strip.
  int get chromaticCurrent {
    final pc = demo?.chromaticPitchClass;
    if (pc != null) return pc;
    final r = reading ?? tuner.lastReading;
    if (r != null && !r.target.isString) return _pitchClass(r.target.target.cents);
    return 9;
  }

  bool get chromaticHighlighted => demo != null || reading != null;

  /// Note name of a pitch class in the tuning's notation and accidentals (the core names it; the octave is cut).
  String pitchClassName(int pc) => app.chromaticName((pc - 9) * 100.0).replaceAll(RegExp(r'-?\d+$'), '');

  // MARK: Actions

  (String, AppIcon?, double, VoidCallback)? get stateAction {
    final d = demo;
    if (d != null) return d.action == null ? null : (d.action!.title, null, d.action!.width, () {});
    if (tuner.permission == MicPermission.restricted) return null;
    if (tuner.permission == MicPermission.denied) return ('Разрешить микрофон', null, 250, openAppSettings);
    if (tuner.needsMicrophoneButton) return ('Включить микрофон', AppIcon.mic, 250, () => tuner.start(confirmedGap: true));
    if (tuner.error != null) {
      return (
        'Повторить',
        null,
        200,
        () {
          tuner.error = null;
          tuner.start(confirmedGap: true);
        },
      );
    }
    return null;
  }

  // MARK: VoiceOver (canvas «Тюнер — VoiceOver», 6.1 п. 15)

  /// «A2, ниже на 14 центов» / «A2, в строю» / «Сыграйте струну».
  String get voiceValue {
    final r = reading;
    if (r == null || micUnavailable) return statusText.isEmpty ? 'Нет показаний' : statusText;
    final (name, octave) = noteParts(r);
    final note = name.replaceAll('♯', ' диез').replaceAll('♭', ' бемоль') + octave;
    if (r.isInTune) return '$note, в строю';
    final c = r.target.deviationCents.abs().round();
    final word = c % 10 == 1 && c % 100 != 11 ? 'цент' : ((c % 10 >= 2 && c % 10 <= 4) && !(c % 100 >= 12 && c % 100 <= 14) ? 'цента' : 'центов');
    return '$note, ${r.target.deviationCents < 0 ? 'ниже' : 'выше'} на $c $word';
  }

  bool get voiceInTune => demo?.inTune ?? reading?.isInTune ?? false;
  double? get voiceCents => reading?.target.deviationCents;

  /// The dial without the Hz line (it moves under the status in large text): «109,1 Гц · цель 110».
  (DialCenter, String) get largeCenter {
    final c = dialCenter;
    if (c is DialNote) {
      final detail = c.detail.replaceAllMapped(RegExp(r'(\d),0(?!\d)'), (m) => m.group(1)!);
      return (DialNote(name: c.name, octave: c.octave, cents: c.cents, centsColor: c.centsColor, detail: '', dimmed: c.dimmed), detail);
    }
    return (c, '');
  }

  // MARK: Formatting

  (String, String) noteParts(TunerReading r) => (r.target.target.name, '${r.target.target.octave}');

  int _stringsIn(int course) {
    final c = tuner.courses;
    return course >= 0 && course < c.length ? c[course].strings.length : 1;
  }

  /// Decimal comma (canvas «109,1 Гц · цель 110,0»).
  static String hz(double f) => (f < 100 ? f.toStringAsFixed(2) : f.toStringAsFixed(1)).replaceAll('.', ',');

  static String signed(int v) => v > 0 ? '+$v' : (v < 0 ? '−${-v}' : '0');

  /// Whole cents (motion spec: rounded to 1 c).
  String centsText(double cents) {
    // TU-10: in the strobe view a steady note reads to a tenth of a cent from the phase.
    final s = tuner.strobe;
    if (tuner.strobeView && s != null && s.isStable && s.cents.abs() < 50) {
      final v = (s.cents * 10).round() / 10;
      final text = v.abs().toStringAsFixed(1).replaceAll('.', ',');
      return '${v > 0 ? '+' : (v < 0 ? '−' : '')}$text ц';
    }
    return '${signed(cents.round())} ц';
  }

  /// Large manual deviations in tones: «−2 тона», «−полтона», «+1,5 тона».
  static String tones(double cents) {
    final halfTones = (cents.abs() / 100).round();
    final sign = cents < 0 ? '−' : '+';
    if (halfTones == 1) return '$signполтона';
    if (halfTones % 2 == 0) {
      final t = halfTones ~/ 2;
      final word = t % 10 == 1 && t % 100 != 11 ? 'тон' : ((t % 10 >= 2 && t % 10 <= 4) && !(t % 100 >= 12 && t % 100 <= 14) ? 'тона' : 'тонов');
      return '$sign$t $word';
    }
    return '$sign${(halfTones / 2).toStringAsFixed(1).replaceAll('.', ',')} тона';
  }

  /// «Микрофон» for the built-in microphone, otherwise the interface's name.
  /// TODO(android): name the routed input (AudioDeviceInfo.getProductName) once the host reports routes.
  String get inputName => demo?.input ?? 'Микрофон';

  /// Canvas «Вход переключён»: the chip shows the interface's first word («Focusrite»).
  String get chipInputName {
    final name = inputName;
    if (name == 'Микрофон' || name.length <= 10) return name;
    return name.split(' ').first;
  }

  AppIcon get inputIcon => inputName == 'Микрофон' ? AppIcon.mic : AppIcon.audioInterface;

  String keyLabel(int course) {
    final c = tuner.courses[course];
    return '${c.short}${c.octave}';
  }

  bool isSelected(StringRef ref) {
    final d = demo;
    if (d != null) return d.selected != null && d.selected == keyLabel(ref.course);
    final m = tuner.mode;
    if (m.kind == TunerModeKind.manual) return m.ref!.course == ref.course;
    final refString = tuner.referenceString;
    if (tuner.isReferencePlaying && refString != null) return refString.course == ref.course;
    final r = reading;
    if (r != null && r.target.isString && r.target.string != null) return r.target.string!.course == ref.course;
    return m == TunerMode.auto && tuner.lastString?.course == ref.course;
  }

  StringStatus mark(StringRef ref) {
    final d = demo;
    if (d != null) return isSelected(ref) ? d.selectedMark : d.mark(ref.course);
    return tuner.stringStatus[ref] ?? (tuner.tuned.contains(ref) ? StringStatus.inTune : StringStatus.unknown);
  }

  static Color markColor(StringStatus status) => switch (status) {
    StringStatus.inTune => TruverColors.inTune,
    StringStatus.flat => TruverColors.flat,
    StringStatus.sharp => TruverColors.sharp,
    StringStatus.unknown => TruverColors.neutralMark,
  };

  String accessibilityStatus(StringRef ref) => switch (tuner.stringStatus[ref] ?? StringStatus.unknown) {
    StringStatus.inTune => 'в строю',
    StringStatus.flat => 'ниже',
    StringStatus.sharp => 'выше',
    StringStatus.unknown => '',
  };

  /// What swiping up / down would select (TalkBack reads it with the adjustable action).
  String adjacentString(bool up) {
    final n = tuner.courses.length;
    if (n == 0) return '';
    final current = tuner.mode.ref?.course ?? tuner.lastString?.course ?? 0;
    return 'Струна ${tuner.stringName(StringRef(math.min(n - 1, math.max(0, current + (up ? 1 : -1)))))}';
  }

  /// Swipe up / down on the dial: the next / previous string in manual mode.
  void stepString(bool up) {
    final n = tuner.courses.length;
    if (n == 0) return;
    final current = tuner.mode.ref?.course ?? tuner.lastString?.course ?? 0;
    final next = math.min(n - 1, math.max(0, current + (up ? 1 : -1)));
    tuner.mode = TunerMode.manual(StringRef(next));
  }

  Widget dial({DialCenter? center}) => TunerDial(
    center: center ?? dialCenter,
    needle: strobeOn ? null : needleCents,
    color: dialColor,
    bandCents: bandCents,
    glow: showsDone,
    phase: tuner.strobe?.angle,
    strobeView: strobeOn,
    progress: referenceProgress,
    countdownUntil: countdownUntil,
    frozen: frozen,
    // The canvas renders of sheet boards catch the band at another moment — a whole dash period away (0).
    bandAngle: app.sheet == null ? (demo?.bandAngle ?? 0) : 0,
  );

  Widget voiceOver(Widget child) => TunerVoiceOver(
    value: voiceValue,
    inTune: voiceInTune,
    cents: voiceCents,
    adjust: stepString,
    increased: adjacentString(true),
    decreased: adjacentString(false),
    child: child,
  );
}

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  static bool _stageArgHandled = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    if (app.args.has('-tunerStage') && !_stageArgHandled) {
      _stageArgHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openTunerStage(context, animated: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = TunerPresenter(app);
    final landscape = isPhoneLandscape(context);
    final large = app.args.has('-tunerLarge') || isAccessibilityTextSize(context);
    final Widget body = landscape ? _TunerLandscape(p: p) : (large ? _TunerLargeText(p: p) : _TunerPortrait(p: p));
    final notice = p.demo?.notice ?? p.tuner.notice;
    // The canvas sets `font-variant-numeric: tabular-nums` on the whole board (iOS `.monospacedDigit()`).
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: body),
          if (!landscape && notice != null)
            Positioned(
              left: 0,
              right: 0,
              // Canvas: 104 from the top of the board, the safe area (47) included.
              top: 57,
              child: TunerNoticeView(notice: notice, dismiss: () => p.tuner.notice = null, speaker: p.tuner.routeToSpeaker),
            ),
        ],
      ),
    );
  }
}

/// iOS `.debug` resets the static flag between tests.
@visibleForTesting
void resetTunerStageArg() => _TunerScreenState._stageArgHandled = false;

// MARK: Portrait

class _TunerPortrait extends StatelessWidget {
  const _TunerPortrait({required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    final app = p.app;
    final twoRows = StringGrid.rows(p.tuner.courses.length) > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(title: 'Тюнер', leading: _a4Chip(app), trailing: [_inputChip(context, p)]),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Canvas rows below the header (94): dial +12, status +350, strings +406, modes +490; 8–9 strings in two
              // rows: strings +398, modes +538. The dial takes what is left, at most 320 as on 390 × 844.
              final fixed = twoRows ? 12.0 + 66 + 122 + 18 + 44 : 12.0 + 74 + 58 + 26 + 44;
              final dial = math.max(180.0, math.min(320.0, math.min(constraints.maxWidth - 70, constraints.maxHeight - fixed)));
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(width: dial, height: dial, child: p.voiceOver(p.dial())),
                      SizedBox(
                        width: constraints.maxWidth,
                        height: twoRows ? 66 : 74,
                        child: _MiddleRow(p: p),
                      ),
                      SizedBox(
                        width: constraints.maxWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: p.showsChromaticStrip ? ChromaticStrip(p: p) : CoachAnchor(id: CoachAnchors.tunerStrings, child: StringGrid(p: p)),
                        ),
                      ),
                      SizedBox(height: twoRows ? 18 : 26),
                      SizedBox(
                        width: constraints.maxWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _ModeRow(p: p),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Widget? _a4Chip(AppModel app) => (app.a4 - 440).abs() > 0.01 ? HeaderChip(text: 'A4 · ${app.a4.toInt()} Гц', tint: TruverColors.sharp) : null;

Widget _inputChip(BuildContext context, TunerPresenter p) => Pressable(
  scale: 1,
  label: 'Вход: ${p.inputName}',
  onTap: () => p.app.showSettings = true,
  child: HeaderChip(text: p.chipInputName, icon: p.inputIcon),
);

/// Between the dial and the strings (canvas: dial bottom + 12 … + 74): the status line at +18 (a 24 pt box, the
/// 17 pt line at its top, a long hint runs onto a second line), the state's action at +12 or the strobe strips
/// at +16.
class _MiddleRow extends StatelessWidget {
  const _MiddleRow({required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    if (p.micUnavailable) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.topCenter,
          child: _ActionView(p: p),
        ),
      );
    }
    if (p.strobeOn && p.hasReading) {
      return Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 16),
        child: Align(
          alignment: Alignment.topCenter,
          child: StrobeStrips(phase: p.frozen ? 0 : (p.tuner.strobe?.angle ?? 0)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 18),
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: _StatusText(text: p.statusText, color: p.statusColor, style: Typo.status, maxLines: 2),
      ),
    );
  }
}

/// The status line: colour fades with `Motion.quick`.
class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, required this.color, required this.style, this.maxLines = 1, this.align = TextAlign.center});
  final String text;
  final Color color;
  final TextStyle style;
  final int maxLines;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: color),
    duration: Motion.quick,
    curve: Motion.out,
    builder: (context, c, _) => SwiftText(
      text,
      maxLines: maxLines,
      textAlign: align,
      style: style.copyWith(color: c),
    ),
  );
}

/// Canvas «Нет доступа» / «Звук недоступен»: a 46 pt ivory button (250 / 200 wide) 12 pt under the dial.
class _ActionView extends StatelessWidget {
  const _ActionView({required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    if (p.demo == null && p.tuner.permission == MicPermission.restricted) {
      // Nothing the user can do here (canvas «доступ ограничен»): only an explanation, no button.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: SwiftText(
          'Изменить доступ может только администратор устройства. Метроном и гриф работают',
          textAlign: TextAlign.center,
          style: Typo.caption.copyWith(color: TruverColors.textTertiary),
        ),
      );
    }
    final action = p.stateAction;
    if (action == null) return const SizedBox.shrink();
    return SizedBox(
      width: action.$3,
      child: PrimaryButton(title: action.$1, icon: action.$2, height: 46, maxWidth: action.$3, onTap: action.$4),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    final tuner = p.tuner;
    return Row(
      children: [
        Expanded(
          child: SegmentedPill<TunerChoice>(
            options: const [(TunerChoice.auto, 'Авто'), (TunerChoice.manual, 'Ручной'), (TunerChoice.chromatic, 'Хром.')],
            selection: p.demo?.choice ?? tuner.choice,
            onChanged: (c) => tuner.choice = c,
          ),
        ),
        const SizedBox(width: 10),
        CoachAnchor(
          id: CoachAnchors.tunerReference,
          child: RoundIconButton(icon: AppIcon.waveform, size: 44, iconSize: 20, label: 'Эталонный тон', onTap: () => tuner.playReference(tuner.referenceTarget)),
        ),
        const SizedBox(width: 10),
        CoachAnchor(
          id: CoachAnchors.tunerMore,
          child: Pressable(
            label: 'Ещё: строб, сцена, порог шума',
            onTap: () => p.app.sheet = const AppSheet('tunerPro'),
            child: const RoundButtonFace(size: 44, child: Center(child: MoreIcon())),
          ),
        ),
      ],
    );
  }
}

/// «Ещё»: three lines with a ring on the top one (canvas icon, 18 pt), the ring filled with the background.
class MoreIcon extends StatelessWidget {
  const MoreIcon({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const AppIconView(AppIcon.list, size: 18, color: TruverColors.textBody),
          // Circle (9, 7) r 2 of the 24 grid at 18 pt: centre (6.75, 5.25), radius 1.5.
          Positioned(
            left: 6.75 - 1.5,
            top: 5.25 - 1.5,
            width: 3,
            height: 3,
            child: ShapeBox(
              shape: SwiftShape.circle,
              fills: const [SwiftFill(TruverColors.background)],
              strokes: const [SwiftStroke(TruverColors.textBody, width: 1.2)],
            ),
          ),
        ],
      ),
    ),
  );
}

/// String keys in physical order (canvas: 58 pt keys, radius 12, gap 6; the note with its octave inline, 17 pt —
/// medium and ivory when selected; a 14 × 3 status mark 8 pt under it that glows when it is the key's colour).
/// Up to seven in one row, 8–9 in two.
class StringGrid extends StatelessWidget {
  const StringGrid({super.key, required this.p});
  final TunerPresenter p;

  static int rows(int count) => count > 7 ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    final courses = p.tuner.courses.length;
    final n = rows(courses);
    final columns = n > 1 ? (courses + 1) ~/ 2 : courses;
    final disabled = p.demo == null && p.micUnavailable;
    return IgnorePointer(
      ignoring: disabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < n; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < columns; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: row * columns + i < courses ? _key(row * columns + i) : const SizedBox(height: 58)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _key(int course) {
    final ref = StringRef(course);
    final selected = p.isSelected(ref);
    final color = TunerPresenter.markColor(p.mark(ref));
    final status = p.accessibilityStatus(ref);
    final glow = selected && color != TruverColors.neutralMark;
    return Pressable(
      label: 'Струна ${p.tuner.stringName(ref)}${status.isEmpty ? '' : ', $status'}',
      selected: selected,
      onTap: () => p.tuner.tapString(ref),
      child: SizedBox(
        height: 58,
        child: ShapeBox(
          shape: const SwiftShape.rounded(12, continuous: true),
          fills: [SwiftFill.gradient(selected ? TruverGradients.keyFillSelected : TruverGradients.keyFill)],
          strokes: [SwiftStroke(selected ? TruverColors.selectedBorder : TruverColors.hairline, inside: true)],
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: swiftNotes(
                    p.keyLabel(course),
                    Typo.inter(17, selected ? TypoWeight.medium : TypoWeight.regular, selected ? TruverColors.textPrimary : TruverColors.textMuted),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 14,
                  height: 3,
                  child: ShapeBox(shape: const SwiftShape.rounded(2), shadows: [if (glow) SwiftShadow(color, 3)], fills: [SwiftFill(color)]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chromatic mode (canvas «Тюнер — хроматический»): instead of the strings, nine note names around the one heard —
/// 26 pt columns spread over the row, bottoms on one line; the heard note 22 semibold ivory, the others 13 tertiary.
class ChromaticStrip extends StatelessWidget {
  const ChromaticStrip({super.key, required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    final current = p.chromaticCurrent;
    final highlighted = p.chromaticHighlighted;
    return Semantics(
      label: 'Хроматический режим',
      excludeSemantics: true,
      child: SizedBox(
        height: 58,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var offset = -4; offset <= 4; offset++)
              SizedBox(
                width: 26,
                child: OverflowBox(
                  maxWidth: double.infinity,
                  fit: OverflowBoxFit.deferToChild,
                  child: swiftNotes(
                    p.pitchClassName(((current + offset) % 12 + 12) % 12),
                    offset == 0 && highlighted
                        ? Typo.inter(22, TypoWeight.semibold, TruverColors.textPrimary)
                        : Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// MARK: Large text (canvas «Тюнер — крупный шрифт», FixTunerLarge)

/// Fixed sizes (the layout is already the large one): header 28 pt with two 48 pt buttons (input, settings), dial
/// 320 × 0.875, status 28 semibold with «109,1 Гц · цель 110» 18 pt under it, strings three in a row (74 pt, 28
/// semibold with a 16 pt octave), modes 46 pt at 19 semibold.
class _TunerLargeText extends StatelessWidget {
  const _TunerLargeText({required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    final app = p.app;
    final tuner = p.tuner;
    final (center, detail) = p.largeCenter;
    final status = p.statusText;
    return MediaQuery.withNoTextScaling(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: ScreenHeader.topPadding + 2),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Semantics(header: true, child: Text('Тюнер', style: Typo.fixed(28, TypoWeight.semibold, TruverColors.textPrimary))),
                  const Spacer(),
                  RoundIconButton(icon: p.inputIcon, size: 48, iconSize: 22, label: 'Вход: ${p.inputName}', onTap: () => app.showSettings = true),
                  const SizedBox(width: 8),
                  RoundIconButton(icon: AppIcon.gear, size: 48, iconSize: 22, label: 'Настройки', onTap: () => app.showSettings = true),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 280,
                    height: 280,
                    child: p.voiceOver(
                      FittedBox(
                        child: SizedBox(width: 320, height: 320, child: p.dial(center: center)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 86),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SwiftText(
                            status.isEmpty ? ' ' : status,
                            textAlign: TextAlign.center,
                            style: Typo.fixed(28, TypoWeight.semibold, p.statusColor),
                          ),
                        ),
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          swiftNotes(detail, Typo.fixed(18, TypoWeight.regular, TruverColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  if (p.micUnavailable) ...[_ActionView(p: p), const SizedBox(height: 16)],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _LargeStringGrid(p: p),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 16),
                    child: _LargeSegments(selection: p.demo?.choice ?? tuner.choice, onChanged: (c) => tuner.choice = c),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large-text strings (canvas «Тюнер — крупный шрифт»): three in a row, 74 pt, radius 14, 28 semibold with a 16 pt
/// tertiary octave inline, a 20 × 4 status mark 8 pt under it.
class _LargeStringGrid extends StatelessWidget {
  const _LargeStringGrid({required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    final courses = p.tuner.courses;
    final rows = <Widget>[];
    for (var start = 0; start < courses.length; start += 3) {
      rows.add(
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: start + i < courses.length ? _key(start + i) : const SizedBox.shrink()),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 8), rows[i]],
      ],
    );
  }

  Widget _key(int course) {
    final tuner = p.tuner;
    final ref = StringRef(course);
    final selected = p.isSelected(ref);
    final c = tuner.courses[course];
    return Pressable(
      label: 'Струна ${tuner.stringName(ref)}',
      selected: selected,
      onTap: () => tuner.tapString(ref),
      child: SizedBox(
        height: 74,
        child: ShapeBox(
          shape: const SwiftShape.rounded(14, continuous: true),
          fills: [SwiftFill(TruverColors.white(selected ? 0.09 : 0.04))],
          strokes: [SwiftStroke(selected ? TruverColors.selectedBorder : TruverColors.hairline, inside: true)],
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwiftText.rich(
                  TextSpan(
                    children: [
                      Typo.notes(c.short, Typo.fixed(28, TypoWeight.semibold, TruverColors.textPrimary)),
                      TextSpan(text: '${c.octave}', style: Typo.fixed(16, TypoWeight.regular, TruverColors.textTertiary)),
                    ],
                  ),
                  style: Typo.fixed(28, TypoWeight.semibold, TruverColors.textPrimary),
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 20,
                  height: 4,
                  child: ShapeBox(shape: const SwiftShape.rounded(2), fills: [SwiftFill(TunerPresenter.markColor(p.mark(ref)))]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Large-text mode segments (canvas): 46 pt segments, radius 23, padding 3 + 1 pt border (radius 26), 19 semibold.
class _LargeSegments extends StatelessWidget {
  const _LargeSegments({required this.selection, required this.onChanged});
  final TunerChoice selection;
  final ValueChanged<TunerChoice> onChanged;

  @override
  Widget build(BuildContext context) => ShapeBox(
    shape: const SwiftShape.rounded(26),
    fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
    strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (value, title) in const [(TunerChoice.auto, 'Авто'), (TunerChoice.manual, 'Ручной'), (TunerChoice.chromatic, 'Хром.')])
            Expanded(
              child: Pressable(
                scale: 1,
                label: title,
                selected: value == selection,
                onTap: () => onChanged(value),
                child: SizedBox(
                  height: 46,
                  child: ShapeBox(
                    shape: SwiftShape.capsule,
                    fills: [SwiftFill(value == selection ? TruverColors.accent : const Color(0x00000000))],
                    child: Center(
                      child: Text(
                        title,
                        maxLines: 1,
                        style: Typo.fixed(19, TypoWeight.semibold, value == selection ? TruverColors.background : TruverColors.textSecondary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

// MARK: Landscape (canvas «Тюнер — альбом», LandTuner 844 × 390)

/// Title 20 semibold at (60, 20); the dial 320 × 0.97 at (60, 52); on the right from x 400, 384 wide, from 40: status
/// 20 medium, strings in one row, mode segments, «строй · вход» caption — 14 apart.
class _TunerLandscape extends StatelessWidget {
  const _TunerLandscape({required this.p});
  final TunerPresenter p;

  @override
  Widget build(BuildContext context) {
    final app = p.app;
    final tuner = p.tuner;
    final Widget top;
    if (p.micUnavailable) {
      top = Align(
        alignment: Alignment.centerLeft,
        child: _ActionView(p: p),
      );
    } else if (p.strobeOn && p.hasReading) {
      top = StrobeStrips(phase: p.frozen ? 0 : (tuner.strobe?.angle ?? 0));
    } else {
      top = _StatusText(text: p.statusText.isEmpty ? ' ' : p.statusText, color: p.statusColor, style: Typo.inter(20, TypoWeight.medium), align: TextAlign.left);
    }
    return LandscapeCanvas(
      child: Stack(
        children: [
          Board(
            x: 60,
            y: 20,
            width: 300,
            child: Semantics(header: true, child: SwiftText('Тюнер', style: Typo.inter(20, TypoWeight.semibold, TruverColors.textPrimary))),
          ),
          Positioned(
            left: 60,
            top: 52,
            width: 320 * 0.97,
            height: 320 * 0.97,
            child: FittedBox(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 320, height: 320, child: p.voiceOver(p.dial())),
            ),
          ),
          Board(
            x: 400,
            y: 40,
            width: 384,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                top,
                const SizedBox(height: 14),
                p.showsChromaticStrip ? ChromaticStrip(p: p) : StringGrid(p: p),
                const SizedBox(height: 14),
                SegmentedPill<TunerChoice>(
                  options: const [(TunerChoice.auto, 'Авто'), (TunerChoice.manual, 'Ручной'), (TunerChoice.chromatic, 'Хром.')],
                  selection: p.demo?.choice ?? tuner.choice,
                  onChanged: (c) => tuner.choice = c,
                ),
                const SizedBox(height: 14),
                Pressable(
                  scale: 1,
                  label: 'Строй: ${app.tuningName}',
                  onTap: () => app.sheet = const AppSheet('tunings'),
                  child: SwiftText(
                    '${app.title} · ${p.inputName}',
                    maxLines: 1,
                    style: Typo.caption.copyWith(color: TruverColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: Route notices

/// Route notices over the tuner (canvas «Тюнер — Bluetooth», «Интерфейс отключён» — an orange-bordered card under the
/// header; «Вход переключён» — a centred toast).
class TunerNoticeView extends StatelessWidget {
  const TunerNoticeView({super.key, required this.notice, required this.dismiss, required this.speaker});
  final RouteNotice notice;
  final VoidCallback dismiss;
  final VoidCallback speaker;

  @override
  Widget build(BuildContext context) {
    switch (notice.kind) {
      case RouteNoticeKind.bluetooth:
        return _card(
          AppIcon.bluetooth,
          '${notice.name}: задержка ~${notice.latency} мс',
          'Для тюнера это неважно, но эталонный тон и метроном будут опаздывать. Слушаем микрофон телефона.',
          8,
          Row(
            children: [
              Pressable(
                label: 'Понятно',
                onTap: dismiss,
                child: SizedBox(
                  height: 36,
                  child: ShapeBox(
                    shape: SwiftShape.capsule,
                    fills: const [SwiftFill.gradient(TruverGradients.primaryFill)],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        widthFactor: 1,
                        child: Text('Понятно', style: Typo.button.copyWith(color: TruverColors.background)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                label: 'Звук в динамик',
                onTap: () {
                  speaker();
                  dismiss();
                },
                child: SizedBox(
                  height: 36,
                  child: ShapeBox(
                    shape: SwiftShape.capsule,
                    fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
                    strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(widthFactor: 1, child: Text('Звук в динамик', style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody))),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case RouteNoticeKind.disconnected:
        return GestureDetector(
          onTap: dismiss,
          child: _card(
            AppIcon.audioInterface,
            'Интерфейс отключён',
            '${notice.name} пропал. Слушаю микрофон телефона — вернёмся к интерфейсу, когда подключите.',
            4,
            null,
          ),
        );
      case RouteNoticeKind.inputSwitched:
        return GestureDetector(
          onTap: dismiss,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: ShapeBox(
                shape: const SwiftShape.rounded(16),
                shadows: [SwiftShadow(TruverColors.black(0.6), 15, y: 14)],
                fills: const [SwiftFill(Color.fromRGBO(38, 40, 45, 0.96))],
                strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIconView(AppIcon.audioInterface, size: 16, color: TruverColors.textSecondary),
                      const SizedBox(width: 10),
                      Flexible(child: SwiftText(notice.name, maxLines: 1, style: Typo.inter(13, TypoWeight.medium, TruverColors.textBody))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }

  /// Padding 12 / 14 + 1 pt border, radius 14, #1e1f23 at 98 %, orange 40 % border, 20 pt icon 10 pt from the text.
  Widget _card(AppIcon icon, String title, String text, double spacing, Widget? actions) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: ShapeBox(
      shape: const SwiftShape.rounded(14),
      shadows: [SwiftShadow(TruverColors.black(0.6), 15, y: 14)],
      fills: const [SwiftFill(Color.fromRGBO(30, 31, 35, 0.98))],
      strokes: [SwiftStroke(TruverColors.sharp.withValues(alpha: 0.4), inside: true)],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconView(icon, size: 20, color: TruverColors.sharp),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwiftText(title, style: Typo.inter(14, TypoWeight.semibold, TruverColors.textPrimary)),
                  SizedBox(height: spacing + 1.13),
                  // line-height 1.4 on 12 pt: 16.8 pt lines (Inter's own 14.5).
                  SwiftText(text, lineSpacing: 2.27, style: Typo.caption.copyWith(color: TruverColors.textSecondary)),
                  if (actions != null) ...[SizedBox(height: spacing + 1.13), actions] else const SizedBox(height: 1.13),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// MARK: VoiceOver / TalkBack

/// The dial as one adjustable element: «Тюнер. A2, ниже на 14 центов». Spoken updates — at most once per 1.5 s and
/// only when the reading moved by more than 3 c; «В строю» at once (canvas «Тюнер — VoiceOver»).
class TunerVoiceOver extends StatefulWidget {
  const TunerVoiceOver({
    super.key,
    required this.value,
    required this.inTune,
    required this.cents,
    required this.adjust,
    this.increased = '',
    this.decreased = '',
    required this.child,
  });
  final String value;
  final String increased;
  final String decreased;
  final bool inTune;
  final double? cents;
  final void Function(bool up) adjust;
  final Widget child;

  @override
  State<TunerVoiceOver> createState() => _TunerVoiceOverState();
}

class _TunerVoiceOverState extends State<TunerVoiceOver> {
  DateTime _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
  double? _lastCents;
  bool _lastInTune = false;

  @override
  void didUpdateWidget(TunerVoiceOver old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _announce(widget.value);
  }

  void _announce(String text) {
    if (!MediaQuery.accessibleNavigationOf(context)) return;
    final view = View.of(context);
    if (widget.inTune && !_lastInTune) {
      _lastInTune = true;
      _lastSpoken = DateTime.now();
      SemanticsService.sendAnnouncement(view, 'В строю', TextDirection.ltr);
      return;
    }
    _lastInTune = widget.inTune;
    if (DateTime.now().difference(_lastSpoken).inMilliseconds < 1500) return;
    final c = widget.cents, last = _lastCents;
    if (c != null && last != null && (c - last).abs() <= 3) return;
    _lastSpoken = DateTime.now();
    _lastCents = c;
    SemanticsService.sendAnnouncement(view, text, TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Тюнер',
    value: widget.value,
    increasedValue: widget.increased,
    decreasedValue: widget.decreased,
    onIncrease: () => widget.adjust(true),
    onDecrease: () => widget.adjust(false),
    child: ExcludeSemantics(child: widget.child),
  );
}

// MARK: «Ещё» (canvas «Тюнер — дополнительно», FixTunerPro)

/// Noise gate, target, strobe switch, stage, intonation check, A4 of this tuning — a canvas sheet from 226.
class TunerProSheet extends StatelessWidget {
  const TunerProSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tuner = app.tuner;
    final gate = tuner.noiseGate.round();
    return DesignSheet(
      title: 'Тюнер · дополнительно',
      height: 618,
      close: () => app.sheet = null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Measured on the render: the canvas cards keep their 1 pt border inside the padding (as `Card` does); the rows
          // are 60 / 52 plus their own 1 pt bottom border.
          Card(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SwiftText('Порог шума', style: Typo.row.copyWith(color: TruverColors.textBody)),
                        ),
                        SwiftText('${gate < 0 ? '−${-gate}' : '$gate'} дБ', style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    SwiftText('выше — не реагирует на гул комнаты', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                    const SizedBox(height: 10),
                    GateSlider(
                      value: tuner.noiseGate,
                      min: TunerController.noiseGateMin,
                      max: TunerController.noiseGateMax,
                      onChanged: (v) => tuner.noiseGate = v,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SectionCaption(text: 'Цель'),
          Card(
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: SegmentedPill<TunerChoice>(
                  options: const [(TunerChoice.auto, 'Струны строя'), (TunerChoice.chromatic, 'Ближайшая ступень')],
                  selection: tuner.choice == TunerChoice.chromatic ? TunerChoice.chromatic : TunerChoice.auto,
                  onChanged: (c) => tuner.choice = c,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            children: [
              Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardRow(
                      title: 'Строб',
                      subtitle: 'вращение — точная подстройка',
                      minHeight: 61,
                      trailing: ToggleSwitch(isOn: tuner.strobeView, onChanged: (v) => tuner.strobeView = v, label: 'Строб'),
                    ),
                    Pressable(
                      scale: 1,
                      onTap: () {
                        app.sheet = null;
                        openTunerStage(context);
                      },
                      child: const CardRow(
                        title: 'Сценический режим',
                        subtitle: 'нота и цвет на весь экран',
                        minHeight: 61,
                        trailing: AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                      ),
                    ),
                    Pressable(
                      scale: 1,
                      onTap: () => app.sheet = const AppSheet('intonation'),
                      child: const CardRow(
                        title: 'Проверка мензуры',
                        subtitle: 'открытая против 12-го лада',
                        minHeight: 61,
                        trailing: AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                      ),
                    ),
                    Pressable(
                      scale: 1,
                      onTap: () {
                        app.tuningEditorFromTuner = true;
                        app.sheet = AppSheet('tuningEditor', app.tuning['id']);
                      },
                      child: CardRow(
                        title: 'Частота (A4) этого строя',
                        minHeight: 53,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${app.a4.toInt()} Гц'),
                            const SizedBox(width: 8),
                            const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Canvas slider: a 4 pt track (white 12 %) with the ivory part up to the value, a 28 pt white knob; 28 pt high.
/// Adjustable with TalkBack (± 1 dB).
class GateSlider extends StatelessWidget {
  const GateSlider({super.key, required this.value, required this.min, required this.max, required this.onChanged});
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  double _clamp(double v) => v.round().toDouble().clamp(min, max).toDouble();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
      void update(double dx) => onChanged(_clamp(min + (dx / w).clamp(0.0, 1.0) * (max - min)));
      return Semantics(
        slider: true,
        label: 'Порог шума',
        value: '${value.toInt()} дБ',
        increasedValue: '${_clamp(value + 1).toInt()} дБ',
        decreasedValue: '${_clamp(value - 1).toInt()} дБ',
        onIncrease: () => onChanged(_clamp(value + 1)),
        onDecrease: () => onChanged(_clamp(value - 1)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          onTapDown: (d) => update(d.localPosition.dx),
          child: SizedBox(
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 12,
                  child: SizedBox(
                    height: 4,
                    child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.12))]),
                  ),
                ),
                Positioned(
                  left: 0,
                  width: t * w,
                  top: 12,
                  child: const SizedBox(
                    height: 4,
                    child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.accent)]),
                  ),
                ),
                Positioned(
                  left: t * w - 14,
                  top: 0,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: ShapeBox(
                      shape: SwiftShape.circle,
                      shadows: [SwiftShadow(TruverColors.black(0.5), 3, y: 2)],
                      fills: const [SwiftFill(Color(0xFFFFFFFF))],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// MARK: Stage mode (TU-12)

/// Opens «Сценический режим» as a full-screen cover over the whole app (iOS `.fullScreenCover`).
void openTunerStage(BuildContext context, {bool animated = true}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: animated ? const Duration(milliseconds: 420) : Duration.zero,
      reverseTransitionDuration: animated ? Motion.move : Duration.zero,
      pageBuilder: (context, _, _) => const _TunerStageRoute(),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Motion.snap, reverseCurve: Motion.inCurve)),
        child: child,
      ),
    ),
  );
}

class _TunerStageRoute extends StatefulWidget {
  const _TunerStageRoute();

  @override
  State<_TunerStageRoute> createState() => _TunerStageRouteState();
}

class _TunerStageRouteState extends State<_TunerStageRoute> {
  @override
  void initState() {
    super.initState();
    // iOS `.statusBarHidden()` + `.persistentSystemOverlays(.hidden)`; the screen already stays on (MainActivity).
    // TODO(android): screen brightness to the maximum (WindowManager.LayoutParams.screenBrightness) while open.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TunerPresenter(AppScope.of(context));
    final cents = p.needleCents;
    return TunerStageView(
      center: p.dialCenter,
      cents: cents,
      inTune: p.voiceInTune || (cents != null && cents.abs() <= 3),
      tuningName: p.app.title,
      close: () => Navigator.of(context).maybePop(),
    );
  }
}

/// TU-12 (canvas «Тюнер — сцена», TunerStagePhone): the deviation colour as a radial glow over the whole screen, the
/// tuning and «касание — выйти» at the top (70), the note 220 ExtraLight with a 56 pt octave (190), «В строю · +1 ц»
/// 34 medium (470), a ±50 c line 310 wide with a 4 × 28 marker (560), «Экран не гаснет · яркость на максимум» (700).
/// A tap anywhere leaves. Reduce motion: a slow cross-fade. TODO(android): «Затемнение вспышек» has no Android
/// setting — `dimFlashing` stays false.
class TunerStageView extends StatelessWidget {
  const TunerStageView({super.key, required this.center, required this.cents, required this.inTune, required this.tuningName, required this.close});
  final DialCenter center;
  final double? cents;
  final bool inTune;
  final String tuningName;
  final VoidCallback close;

  static const dimFlashing = false;

  bool get _hasReading => cents != null;
  bool get _green => inTune || (cents != null && cents!.abs() <= 3);

  /// The canvas glow (in tune): rgba(70,224,143,0.32) → rgba(10,40,26,0.9) at 70 % → #06130c; the same recipe in
  /// blue / orange for flat / sharp.
  List<Color> get _glow {
    final c = cents;
    if (c == null || dimFlashing) return const [Color(0x00000000), Color(0x00000000), Color(0x00000000)];
    if (_green) return const [Color.fromRGBO(70, 224, 143, 0.32), Color.fromRGBO(10, 40, 26, 0.9), Color(0xFF06130C)];
    if (c < 0) return const [Color.fromRGBO(106, 168, 255, 0.32), Color.fromRGBO(10, 24, 46, 0.9), Color(0xFF060B14)];
    return const [Color.fromRGBO(255, 155, 82, 0.32), Color.fromRGBO(46, 24, 10, 0.9), Color(0xFF140B06)];
  }

  /// «В строю · +1 ц» — a pale tint of the deviation colour.
  Color get _lineColor {
    final c = cents;
    if (c == null) return TruverColors.textSecondary;
    if (_green) return const Color(0xFFB9F5D4);
    return c < 0 ? const Color(0xFFC9DEFD) : const Color(0xFFFFD9BD);
  }

  String get _centsLine {
    final c = cents;
    if (c == null) return '';
    final v = c.round();
    final text = '${v > 0 ? '+$v' : (v < 0 ? '−${-v}' : '0')} ц';
    if (_green) return 'В строю · $text';
    return '$text · ${v < 0 ? 'подтяните' : 'ослабьте'}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width, h = size.height;
    // Board rows at 844 pt; taller or shorter screens stretch them.
    final k = h / 844;
    final glow = _glow;
    final white = TruverColors.white(0.6);
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      child: Semantics(
        explicitChildNodes: true,
        onTap: close,
        hint: 'Закрыть сценический режим',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          child: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(center: TruverGradients.screenCenter, radius: 1.2, colors: [TruverColors.backgroundLift, TruverColors.background]),
                  ),
                ),
              ),
              // radial-gradient(80% 60% at 50% 40%): radii 0.8 w × 0.6 h around (0.5 w, 0.4 h).
              Positioned(
                left: 0.5 * w - 0.8 * w,
                top: 0.4 * h - 0.6 * h,
                width: 1.6 * w,
                height: 1.2 * h,
                child: Opacity(
                  opacity: _hasReading ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(radius: 0.5, colors: glow, stops: const [0, 0.7, 1]),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                top: 70 * k,
                child: Row(
                  children: [
                    Expanded(child: SwiftText(tuningName, maxLines: 1, style: Typo.inter(13, TypoWeight.regular, white))),
                    SwiftText('касание — выйти', style: Typo.inter(13, TypoWeight.regular, white)),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 190 * k,
                height: 220,
                child: Center(child: _noteText()),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 470 * k,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SwiftText(_centsLine, maxLines: 1, style: Typo.inter(34, TypoWeight.medium, _lineColor)),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 560 * k,
                child: Center(child: _marker(math.min(w - 80, 520))),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 700 * k,
                child: Center(child: SwiftText('Экран не гаснет · яркость на максимум', style: Typo.inter(13, TypoWeight.regular, TruverColors.white(0.55)))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The note 220 pt ExtraLight, line-height 1, the octave an inline 56 pt span at 70 %.
  Widget _noteText() {
    final c = center;
    String? name, octave;
    if (c is DialNote) {
      name = c.name;
      octave = c.octave;
    } else if (c is DialStrobeNote) {
      name = c.name;
      octave = c.octave;
    }
    if (name != null) {
      return Semantics(
        label: name + octave!,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: _hasReading ? 1 : 0.3,
            child: OverflowBox(
              maxHeight: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    children: [
                      Typo.notes(name, Typo.fixed(220, TypoWeight.extraLight, const Color(0xFFFFFFFF))),
                      TextSpan(text: octave, style: Typo.fixed(56, TypoWeight.regular, TruverColors.white(0.7))),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (c is DialDone) return const AppIconView(AppIcon.check, size: 132, lineWidth: 6, color: TruverColors.inTune);
    return Text('Сыграйте струну', style: Typo.inter(26, TypoWeight.medium, TruverColors.textSecondary));
  }

  /// ±50 c line (12 pt, white 15 %) with a 4 × 28 white marker, 2 pt per cent from the centre.
  Widget _marker(double width) {
    final x = (cents ?? 0).clamp(-50.0, 50.0) * 2 + 2;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: 12,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ShapeBox(shape: SwiftShape.capsule, fills: [SwiftFill(TruverColors.white(0.15))]),
            ),
            Positioned(
              left: width / 2 + x,
              top: -8,
              width: 4,
              height: 28,
              child: Opacity(
                opacity: _hasReading ? 1 : 0,
                child: const ShapeBox(shape: SwiftShape.rounded(2), fills: [SwiftFill(Color(0xFFFFFFFF))]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

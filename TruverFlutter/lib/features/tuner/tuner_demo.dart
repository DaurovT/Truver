/// Port of the `TunerDemo` and `TunerController.RouteNotice` parts of Truver/Sources/Features/Tuner/TunerScreen.swift
/// and TunerController.swift.
library;

import 'package:flutter/widgets.dart';

import '../../design/icons.dart';
import '../../design/theme.dart';
import 'tuner_controller.dart';
import 'tuner_dial.dart';

enum RouteNoticeKind { bluetooth, disconnected, inputSwitched }

/// Audio route notices over the tuner (canvas «Тюнер — Bluetooth», «Интерфейс отключён», «Вход переключён»).
@immutable
class RouteNotice {
  /// Bluetooth output: the headset mic is not used, the output lags (`latency` ms).
  const RouteNotice.bluetooth(this.name, this.latency) : kind = RouteNoticeKind.bluetooth;

  /// The interface went away; the tuner listens to the built-in microphone.
  const RouteNotice.disconnected(this.name) : kind = RouteNoticeKind.disconnected, latency = 0;

  /// Another input took over: «Слушаю Focusrite 2i2 · вход 1 (гитара)» (`name` is the whole line).
  const RouteNotice.inputSwitched(this.name) : kind = RouteNoticeKind.inputSwitched, latency = 0;

  final RouteNoticeKind kind;
  final String name;
  final int latency;
}

/// The state's action under the dial (canvas «Нет доступа» / «Звук недоступен»): title and button width.
@immutable
class TunerDemoAction {
  const TunerDemoAction(this.title, this.width);
  final String title;
  final double width;
}

/// Debug hook: `-tunerDemo <state>` freezes the screen on a state of the canvas (no guitar in tests; every animation
/// stands at its first frame). States — the boards FixTunerFlat / Sharp / Waiting / Done / Reference / OutOfRange /
/// NoAccess, TunerListening / Manual / Chromatic / Strobe / Bluetooth / EngineFail / InputSwitched,
/// DeviceDisconnected, TunerStagePhone (`-tunerStage`), LandTuner (`landscape`). The selected key is named by its
/// label («A2»), the marks count from the lowest string — so the same state works on 6, 7 and 8 strings.
@immutable
class TunerDemo {
  const TunerDemo({
    required this.center,
    required this.status,
    required this.statusColor,
    this.cents,
    this.color,
    this.inTune = false,
    this.selected,
    this.lowMarks = const [],
    this.selectedMark = StringStatus.unknown,
    this.allMarks,
    this.choice = TunerChoice.auto,
    this.strobe = false,
    this.done = false,
    this.action,
    this.notice,
    this.input,
    this.chromaticPitchClass,
    this.bandAngle = 0,
  });

  final DialCenter center;
  final String status;
  final Color statusColor;
  final double? cents;
  final Color? color;
  final bool inTune;
  final String? selected;
  final List<StringStatus> lowMarks;

  /// Mark of the selected key.
  final StringStatus selectedMark;
  final StringStatus? allMarks;
  final TunerChoice choice;
  final bool strobe;
  final bool done;
  final TunerDemoAction? action;
  final RouteNotice? notice;
  final String? input;
  final int? chromaticPitchClass;

  /// Where the canvas render catches the spinning band (0.05 s in: «spinrev 6s» −3°, «spin 1.2s» +15°, «spin 6s» +3°).
  final double bandAngle;

  StringStatus mark(int course) => allMarks ?? (course < lowMarks.length ? lowMarks[course] : StringStatus.unknown);

  TunerDemo copyWith({Color? statusColor, List<StringStatus>? lowMarks, RouteNotice? notice, String? input, double? bandAngle}) => TunerDemo(
    center: center,
    status: status,
    statusColor: statusColor ?? this.statusColor,
    cents: cents,
    color: color,
    inTune: inTune,
    selected: selected,
    lowMarks: lowMarks ?? this.lowMarks,
    selectedMark: selectedMark,
    allMarks: allMarks,
    choice: choice,
    strobe: strobe,
    done: done,
    action: action,
    notice: notice ?? this.notice,
    input: input ?? this.input,
    chromaticPitchClass: chromaticPitchClass,
    bandAngle: bandAngle ?? this.bandAngle,
  );

  static const _flat = TunerDemo(
    center: DialNote(name: 'A', octave: '2', cents: '−14 ц', centsColor: TruverColors.flat, detail: '109,1 Гц · цель 110,0'),
    status: 'Ниже — подтяните',
    statusColor: TruverColors.flat,
    cents: -14,
    color: TruverColors.flat,
    selected: 'A2',
    lowMarks: [StringStatus.inTune],
    selectedMark: StringStatus.flat,
    bandAngle: -3,
  );

  static const _sharp = TunerDemo(
    center: DialNote(name: 'D', octave: '3', cents: '+31 ц', centsColor: TruverColors.sharp, detail: '148,5 Гц · цель 146,8'),
    status: 'Выше — ослабьте',
    statusColor: TruverColors.sharp,
    cents: 31,
    color: TruverColors.sharp,
    selected: 'D3',
    lowMarks: [StringStatus.inTune, StringStatus.inTune],
    selectedMark: StringStatus.sharp,
    bandAngle: 15,
  );

  static TunerDemo? named(String? name) => switch (name) {
    'flat' => _flat,
    // Canvas «Тюнер — крупный шрифт»: the flat reading, no string marked yet.
    'large' => _flat.copyWith(lowMarks: const []),
    'sharp' || 'landscape' => _sharp,
    'waiting' => const TunerDemo(
      center: DialNote(name: 'E', octave: '2', cents: '', centsColor: TruverColors.inTune, detail: 'начните с 6-й струны', dimmed: true),
      status: 'Сыграйте струну',
      statusColor: TruverColors.textBody,
    ),
    'done' => const TunerDemo(
      center: DialDone(detail: '6 из 6 струн в строю'),
      status: 'Все струны в строю',
      statusColor: TruverColors.inTune,
      color: TruverColors.inTune,
      inTune: true,
      allMarks: StringStatus.inTune,
      done: true,
    ),
    'reference' => const TunerDemo(
      center: DialReference(title: 'Эталон E2', detail: '82,41 Гц · анализ на паузе'),
      status: 'Звучит эталон · 3 с',
      statusColor: TruverColors.textBody,
      selected: 'E2',
    ),
    'outOfRange' => const TunerDemo(
      center: DialMessage(icon: AppIcon.warning, iconColor: TruverColors.textBody, title: 'Вне диапазона', detail: 'Ниже 25 Гц или выше последнего лада'),
      status: 'Сыграйте открытую струну',
      statusColor: TruverColors.textBody,
      lowMarks: [StringStatus.inTune],
    ),
    'noAccess' => const TunerDemo(
      center: DialMessage(icon: AppIcon.micOff, iconColor: TruverColors.sharp, title: 'Нужен микрофон', detail: 'Тюнер слышит струну. Звук не записывается'),
      status: '',
      statusColor: TruverColors.textBody,
      action: TunerDemoAction('Разрешить микрофон', 250),
    ),
    'engineFail' => const TunerDemo(
      center: DialMessage(
        icon: AppIcon.warning,
        iconColor: TruverColors.sharp,
        title: 'Звук недоступен',
        detail: 'Микрофон занят другим приложением или звонком',
      ),
      status: '',
      statusColor: TruverColors.textBody,
      action: TunerDemoAction('Повторить', 200),
    ),
    'listening' => const TunerDemo(center: DialListening(), status: 'Дайте струне прозвучать', statusColor: TruverColors.textBody),
    'manual' => const TunerDemo(
      center: DialNote(name: 'G', octave: '3', cents: '−3 ц', centsColor: TruverColors.inTune, detail: '195,6 Гц · цель 196,0'),
      status: 'Ручной: только G3 — другие ноты не мешают',
      statusColor: TruverColors.inTune,
      cents: -3,
      color: TruverColors.inTune,
      inTune: true,
      selected: 'G3',
      lowMarks: [StringStatus.inTune, StringStatus.inTune, StringStatus.inTune],
      selectedMark: StringStatus.inTune,
      choice: TunerChoice.manual,
      bandAngle: -3,
    ),
    'chromatic' => const TunerDemo(
      center: DialNote(name: 'C♯', octave: '4', cents: '+6 ц', centsColor: TruverColors.inTune, detail: '279,2 Гц'),
      status: 'Хроматический: любая нота, не только струны строя',
      statusColor: TruverColors.textBody,
      cents: 6,
      color: TruverColors.inTune,
      inTune: true,
      choice: TunerChoice.chromatic,
      chromaticPitchClass: 1,
      bandAngle: 3,
    ),
    'strobe' => const TunerDemo(
      center: DialStrobeNote(name: 'A', octave: '2', line: '−2 ц · полосы почти стоят', color: TruverColors.inTune),
      status: '',
      statusColor: TruverColors.textBody,
      cents: -2,
      color: TruverColors.inTune,
      inTune: true,
      selected: 'A2',
      lowMarks: [StringStatus.inTune],
      strobe: true,
    ),
    'stage' => const TunerDemo(
      center: DialNote(name: 'E', octave: '2', cents: '+1 ц', centsColor: TruverColors.inTune, detail: ''),
      status: 'В строю',
      statusColor: TruverColors.inTune,
      cents: 1,
      color: TruverColors.inTune,
      inTune: true,
      selected: 'E2',
    ),
    'bluetooth' => _flat.copyWith(statusColor: TruverColors.textBody, lowMarks: const [], notice: const RouteNotice.bluetooth('AirPods', 180), bandAngle: 0),
    'disconnected' => _flat.copyWith(
      statusColor: TruverColors.textBody,
      lowMarks: const [],
      notice: const RouteNotice.disconnected('Focusrite 2i2'),
      bandAngle: 0,
    ),
    'inputSwitched' => _flat.copyWith(notice: const RouteNotice.inputSwitched('Слушаю Focusrite 2i2 · вход 1 (гитара)'), input: 'Focusrite 2i2'),
    _ => null,
  };
}

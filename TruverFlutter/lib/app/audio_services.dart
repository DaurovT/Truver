/// Port of Truver/Sources/Audio/AudioServices.swift
///
/// Audio policy of the app on top of the core's `audio.*` bridge commands (TruverBridge/AudioCommands.swift):
/// one AAudio host in the core, the microphone only while a module needs it (AU-4), real-time data polled once
/// per frame (`audio.poll`) and handed to every listener (tuner, metronome…).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/truver_core.dart';

enum MicPermission {
  undetermined,
  granted,
  denied,

  /// A profile or policy forbids the microphone — the user cannot allow it (canvas «Тюнер — доступ ограничен»).
  /// Android: «больше не спрашивать» / permanently denied lands here too.
  restricted,
}

/// One `audio.poll` result: `{now, tuner: [...], ticks: [...], notices: [...], metronomeRunning, tunerRunning}`.
typedef AudioPoll = Map<String, dynamic>;

class AudioServices {
  AudioServices(this.core);

  /// null when the core library is missing (desktop without the core) — every call becomes a no-op.
  final TruverCore? core;

  VoidCallback? onConfigurationChange;

  /// false once the core reported that this platform has no audio host.
  bool available = true;

  /// Calls an `audio.*` command; null when there is no core or no audio host on this platform (macOS tests).
  dynamic call(String method, [Map<String, dynamic>? params]) {
    final c = core;
    if (c == null || !available) return null;
    try {
      return c.call(method, params);
    } on TruverCoreError catch (e) {
      // The macOS test build of the core has no audio host: stop calling after the first refusal.
      if (e.message.contains('not available')) {
        available = false;
      } else {
        debugPrint('$method: $e');
      }
      return null;
    }
  }

  // MARK: Volumes and latency (SND-7, ME-9)

  double clickVolume = 0.8;
  double notesVolume = 0.6;
  double referenceVolume = 0.5;
  String clickSound = 'click';

  /// «Громкость акцента»: the strong click over the normal one, dB (core `ClickSounds.defaultAccentDB`).
  double accentDB = 6;

  /// ME-9: manual corrections in ms per output name, from the settings.
  Map<String, double> _latencyOffsets = {};
  Map<String, double> get latencyOffsets => _latencyOffsets;
  set latencyOffsets(Map<String, double> value) {
    _latencyOffsets = Map.of(value);
    applyLatency();
  }

  /// Output name the correction is stored under. TODO(android): name the routed device (AudioDeviceInfo) —
  /// «Динамик» until the host reports routes.
  String get outputName => 'Динамик';

  void setVolumes({double? click, double? notes, double? reference, String? sound, double? accentDB}) {
    clickVolume = click ?? clickVolume;
    notesVolume = notes ?? notesVolume;
    referenceVolume = reference ?? referenceVolume;
    clickSound = sound ?? clickSound;
    this.accentDB = accentDB ?? this.accentDB;
    _sendVolumes();
  }

  /// The beat timeline and the flash use the system latency (from AAudio timestamps, in the core) + the manual
  /// correction (ME-9, ME-12).
  void applyLatency() => _sendVolumes();

  void _sendVolumes() => call('audio.setVolumes', {
        'click': clickVolume,
        'notes': notesVolume,
        'reference': referenceVolume,
        'clickSound': clickSound,
        'accentDB': accentDB,
        'latencyOffset': (_latencyOffsets[outputName] ?? 0) / 1000,
      });

  // MARK: Microphone (AU-4)

  MicPermission _mic = MicPermission.undetermined;

  /// Last known permission; refresh with [refreshMicPermission].
  MicPermission get micPermission => _mic;

  static MicPermission _map(PermissionStatus s) => switch (s) {
        PermissionStatus.granted || PermissionStatus.limited || PermissionStatus.provisional => MicPermission.granted,
        PermissionStatus.restricted || PermissionStatus.permanentlyDenied => MicPermission.restricted,
        PermissionStatus.denied => MicPermission.denied,
      };

  Future<MicPermission> refreshMicPermission() async {
    try {
      final status = await Permission.microphone.status;
      // Android reports «denied» before the first request too: keep «undetermined» until we have asked.
      _mic = status == PermissionStatus.denied && !_asked ? MicPermission.undetermined : _map(status);
    } catch (_) {}
    return _mic;
  }

  bool _asked = false;

  Future<MicPermission> requestMicPermission() async {
    try {
      _asked = true;
      _mic = _map(await Permission.microphone.request());
    } catch (_) {}
    return _mic;
  }

  /// For the metronome and note sounds. The core's AAudio host keeps one output stream; nothing to switch (AU-5).
  void ensurePlayback() => applyLatency();

  /// For the tuner, trainer and smart mode: the input opens with `audio.startTuner` (UNPROCESSED preset ≈ iOS
  /// `.measurement`, AU-1).
  void ensureRecording() => applyLatency();

  /// Plays a pluck of `cents` (from A4 = 440) on string `string`.
  void playNote(double cents, {int? string}) {
    ensurePlayback();
    call('audio.playNotes', {
      'notes': [
        {'cents': cents, 'string': ?string},
      ],
    });
  }

  // MARK: Per-frame poll

  final List<void Function(AudioPoll poll)> _listeners = [];
  bool _scheduled = false;

  /// Adds a per-frame listener of `audio.poll`; polling runs while there is at least one listener.
  void addPollListener(void Function(AudioPoll poll) listener) {
    _listeners.add(listener);
    _schedule();
  }

  void removePollListener(void Function(AudioPoll poll) listener) => _listeners.remove(listener);

  void _schedule() {
    if (_scheduled || _listeners.isEmpty) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduled = false;
      if (_listeners.isEmpty) return;
      final poll = call('audio.poll');
      if (poll is Map) {
        final map = Map<String, dynamic>.from(poll);
        for (final l in List.of(_listeners)) {
          l(map);
        }
      }
      _schedule();
    });
  }
}

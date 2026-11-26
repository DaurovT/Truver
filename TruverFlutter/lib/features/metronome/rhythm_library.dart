/// The rhythmic figures of the metronome (`BeatRhythm`, `BeatRhythms` in TruverDSP/MetronomeModel.swift) as the
/// core describes them through `metronome.rhythms` / `metronome.describe` (TruverBridge/MetronomeCommands.swift):
/// the stored JSON plus names and notation values. Nothing about figures is computed on the Dart side.
library;

import 'dart:convert';

import '../../core/truver_core.dart';

/// One figure: `json` is the core `BeatRhythm` as stored in `MeterSettings` (`id, grid, onsets, span, group`).
class RhythmInfo {
  RhythmInfo._(this.json, Map<String, dynamic> dto)
    : name = dto['name'] as String? ?? '',
      shortName = dto['shortName'] as String? ?? '',
      spokenName = dto['spokenName'] as String? ?? '',
      tuplet = (dto['tuplet'] as num?)?.toInt(),
      tupletLabel = dto['tupletLabel'] as String?,
      durations = [for (final d in (dto['durations'] as List? ?? const [])) (d as num).toInt()],
      stepsPerBeat = (dto['stepsPerBeat'] as num?)?.toDouble() ?? 1,
      isPlain = dto['isPlain'] as bool? ?? false;

  final Map<String, dynamic> json;
  final String name;
  final String shortName;
  final String spokenName;
  final int? tuplet;
  final String? tupletLabel;
  final List<int> durations;
  final double stepsPerBeat;
  final bool isPlain;

  String get id => json['id'] as String;
  int get grid => (json['grid'] as num).toInt();
  List<int> get onsets => [for (final o in json['onsets'] as List) (o as num).toInt()];
  int get span => (json['span'] as num?)?.toInt() ?? 1;
  String get group => json['group'] as String? ?? 'values';

  /// Swift `BeatRhythm ==` (all stored fields).
  bool sameAs(RhythmInfo? other) => other != null && RhythmLibrary.key(json) == RhythmLibrary.key(other.json);
}

class RhythmGroupInfo {
  const RhythmGroupInfo(this.id, this.title);
  final String id;
  final String title;
}

abstract final class RhythmLibrary {
  static List<RhythmInfo>? _all;
  static List<RhythmGroupInfo> _groups = const [];
  static final Map<String, RhythmInfo> _described = {};

  static TruverCore? get _core => TruverCore.instance;

  /// `BeatRhythms.all`.
  static List<RhythmInfo> get all {
    if (_all != null) return _all!;
    final list = <RhythmInfo>[];
    try {
      final r = _core?.call('metronome.rhythms');
      if (r is Map) {
        _groups = [for (final g in r['groups'] as List) RhythmGroupInfo(g['id'] as String, g['title'] as String)];
        for (final d in r['rhythms'] as List) {
          final dto = Map<String, dynamic>.from(d as Map);
          final info = RhythmInfo._(Map<String, dynamic>.from(dto['rhythm'] as Map), dto);
          list.add(info);
          _described[key(info.json)] = info;
        }
      }
    } catch (_) {}
    return _all = list;
  }

  /// `BeatRhythmGroup.allCases` with titles.
  static List<RhythmGroupInfo> get groups {
    all;
    return _groups;
  }

  /// `BeatRhythms.rhythm(id:)`.
  static RhythmInfo? byId(String id) => all.where((r) => r.id == id).firstOrNull;

  /// `BeatRhythms.figures(in:)`.
  static List<RhythmInfo> figures(String group) => [
    for (final r in all)
      if (r.group == group) r,
  ];

  /// Equality key of a stored figure.
  static String key(Map<String, dynamic> json) =>
      jsonEncode([json['id'], json['grid'], json['onsets'], json['span'] ?? 1, json['group'] ?? 'values']);

  /// Names and values of any stored figure (from the library when it is one of its figures).
  static RhythmInfo describe(Map<String, dynamic> json) {
    all;
    final k = key(json);
    final known = _described[k];
    if (known != null) return known;
    var dto = <String, dynamic>{};
    try {
      final r = _core?.call('metronome.describe', {
        'rhythms': [json],
      });
      if (r is List && r.isNotEmpty) dto = Map<String, dynamic>.from(r.first as Map);
    } catch (_) {}
    final info = RhythmInfo._(dto['rhythm'] is Map ? Map<String, dynamic>.from(dto['rhythm'] as Map) : json, dto);
    _described[k] = info;
    return info;
  }

  /// The even subdivision `n` as a figure (`BeatRhythm(id: "sub\(n)", grid: n, onsets: 0..<n)` when not in the library).
  static RhythmInfo plain(int n) =>
      all.where((r) => r.span == 1 && r.isPlain && r.grid == n).firstOrNull ??
      describe({
        'id': 'sub$n',
        'grid': n,
        'onsets': [for (var i = 0; i < n; i++) i],
        'span': 1,
        'group': 'values',
      });
}

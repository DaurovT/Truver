import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Launch arguments for screenshots and checks — the same names as the iOS app (`-tab tuner`, `-sheet metroModes`,
/// `-tunerDemo flat`…). Android: an intent extra `args` (see MainActivity.kt); tests: `TruverTestApp(args:)`.
class DebugArgs {
  DebugArgs(String raw) : list = raw.trim().isEmpty ? const [] : raw.trim().split(RegExp(r'\s+'));

  final List<String> list;

  bool has(String flag) => list.contains(flag);

  /// The value after `flag` (`value('-tab')` → `tuner`), or null.
  String? value(String flag) {
    final i = list.indexOf(flag);
    return i >= 0 && i + 1 < list.length ? list[i + 1] : null;
  }

  int? intValue(String flag) => int.tryParse(value(flag) ?? '');

  static const _channel = MethodChannel('truver/debug');

  /// Reads the launch arguments on Android (empty elsewhere and in release builds).
  static Future<DebugArgs> load() async {
    if (kReleaseMode) return DebugArgs('');
    try {
      return DebugArgs(await _channel.invokeMethod<String>('args') ?? '');
    } catch (_) {
      return DebugArgs('');
    }
  }
}

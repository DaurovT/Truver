import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The Swift core (TruverCore → TruverBridge) loaded through dart:ffi.
///
/// Everything goes through one JSON call: `call('method', {params})` returns the decoded `ok` value or throws
/// [TruverCoreError]. Real-time data (tuner readings, beat ticks) comes from `audio.poll`, which the app calls
/// once per frame — no callback ever crosses from an audio thread into Dart.
class TruverCore {
  TruverCore._(DynamicLibrary lib)
      : _call = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('truver_call'),
        _free = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('truver_free'),
        _now = lib.lookupFunction<Int64 Function(), int Function()>('truver_now_ns');

  static TruverCore? _instance;

  /// Why the library did not load (shown in diagnostics).
  static String? loadError;

  /// The loaded core, or null when the library is missing (e.g. a desktop build without the core yet).
  static TruverCore? get instance {
    if (_instance != null) return _instance;
    try {
      _instance = TruverCore._(_open());
    } catch (e) {
      loadError = '$e';
      _instance = null;
    }
    return _instance;
  }

  static DynamicLibrary _open() {
    // Tests and tools: an explicit path (flutter test on the Mac loads macos/Frameworks/libTruverBridge.dylib).
    final explicit = Platform.environment['TRUVER_CORE_LIB'];
    if (explicit != null) return DynamicLibrary.open(explicit);
    if (Platform.isMacOS && File('macos/Frameworks/libTruverBridge.dylib').existsSync()) {
      return DynamicLibrary.open('macos/Frameworks/libTruverBridge.dylib');
    }
    if (Platform.isAndroid) return DynamicLibrary.open('libTruverBridge.so');
    if (Platform.isWindows) return DynamicLibrary.open('TruverBridge.dll');
    if (Platform.isMacOS) return DynamicLibrary.open('libTruverBridge.dylib');
    throw UnsupportedError('TruverCore: ${Platform.operatingSystem}');
  }

  final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>) _call;
  final void Function(Pointer<Utf8>) _free;
  final int Function() _now;

  /// Monotonic nanoseconds — the clock of `hostNanos` in beat ticks.
  int nowNanos() => _now();

  dynamic call(String method, [Map<String, dynamic>? params]) {
    final m = method.toNativeUtf8();
    final p = jsonEncode(params ?? const {}).toNativeUtf8();
    try {
      final result = _call(m, p);
      final text = result.toDartString();
      _free(result);
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      if (decoded.containsKey('error')) throw TruverCoreError(decoded['error'] as String);
      return decoded['ok'];
    } finally {
      malloc.free(m);
      malloc.free(p);
    }
  }
}

class TruverCoreError implements Exception {
  TruverCoreError(this.message);
  final String message;
  @override
  String toString() => 'TruverCore: $message';
}

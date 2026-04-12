import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// Thin wrapper around `libzyra_perception.so`.
///
/// Phase 2 scope: just the bootstrap symbols (`zyra_hello`, `zyra_log_version`,
/// `zyra_ncnn_version`). The full detection API (`zyra_engine_*` family,
/// `ZyraDetectionBatch` POD) lands in Phase 4 with ffigen-generated bindings.
///
/// This file is hand-written for now because the surface is tiny and we want
/// Phase 2 to not depend on `dart run ffigen` having been invoked.
class ZyraNative {
  ZyraNative._(ffi.DynamicLibrary lib)
      : _hello = lib
            .lookup<ffi.NativeFunction<ffi.Int32 Function()>>('zyra_hello')
            .asFunction<int Function()>(),
        _logVersion = lib
            .lookup<ffi.NativeFunction<ffi.Void Function()>>(
                'zyra_log_version')
            .asFunction<void Function()>(),
        _ncnnVersion = lib
            .lookup<ffi.NativeFunction<ffi.Pointer<Utf8> Function()>>(
                'zyra_ncnn_version')
            .asFunction<ffi.Pointer<Utf8> Function()>();

  /// Open the shared library and resolve entry points. Throws if the .so is
  /// missing or any symbol fails to bind — both are programmer errors that
  /// must fail loudly rather than silently downgrade.
  factory ZyraNative.open() {
    final ffi.DynamicLibrary lib =
        ffi.DynamicLibrary.open('libzyra_perception.so');
    return ZyraNative._(lib);
  }

  final int Function() _hello;
  final void Function() _logVersion;
  final ffi.Pointer<Utf8> Function() _ncnnVersion;

  /// Returns 42 when the native side is alive. Used only by the bootstrap
  /// smoke test — not on any hot path.
  int hello() => _hello();

  /// Emit a one-line logcat banner with NCNN + OpenCV versions. Call once at
  /// startup.
  void logVersion() => _logVersion();

  /// NCNN version string (static storage, do NOT free).
  String ncnnVersion() => _ncnnVersion().toDartString();
}

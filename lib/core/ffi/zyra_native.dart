import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// Thin wrapper around `libzyra_perception.so`.
///
/// Phase 2 exposed the three bootstrap stubs (`zyra_hello`,
/// `zyra_log_version`, `zyra_ncnn_version`). Phase 3 adds the detector
/// self-test (`zyra_detector_selftest`) so the full C++ pipeline can be
/// validated from Dart before the hot-path FFI (Phase 4) exists.
///
/// Still hand-written — ffigen-generated bindings arrive in Phase 4 with
/// the `ZyraDetectionBatch` POD.
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
            .asFunction<ffi.Pointer<Utf8> Function()>(),
        _detectorSelftest = lib
            .lookup<
                ffi.NativeFunction<
                    ffi.Int32 Function(
                      ffi.Pointer<Utf8>,
                      ffi.Pointer<Utf8>,
                      ffi.Int32,
                      ffi.Pointer<ffi.Int32>,
                      ffi.Pointer<ffi.Float>,
                      ffi.Pointer<ffi.Float>,
                      ffi.Pointer<ffi.Float>,
                      ffi.Pointer<ffi.Int32>,
                    )>>('zyra_detector_selftest')
            .asFunction<
                int Function(
                  ffi.Pointer<Utf8>,
                  ffi.Pointer<Utf8>,
                  int,
                  ffi.Pointer<ffi.Int32>,
                  ffi.Pointer<ffi.Float>,
                  ffi.Pointer<ffi.Float>,
                  ffi.Pointer<ffi.Float>,
                  ffi.Pointer<ffi.Int32>,
                )>();

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
  final int Function(
    ffi.Pointer<Utf8>,
    ffi.Pointer<Utf8>,
    int,
    ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Int32>,
  ) _detectorSelftest;

  /// Returns 42 when the native side is alive. Used only by the bootstrap
  /// smoke test — not on any hot path.
  int hello() => _hello();

  /// Emit a one-line logcat banner with NCNN + OpenCV versions. Call once at
  /// startup.
  void logVersion() => _logVersion();

  /// NCNN version string (static storage, do NOT free).
  String ncnnVersion() => _ncnnVersion().toDartString();

  /// Phase 3 self-test — loads the supplied model and runs one inference on
  /// a synthetic 640×640 grey frame. Throws [ZyraSelftestException] on
  /// failure. Returns timing stats for triage.
  ZyraSelftestResult detectorSelftest({
    required String paramPath,
    required String binPath,
    required bool useVulkan,
  }) {
    final ffi.Pointer<Utf8> paramPtr = paramPath.toNativeUtf8();
    final ffi.Pointer<Utf8> binPtr = binPath.toNativeUtf8();
    final ffi.Pointer<ffi.Int32> count = calloc<ffi.Int32>();
    final ffi.Pointer<ffi.Float> preMs = calloc<ffi.Float>();
    final ffi.Pointer<ffi.Float> infMs = calloc<ffi.Float>();
    final ffi.Pointer<ffi.Float> nmsMs = calloc<ffi.Float>();
    final ffi.Pointer<ffi.Int32> vulkan = calloc<ffi.Int32>();
    try {
      final int rc = _detectorSelftest(
        paramPtr,
        binPtr,
        useVulkan ? 1 : 0,
        count,
        preMs,
        infMs,
        nmsMs,
        vulkan,
      );
      if (rc != 0) {
        throw ZyraSelftestException(rc);
      }
      return ZyraSelftestResult(
        detectionCount: count.value,
        preprocessMs: preMs.value,
        inferMs: infMs.value,
        nmsMs: nmsMs.value,
        vulkanActive: vulkan.value != 0,
      );
    } finally {
      calloc.free(paramPtr);
      calloc.free(binPtr);
      calloc.free(count);
      calloc.free(preMs);
      calloc.free(infMs);
      calloc.free(nmsMs);
      calloc.free(vulkan);
    }
  }
}

/// Stage timings + detection count from `zyra_detector_selftest`.
class ZyraSelftestResult {
  const ZyraSelftestResult({
    required this.detectionCount,
    required this.preprocessMs,
    required this.inferMs,
    required this.nmsMs,
    required this.vulkanActive,
  });

  final int detectionCount;
  final double preprocessMs;
  final double inferMs;
  final double nmsMs;
  final bool vulkanActive;

  @override
  String toString() =>
      'ZyraSelftestResult(dets=$detectionCount, pre=${preprocessMs.toStringAsFixed(2)}ms, '
      'inf=${inferMs.toStringAsFixed(2)}ms, nms=${nmsMs.toStringAsFixed(2)}ms, '
      'vulkan=$vulkanActive)';
}

/// Thrown when `zyra_detector_selftest` returns a non-zero error code.
class ZyraSelftestException implements Exception {
  const ZyraSelftestException(this.code);
  final int code;

  String get reason {
    switch (code) {
      case -1:
        return 'model load failed';
      case -2:
        return 'inference threw';
      case -3:
        return 'null model path';
      default:
        return 'unknown error code $code';
    }
  }

  @override
  String toString() => 'ZyraSelftestException($code: $reason)';
}

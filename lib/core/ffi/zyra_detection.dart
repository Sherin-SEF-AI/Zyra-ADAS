import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' show calloc;

/// Matches `ZYRA_MAX_DETECTIONS` in cpp/include/zyra/ffi_api.h.
const int kZyraMaxDetections = 64;

/// dart:ffi struct mirroring `ZyraDetection` in cpp/include/zyra/ffi_api.h.
/// Layout MUST stay in sync — the native code copies into this buffer by
/// absolute offset.
final class ZyraDetectionStruct extends ffi.Struct {
  @ffi.Float()
  external double x1;
  @ffi.Float()
  external double y1;
  @ffi.Float()
  external double x2;
  @ffi.Float()
  external double y2;
  @ffi.Int32()
  external int classId;
  @ffi.Float()
  external double confidence;
}

/// dart:ffi struct mirroring `ZyraDetectionBatch`. The fixed-size array is
/// declared as an `ffi.Array` so Dart can access each slot as a
/// `ZyraDetectionStruct` without allocation.
final class ZyraDetectionBatchStruct extends ffi.Struct {
  @ffi.Uint64()
  external int frameId;
  @ffi.Double()
  external double timestampMs;
  @ffi.Int32()
  external int count;
  @ffi.Int32()
  external int rotationDeg;
  @ffi.Int32()
  external int origWidth;
  @ffi.Int32()
  external int origHeight;
  @ffi.Float()
  external double preprocessMs;
  @ffi.Float()
  external double inferMs;
  @ffi.Float()
  external double nmsMs;
  @ffi.Int32()
  external int vulkanActive;
  @ffi.Int32()
  external int reserved;
  @ffi.Array(kZyraMaxDetections)
  external ffi.Array<ZyraDetectionStruct> detections;
}

/// Immutable Dart-side detection. Returned by `ZyraEngine.pollDetections()`.
class ZyraDetection {
  const ZyraDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.classId,
    required this.confidence,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Zyra class id (see `lib/core/constants.dart` `kZyraClasses`).
  final int classId;

  /// [0, 1] — model score after NMS + per-class thresholds.
  final double confidence;

  double get width => x2 - x1;
  double get height => y2 - y1;
  double get area => width * height;
}

/// A snapshot of inference output for a single frame. Returned by
/// `ZyraEngine.pollDetections()`.
class ZyraBatch {
  const ZyraBatch({
    required this.frameId,
    required this.timestampMs,
    required this.rotationDeg,
    required this.origWidth,
    required this.origHeight,
    required this.preprocessMs,
    required this.inferMs,
    required this.nmsMs,
    required this.vulkanActive,
    required this.detections,
  });

  final int frameId;
  final double timestampMs;
  final int rotationDeg;
  final int origWidth;
  final int origHeight;
  final double preprocessMs;
  final double inferMs;
  final double nmsMs;
  final bool vulkanActive;
  final List<ZyraDetection> detections;

  double get totalMs => preprocessMs + inferMs + nmsMs;
}

/// Allocate a batch struct buffer suitable for passing to
/// `zyra_engine_poll_detections`. Caller must `calloc.free(ptr)` when done.
ffi.Pointer<ZyraDetectionBatchStruct> allocateBatchBuffer() {
  return calloc<ZyraDetectionBatchStruct>();
}

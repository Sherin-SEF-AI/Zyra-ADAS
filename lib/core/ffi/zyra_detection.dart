import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' show calloc;

/// Matches `ZYRA_MAX_DETECTIONS` in cpp/include/zyra/ffi_api.h.
const int kZyraMaxDetections = 64;

/// Matches `ZYRA_MAX_LANES` in cpp/include/zyra/ffi_api.h.
const int kZyraMaxLanes = 8;

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

/// dart:ffi struct mirroring `ZyraLane` in cpp/include/zyra/ffi_api.h.
final class ZyraLaneStruct extends ffi.Struct {
  @ffi.Float()
  external double x1;
  @ffi.Float()
  external double y1;
  @ffi.Float()
  external double x2;
  @ffi.Float()
  external double y2;
  @ffi.Int32()
  external int side; // 0 = left, 1 = right
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
  // Phase 6 — lane block. Matches the tail of ZyraDetectionBatch in
  // ffi_api.h. Must remain in this order.
  @ffi.Int32()
  external int laneCount;
  @ffi.Float()
  external double laneMs;
  @ffi.Int32()
  external int reserved2;
  @ffi.Array(kZyraMaxLanes)
  external ffi.Array<ZyraLaneStruct> lanes;
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

/// Immutable Dart-side lane segment. Side = 0 for left of the image center,
/// 1 for right. Coords are in ORIGINAL (unrotated) frame space.
class ZyraLane {
  const ZyraLane({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.side,
    required this.confidence,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final int side;
  final double confidence;

  bool get isLeft => side == 0;
  bool get isRight => side == 1;
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
    required this.lanes,
    required this.laneMs,
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
  final List<ZyraLane> lanes;

  /// Wall-clock of the lane stage (classical Hough) in milliseconds.
  final double laneMs;

  double get totalMs => preprocessMs + inferMs + nmsMs + laneMs;
}

/// Allocate a batch struct buffer suitable for passing to
/// `zyra_engine_poll_detections`. Caller must `calloc.free(ptr)` when done.
ffi.Pointer<ZyraDetectionBatchStruct> allocateBatchBuffer() {
  return calloc<ZyraDetectionBatchStruct>();
}

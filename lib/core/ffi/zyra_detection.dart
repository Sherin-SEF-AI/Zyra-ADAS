import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show calloc;

/// Matches `ZYRA_MAX_DETECTIONS` in cpp/include/zyra/ffi_api.h.
const int kZyraMaxDetections = 64;

/// Matches `ZYRA_MAX_LANES` in cpp/include/zyra/ffi_api.h.
const int kZyraMaxLanes = 8;

/// Matches `ZYRA_MAX_LANE_CURVES` (left / right / center).
const int kZyraMaxLaneCurves = 3;

/// Matches `ZYRA_MAX_TRACKS` in cpp/include/zyra/ffi_api.h.
const int kZyraMaxTracks = 32;

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

/// Phase 7 — polynomial lane curve. Mirrors `ZyraLaneCurve` in ffi_api.h.
/// coeffs laid out as [a, b, c] with x = a*y^2 + b*y + c in original image
/// space.
final class ZyraLaneCurveStruct extends ffi.Struct {
  @ffi.Array(3)
  external ffi.Array<ffi.Float> coeffs;
  @ffi.Float()
  external double yTop;
  @ffi.Float()
  external double yBot;
  @ffi.Int32()
  external int side;
  @ffi.Float()
  external double confidence;
  @ffi.Int32()
  external int locked;
  @ffi.Int32()
  external int reserved;
}

/// Phase 7 — Lane Assist snapshot. Mirrors `ZyraLaneAssist` in ffi_api.h.
final class ZyraLaneAssistStruct extends ffi.Struct {
  @ffi.Int32()
  external int ldwState;
  @ffi.Float()
  external double lateralOffsetPx;
  @ffi.Float()
  external double lateralVelocityPxS;
  @ffi.Float()
  external double ttlcS;
  @ffi.Float()
  external double curvaturePx;
  @ffi.Int32()
  external int armed;
  @ffi.Float()
  external double distToLinePx;
  @ffi.Int32()
  external int driftSide;
  // Phase 10 — world-space mirrors. NaN when IPM is not calibrated.
  @ffi.Float()
  external double lateralOffsetM;
  @ffi.Float()
  external double distToLineM;
}

/// Phase 8 — per-object track. Mirrors `ZyraTrack` in ffi_api.h.
final class ZyraTrackStruct extends ffi.Struct {
  @ffi.Int32()
  external int id;
  @ffi.Int32()
  external int classId;
  @ffi.Float()
  external double x1;
  @ffi.Float()
  external double y1;
  @ffi.Float()
  external double x2;
  @ffi.Float()
  external double y2;
  @ffi.Float()
  external double vxPxS;
  @ffi.Float()
  external double vyPxS;
  @ffi.Int32()
  external int ageFrames;
  @ffi.Float()
  external double confidence;
  @ffi.Float()
  external double heightRatePerS;
  // Phase 17 — relative depth (0..1, 0=far).
  @ffi.Float()
  external double depthRelative;
}

/// Phase 8 — FCW snapshot. Mirrors `ZyraFcw` in ffi_api.h.
final class ZyraFcwStruct extends ffi.Struct {
  @ffi.Int32()
  external int state;
  @ffi.Float()
  external double ttcS;
  @ffi.Int32()
  external int criticalTrackId;
  @ffi.Int32()
  external int criticalClassId;
  @ffi.Float()
  external double criticalBboxHFrac;
  // Phase 10 — world-space metrics. +INF when no target or uncalibrated.
  @ffi.Float()
  external double criticalDistanceM;
  @ffi.Float()
  external double rangeRateMps;
  // Phase 17 — relative depth of critical target (0..1).
  @ffi.Float()
  external double criticalDepth;
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
  // Phase 7 — tracker + assist block. Must remain in this order.
  @ffi.Int32()
  external int curveCount;
  @ffi.Float()
  external double trackerMs;
  @ffi.Int32()
  external int reserved3;
  @ffi.Array(kZyraMaxLaneCurves)
  external ffi.Array<ZyraLaneCurveStruct> curves;
  external ZyraLaneAssistStruct assist;
  // Phase 8 — tracker + FCW block. Must remain in this order.
  @ffi.Int32()
  external int trackCount;
  @ffi.Float()
  external double objectTrackerMs;
  @ffi.Float()
  external double fcwMs;
  @ffi.Int32()
  external int reserved4;
  @ffi.Array(kZyraMaxTracks)
  external ffi.Array<ZyraTrackStruct> tracks;
  external ZyraFcwStruct fcw;
  // Phase 11 — ego-state echo.
  @ffi.Float()
  external double egoSpeedMps;
  @ffi.Float()
  external double egoPitchDeg;
  @ffi.Float()
  external double egoYawRateDegS;
  @ffi.Int32()
  external int reserved5;
  // Phase 15 — shadow-mode L2 plan.
  @ffi.Float()
  external double shadowBrakeMps2;
  @ffi.Float()
  external double shadowSteerRad;
  @ffi.Int32()
  external int shadowBrakeActive;
  @ffi.Int32()
  external int shadowSteerActive;
  // Phase 16 — road segmentation block.
  @ffi.Float()
  external double segInferMs;
  @ffi.Float()
  external double segPostMs;
  @ffi.Int32()
  external int segHasDriveable;
  @ffi.Int32()
  external int segMaskW;
  @ffi.Int32()
  external int segMaskH;
  @ffi.Int32()
  external int segReserved;
  @ffi.Array(3600)
  external ffi.Array<ffi.Uint8> segDriveableMask;
  // Phase 17 — depth estimation block.
  @ffi.Float()
  external double depthInferMs;
  @ffi.Float()
  external double depthPostMs;
  @ffi.Int32()
  external int depthValid;
  @ffi.Int32()
  external int depthMapW;
  @ffi.Int32()
  external int depthMapH;
  @ffi.Int32()
  external int depthReserved;
  @ffi.Array(4800)
  external ffi.Array<ffi.Uint8> depthMap;
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

/// Phase 7 — polynomial lane curve: x = a*y^2 + b*y + c. Side is
/// 0 = left, 1 = right, 2 = center (synthesised by the tracker).
class ZyraLaneCurve {
  const ZyraLaneCurve({
    required this.a,
    required this.b,
    required this.c,
    required this.yTop,
    required this.yBot,
    required this.side,
    required this.confidence,
    required this.locked,
  });

  final double a;
  final double b;
  final double c;
  final double yTop;
  final double yBot;
  final int side;
  final double confidence;
  final bool locked;

  bool get isLeft => side == 0;
  bool get isRight => side == 1;
  bool get isCenter => side == 2;

  /// Evaluate x at a given y.
  double xAt(double y) => a * y * y + b * y + c;
}

/// Phase 7 — Lane Departure Warning state.
enum ZyraLdwState { disarmed, armed, warn, alert }

/// Phase 7 — Lane Assist snapshot for the current frame.
class ZyraLaneAssist {
  const ZyraLaneAssist({
    required this.state,
    required this.lateralOffsetPx,
    required this.lateralVelocityPxS,
    required this.ttlcS,
    required this.curvaturePx,
    required this.armed,
    required this.distToLinePx,
    required this.driftSide,
    required this.lateralOffsetM,
    required this.distToLineM,
  });

  final ZyraLdwState state;
  final double lateralOffsetPx;
  final double lateralVelocityPxS;

  /// Time To Lane Crossing. `double.infinity` if safe, low values
  /// indicate imminent departure.
  final double ttlcS;

  /// Signed radius of curvature at the bottom of the image, pixel
  /// units. Positive curves right, negative left. `double.infinity`
  /// when straight.
  final double curvaturePx;

  final bool armed;

  /// Distance to the nearest lane line at the bottom of the image,
  /// in pixels. -1 if unknown.
  final double distToLinePx;

  /// 0 drifting toward left line, 1 toward right, -1 none.
  final int driftSide;

  /// Phase 10 — signed lateral offset in metres. NaN when IPM isn't
  /// calibrated (no vehicle profile geometry pushed yet).
  final double lateralOffsetM;

  /// Phase 10 — distance to nearest lane line in metres. -1 when unknown.
  final double distToLineM;

  bool get isWarning => state == ZyraLdwState.warn;
  bool get isAlert => state == ZyraLdwState.alert;

  /// True when [lateralOffsetM] is a usable (finite, non-NaN) metric.
  bool get hasWorldMetrics =>
      !lateralOffsetM.isNaN && lateralOffsetM.isFinite;
}

/// Phase 8 — smoothed, persistent-ID object track.
class ZyraTrack {
  const ZyraTrack({
    required this.id,
    required this.classId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.vxPxS,
    required this.vyPxS,
    required this.ageFrames,
    required this.confidence,
    required this.heightRatePerS,
    required this.depthRelative,
  });

  final int id;
  final int classId;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double vxPxS;
  final double vyPxS;
  final int ageFrames;
  final double confidence;

  /// Fractional bbox-height expansion rate, in 1/sec. Positive = approaching.
  final double heightRatePerS;

  /// Phase 17 — relative depth (0..1, 0=far, 1=near). 0 when unavailable.
  final double depthRelative;

  double get cx => 0.5 * (x1 + x2);
  double get cy => 0.5 * (y1 + y2);
  double get width => x2 - x1;
  double get height => y2 - y1;
}

/// Phase 8 — FCW state levels.
enum ZyraFcwState { safe, caution, warn, alert }

ZyraFcwState zyraFcwFromInt(int v) {
  switch (v) {
    case 1:
      return ZyraFcwState.caution;
    case 2:
      return ZyraFcwState.warn;
    case 3:
      return ZyraFcwState.alert;
    case 0:
    default:
      return ZyraFcwState.safe;
  }
}

/// Phase 8 — FCW snapshot for the current frame.
class ZyraFcw {
  const ZyraFcw({
    required this.state,
    required this.ttcS,
    required this.criticalTrackId,
    required this.criticalClassId,
    required this.criticalBboxHFrac,
    required this.criticalDistanceM,
    required this.rangeRateMps,
    required this.criticalDepth,
  });

  final ZyraFcwState state;
  final double ttcS;
  final int criticalTrackId;
  final int criticalClassId;
  final double criticalBboxHFrac;

  /// Phase 10 — ground range to the critical target, metres.
  /// `double.infinity` when no target or IPM is uncalibrated.
  final double criticalDistanceM;

  /// Phase 10 — closing rate along the sight line, metres/sec.
  /// Positive = closing (range shrinking). 0 when no target / uncalibrated.
  final double rangeRateMps;

  /// Phase 17 — relative depth of the critical target (0..1, 0=far).
  final double criticalDepth;

  bool get isSafe => state == ZyraFcwState.safe;
  bool get isCaution => state == ZyraFcwState.caution;
  bool get isWarn => state == ZyraFcwState.warn;
  bool get isAlert => state == ZyraFcwState.alert;
  bool get isActive => state != ZyraFcwState.safe;

  /// True when [criticalDistanceM] is usable (finite, with a target).
  bool get hasWorldMetrics =>
      criticalTrackId >= 0 && criticalDistanceM.isFinite;
}

/// Phase 15 — Shadow-mode L2 plan snapshot.
class ZyraShadowPlan {
  const ZyraShadowPlan({
    required this.brakeMps2,
    required this.steerRad,
    required this.brakeActive,
    required this.steerActive,
  });

  /// Required deceleration, m/s² (positive = braking).
  final double brakeMps2;

  /// Desired steering angle, radians (positive = left).
  final double steerRad;

  final bool brakeActive;
  final bool steerActive;

  bool get isActive => brakeActive || steerActive;
}

ZyraLdwState zyraLdwFromInt(int v) {
  switch (v) {
    case 1:
      return ZyraLdwState.armed;
    case 2:
      return ZyraLdwState.warn;
    case 3:
      return ZyraLdwState.alert;
    case 0:
    default:
      return ZyraLdwState.disarmed;
  }
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
    required this.curves,
    required this.trackerMs,
    required this.assist,
    required this.tracks,
    required this.objectTrackerMs,
    required this.fcwMs,
    required this.fcw,
    required this.egoSpeedMps,
    required this.egoPitchDeg,
    required this.egoYawRateDegS,
    required this.shadowPlan,
    required this.segInferMs,
    required this.segPostMs,
    required this.hasDriveable,
    required this.driveableMask,
    required this.driveableMaskW,
    required this.driveableMaskH,
    required this.depthInferMs,
    required this.depthPostMs,
    required this.hasDepth,
    required this.depthMap,
    required this.depthMapW,
    required this.depthMapH,
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

  /// Phase 7 — smoothed polynomial curves (left / right / center).
  final List<ZyraLaneCurve> curves;

  /// Wall-clock of the tracker (poly fit + EMA) stage in milliseconds.
  final double trackerMs;

  /// Phase 7 — Lane Assist snapshot for this frame.
  final ZyraLaneAssist assist;

  /// Phase 8 — persistent-ID tracked objects (confirmed, non-missed only).
  final List<ZyraTrack> tracks;

  /// Wall-clock of the object tracker stage in milliseconds.
  final double objectTrackerMs;

  /// Wall-clock of the FCW stage in milliseconds (bundled into tracker in
  /// current build — kept as a separate field for future independent timing).
  final double fcwMs;

  /// Phase 8 — Forward Collision Warning snapshot for this frame.
  final ZyraFcw fcw;

  /// Phase 11 — ego-state echo: the speed the engine used for gating.
  final double egoSpeedMps;
  final double egoPitchDeg;
  final double egoYawRateDegS;

  /// Phase 15 — shadow-mode L2 plan for this frame.
  final ZyraShadowPlan shadowPlan;

  /// Phase 16 — road segmentation timing.
  final double segInferMs;
  final double segPostMs;

  /// Phase 16 — driveable area mask (80×45, row-major, 1=driveable).
  final bool hasDriveable;
  final Uint8List? driveableMask;
  final int driveableMaskW;
  final int driveableMaskH;

  /// Phase 17 — depth estimation timing.
  final double depthInferMs;
  final double depthPostMs;

  /// Phase 17 — depth map (80×60, row-major, 0=far, 255=near).
  final bool hasDepth;
  final Uint8List? depthMap;
  final int depthMapW;
  final int depthMapH;

  double get egoSpeedKmh => egoSpeedMps * 3.6;

  double get totalMs =>
      preprocessMs +
      inferMs +
      nmsMs +
      laneMs +
      trackerMs +
      objectTrackerMs +
      fcwMs;
}

/// Allocate a batch struct buffer suitable for passing to
/// `zyra_engine_poll_detections`. Caller must `calloc.free(ptr)` when done.
ffi.Pointer<ZyraDetectionBatchStruct> allocateBatchBuffer() {
  return calloc<ZyraDetectionBatchStruct>();
}

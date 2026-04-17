import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'zyra_detection.dart';

// -----------------------------------------------------------------------------
// Native function signatures — hand-written for now. Moves to ffigen-generated
// code once we need the broader surface in later phases.
// -----------------------------------------------------------------------------

typedef _EngineCreateC = ffi.Int64 Function();
typedef _EngineCreateD = int Function();

typedef _EngineDestroyC = ffi.Void Function(ffi.Int64);
typedef _EngineDestroyD = void Function(int);

typedef _EngineLoadModelC = ffi.Int32 Function(
  ffi.Int64,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Int32,
);
typedef _EngineLoadModelD = int Function(
  int,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  int,
);

typedef _EngineWarmupC = ffi.Int32 Function(ffi.Int64);
typedef _EngineWarmupD = int Function(int);

typedef _EngineSetClassThresholdC = ffi.Void Function(
    ffi.Int64, ffi.Int32, ffi.Float);
typedef _EngineSetClassThresholdD = void Function(int, int, double);

typedef _EngineSetFloatC = ffi.Void Function(ffi.Int64, ffi.Float);
typedef _EngineSetFloatD = void Function(int, double);

typedef _EngineSubmitFrameC = ffi.Int32 Function(
  ffi.Int64,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Uint64,
  ffi.Double,
);
typedef _EngineSubmitFrameD = int Function(
  int,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  double,
);

typedef _EnginePollC = ffi.Int32 Function(
    ffi.Int64, ffi.Pointer<ZyraDetectionBatchStruct>);
typedef _EnginePollD = int Function(
    int, ffi.Pointer<ZyraDetectionBatchStruct>);

typedef _EngineAvgFpsC = ffi.Float Function(ffi.Int64);
typedef _EngineAvgFpsD = double Function(int);

typedef _EngineIsVulkanC = ffi.Int32 Function(ffi.Int64);
typedef _EngineIsVulkanD = int Function(int);

typedef _EngineSetCameraGeometryC = ffi.Int32 Function(
    ffi.Int64, ffi.Float, ffi.Float, ffi.Float, ffi.Int32, ffi.Int32);
typedef _EngineSetCameraGeometryD = int Function(
    int, double, double, double, int, int);

typedef _EngineSetEgoStateC = ffi.Int32 Function(
    ffi.Int64, ffi.Float, ffi.Float, ffi.Float);
typedef _EngineSetEgoStateD = int Function(int, double, double, double);

typedef _EngineSetVehicleDynamicsC = ffi.Int32 Function(
    ffi.Int64, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _EngineSetVehicleDynamicsD = int Function(
    int, double, double, double, double, double);

typedef _EngineLoadSegModelC = ffi.Int32 Function(
    ffi.Int64, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32);
typedef _EngineLoadSegModelD = int Function(
    int, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int);

// -----------------------------------------------------------------------------

/// Thin wrapper around the Phase 4 C engine API. Owns an opaque native handle.
///
/// Not thread-safe from multiple Dart isolates. Expect the isolate that owns
/// the engine to drive both `submitFrame` and `pollDetections`. The native
/// side has its own worker thread for inference — Dart just produces and
/// consumes.
class ZyraEngine {
  ZyraEngine._(
    ffi.DynamicLibrary lib, {
    required this.handle,
  })  : _destroy = lib
            .lookup<ffi.NativeFunction<_EngineDestroyC>>('zyra_engine_destroy')
            .asFunction<_EngineDestroyD>(),
        _loadModel = lib
            .lookup<ffi.NativeFunction<_EngineLoadModelC>>(
                'zyra_engine_load_model')
            .asFunction<_EngineLoadModelD>(),
        _warmup = lib
            .lookup<ffi.NativeFunction<_EngineWarmupC>>('zyra_engine_warmup')
            .asFunction<_EngineWarmupD>(),
        _setClassThreshold = lib
            .lookup<ffi.NativeFunction<_EngineSetClassThresholdC>>(
                'zyra_engine_set_class_threshold')
            .asFunction<_EngineSetClassThresholdD>(),
        _setConfThreshold = lib
            .lookup<ffi.NativeFunction<_EngineSetFloatC>>(
                'zyra_engine_set_conf_threshold')
            .asFunction<_EngineSetFloatD>(),
        _setNmsIou = lib
            .lookup<ffi.NativeFunction<_EngineSetFloatC>>(
                'zyra_engine_set_nms_iou')
            .asFunction<_EngineSetFloatD>(),
        _submitFrame = lib
            .lookup<ffi.NativeFunction<_EngineSubmitFrameC>>(
                'zyra_engine_submit_frame')
            .asFunction<_EngineSubmitFrameD>(),
        _pollDetections = lib
            .lookup<ffi.NativeFunction<_EnginePollC>>(
                'zyra_engine_poll_detections')
            .asFunction<_EnginePollD>(),
        _avgFps = lib
            .lookup<ffi.NativeFunction<_EngineAvgFpsC>>(
                'zyra_engine_get_avg_fps')
            .asFunction<_EngineAvgFpsD>(),
        _isVulkanActive = lib
            .lookup<ffi.NativeFunction<_EngineIsVulkanC>>(
                'zyra_engine_is_vulkan_active')
            .asFunction<_EngineIsVulkanD>(),
        _setCameraGeometry = lib
            .lookup<ffi.NativeFunction<_EngineSetCameraGeometryC>>(
                'zyra_engine_set_camera_geometry')
            .asFunction<_EngineSetCameraGeometryD>(),
        _setEgoState = lib
            .lookup<ffi.NativeFunction<_EngineSetEgoStateC>>(
                'zyra_engine_set_ego_state')
            .asFunction<_EngineSetEgoStateD>(),
        _setVehicleDynamics = lib
            .lookup<ffi.NativeFunction<_EngineSetVehicleDynamicsC>>(
                'zyra_engine_set_vehicle_dynamics')
            .asFunction<_EngineSetVehicleDynamicsD>(),
        _loadSegModel = lib
            .lookup<ffi.NativeFunction<_EngineLoadSegModelC>>(
                'zyra_engine_load_seg_model')
            .asFunction<_EngineLoadSegModelD>() {
    _batchBuffer = allocateBatchBuffer();
  }

  /// Create a new native engine and wrap it. Throws if allocation fails.
  factory ZyraEngine.create(ffi.DynamicLibrary lib) {
    final _EngineCreateD create = lib
        .lookup<ffi.NativeFunction<_EngineCreateC>>('zyra_engine_create')
        .asFunction<_EngineCreateD>();
    final int handle = create();
    if (handle == 0) {
      throw StateError('zyra_engine_create returned null handle');
    }
    return ZyraEngine._(lib, handle: handle);
  }

  final int handle;
  final _EngineDestroyD _destroy;
  final _EngineLoadModelD _loadModel;
  final _EngineWarmupD _warmup;
  final _EngineSetClassThresholdD _setClassThreshold;
  final _EngineSetFloatD _setConfThreshold;
  final _EngineSetFloatD _setNmsIou;
  final _EngineSubmitFrameD _submitFrame;
  final _EnginePollD _pollDetections;
  final _EngineAvgFpsD _avgFps;
  final _EngineIsVulkanD _isVulkanActive;
  final _EngineSetCameraGeometryD _setCameraGeometry;
  final _EngineSetEgoStateD _setEgoState;
  final _EngineSetVehicleDynamicsD _setVehicleDynamics;
  final _EngineLoadSegModelD _loadSegModel;

  late final ffi.Pointer<ZyraDetectionBatchStruct> _batchBuffer;
  bool _disposed = false;
  int _lastDrainedFrameId = -1;

  /// Release the underlying native engine + scratch buffer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(handle);
    calloc.free(_batchBuffer);
  }

  /// Load a YOLOv8 NCNN model from filesystem paths. See
  /// `zyra_engine_load_model` in ffi_api.h for error codes.
  void loadModel({
    required String paramPath,
    required String binPath,
    required bool useVulkan,
  }) {
    _ensureAlive();
    final ffi.Pointer<Utf8> p = paramPath.toNativeUtf8();
    final ffi.Pointer<Utf8> b = binPath.toNativeUtf8();
    try {
      final int rc = _loadModel(handle, p, b, useVulkan ? 1 : 0);
      if (rc != 0) {
        throw ZyraEngineException(
            'load_model failed (code $rc) for $paramPath / $binPath');
      }
    } finally {
      calloc.free(p);
      calloc.free(b);
    }
  }

  /// Load the TwinLiteNet road segmentation NCNN model. Runs on CPU by
  /// default (Vulkan reserved for YOLO). See `zyra_engine_load_seg_model`.
  void loadSegModel({
    required String paramPath,
    required String binPath,
    bool useVulkan = false,
  }) {
    _ensureAlive();
    final ffi.Pointer<Utf8> p = paramPath.toNativeUtf8();
    final ffi.Pointer<Utf8> b = binPath.toNativeUtf8();
    try {
      final int rc = _loadSegModel(handle, p, b, useVulkan ? 1 : 0);
      if (rc != 0) {
        throw ZyraEngineException(
            'load_seg_model failed (code $rc) for $paramPath / $binPath');
      }
    } finally {
      calloc.free(p);
      calloc.free(b);
    }
  }

  /// Force-compile Vulkan shaders. Call once after `loadModel` to keep
  /// first-frame latency off the critical path.
  void warmup() {
    _ensureAlive();
    final int rc = _warmup(handle);
    if (rc != 0) {
      throw ZyraEngineException('warmup failed (code $rc)');
    }
  }

  void setClassThreshold(int zyraClassId, double threshold) {
    _ensureAlive();
    _setClassThreshold(handle, zyraClassId, threshold);
  }

  void setConfThreshold(double threshold) {
    _ensureAlive();
    _setConfThreshold(handle, threshold);
  }

  void setNmsIou(double iou) {
    _ensureAlive();
    _setNmsIou(handle, iou);
  }

  /// Phase 10 — push the camera geometry the engine needs to project
  /// pixels onto the road plane. `frameW/H` must be the sensor-native
  /// (landscape) dimensions the worker processes. Throws if the native
  /// call rejects the inputs.
  void setCameraGeometry({
    required double mountHeightM,
    required double pitchDeg,
    required double hfovDeg,
    required int frameW,
    required int frameH,
  }) {
    _ensureAlive();
    final int rc = _setCameraGeometry(
        handle, mountHeightM, pitchDeg, hfovDeg, frameW, frameH);
    if (rc != 0) {
      throw ZyraEngineException('set_camera_geometry failed (code $rc)');
    }
  }

  /// Phase 11 — push ego-vehicle state (GPS speed, IMU pitch, yaw rate)
  /// into the engine for speed-gated warnings. Called at ~1 Hz.
  void setEgoState({
    required double speedMps,
    required double pitchDeg,
    required double yawRateDegPerS,
  }) {
    _ensureAlive();
    _setEgoState(handle, speedMps, pitchDeg, yawRateDegPerS);
  }

  /// Phase 15 — push vehicle dynamics for the shadow-mode L2 planner.
  /// Typically called once on profile selection.
  void setVehicleDynamics({
    required double wheelbaseM,
    required double maxDecelMps2,
    required double comfortDecelMps2,
    required double maxLateralAccelMps2,
    required double steerRateLimitRadPerS,
  }) {
    _ensureAlive();
    _setVehicleDynamics(handle, wheelbaseM, maxDecelMps2, comfortDecelMps2,
        maxLateralAccelMps2, steerRateLimitRadPerS);
  }

  /// Average completed inference FPS over the trailing ~1 s window.
  double get avgFps => _avgFps(handle);

  /// 1 = Vulkan, 0 = CPU, -1 = not loaded.
  int get vulkanActive => _isVulkanActive(handle);

  /// Submit a YUV_420_888 camera frame. Plane pointers must remain valid
  /// for the duration of the call only — the engine copies what it needs
  /// before returning. See `zyra_engine_submit_frame` error codes.
  int submitFrame({
    required ffi.Pointer<ffi.Uint8> y,
    required ffi.Pointer<ffi.Uint8> u,
    required ffi.Pointer<ffi.Uint8> v,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int rotationDeg,
    required int frameId,
    required double timestampMs,
  }) {
    _ensureAlive();
    return _submitFrame(
      handle,
      y,
      u,
      v,
      width,
      height,
      yRowStride,
      uvRowStride,
      uvPixelStride,
      rotationDeg,
      frameId,
      timestampMs,
    );
  }

  /// Submit a contiguous RGB888 image (for tests / synthetic pipelines).
  /// Converts to a synthetic NV21-ish triple-plane layout in Dart and
  /// submits. Not used on the hot path.
  int submitRgbAsGrey({
    required Uint8List grey,
    required int width,
    required int height,
    required int frameId,
    required double timestampMs,
  }) {
    if (grey.length != width * height) {
      throw ArgumentError(
          'grey buffer size (${grey.length}) != $width × $height');
    }
    // Build a YUV_420_888 I420 in native memory: Y (W*H) then U (W*H/4)
    // then V (W*H/4), all filled with the neutral chroma value 128 so the
    // resulting RGB is pure grey.
    final int uvPlane = (width ~/ 2) * (height ~/ 2);
    final int total = width * height + 2 * uvPlane;
    final ffi.Pointer<ffi.Uint8> buf = calloc<ffi.Uint8>(total);
    try {
      buf.asTypedList(width * height).setAll(0, grey);
      (buf + width * height)
          .asTypedList(uvPlane)
          .fillRange(0, uvPlane, 128);
      (buf + (width * height + uvPlane))
          .asTypedList(uvPlane)
          .fillRange(0, uvPlane, 128);
      final ffi.Pointer<ffi.Uint8> yp = buf;
      final ffi.Pointer<ffi.Uint8> up = buf + width * height;
      final ffi.Pointer<ffi.Uint8> vp = buf + (width * height + uvPlane);
      return submitFrame(
        y: yp,
        u: up,
        v: vp,
        width: width,
        height: height,
        yRowStride: width,
        uvRowStride: width ~/ 2,
        uvPixelStride: 1,
        rotationDeg: 0,
        frameId: frameId,
        timestampMs: timestampMs,
      );
    } finally {
      calloc.free(buf);
    }
  }

  /// Read the most recent completed batch. Returns null if no batch has
  /// landed yet, or the same batch has already been returned on a prior
  /// call (deduped by frame id so consumers don't double-render stale
  /// detections).
  ZyraBatch? pollDetections() {
    _ensureAlive();
    final int rc = _pollDetections(handle, _batchBuffer);
    if (rc <= 0) return null;

    final ZyraDetectionBatchStruct b = _batchBuffer.ref;
    if (b.frameId == _lastDrainedFrameId) return null;
    _lastDrainedFrameId = b.frameId;

    final int n = b.count.clamp(0, kZyraMaxDetections);
    final List<ZyraDetection> dets = List<ZyraDetection>.generate(n, (int i) {
      final ZyraDetectionStruct d = b.detections[i];
      return ZyraDetection(
        x1: d.x1,
        y1: d.y1,
        x2: d.x2,
        y2: d.y2,
        classId: d.classId,
        confidence: d.confidence,
      );
    });

    final int lnc = b.laneCount.clamp(0, kZyraMaxLanes);
    final List<ZyraLane> lanes = List<ZyraLane>.generate(lnc, (int i) {
      final ZyraLaneStruct ln = b.lanes[i];
      return ZyraLane(
        x1: ln.x1,
        y1: ln.y1,
        x2: ln.x2,
        y2: ln.y2,
        side: ln.side,
        confidence: ln.confidence,
      );
    });

    final int cc = b.curveCount.clamp(0, kZyraMaxLaneCurves);
    final List<ZyraLaneCurve> curves =
        List<ZyraLaneCurve>.generate(cc, (int i) {
      final ZyraLaneCurveStruct lc = b.curves[i];
      return ZyraLaneCurve(
        a: lc.coeffs[0],
        b: lc.coeffs[1],
        c: lc.coeffs[2],
        yTop: lc.yTop,
        yBot: lc.yBot,
        side: lc.side,
        confidence: lc.confidence,
        locked: lc.locked != 0,
      );
    });

    final ZyraLaneAssistStruct a = b.assist;
    final ZyraLaneAssist assist = ZyraLaneAssist(
      state: zyraLdwFromInt(a.ldwState),
      lateralOffsetPx: a.lateralOffsetPx,
      lateralVelocityPxS: a.lateralVelocityPxS,
      ttlcS: a.ttlcS,
      curvaturePx: a.curvaturePx,
      armed: a.armed != 0,
      distToLinePx: a.distToLinePx,
      driftSide: a.driftSide,
      lateralOffsetM: a.lateralOffsetM,
      distToLineM: a.distToLineM,
    );

    final int tc = b.trackCount.clamp(0, kZyraMaxTracks);
    final List<ZyraTrack> tracks = List<ZyraTrack>.generate(tc, (int i) {
      final ZyraTrackStruct t = b.tracks[i];
      return ZyraTrack(
        id: t.id,
        classId: t.classId,
        x1: t.x1,
        y1: t.y1,
        x2: t.x2,
        y2: t.y2,
        vxPxS: t.vxPxS,
        vyPxS: t.vyPxS,
        ageFrames: t.ageFrames,
        confidence: t.confidence,
        heightRatePerS: t.heightRatePerS,
      );
    });

    final ZyraFcwStruct fs = b.fcw;
    final ZyraFcw fcw = ZyraFcw(
      state: zyraFcwFromInt(fs.state),
      ttcS: fs.ttcS,
      criticalTrackId: fs.criticalTrackId,
      criticalClassId: fs.criticalClassId,
      criticalBboxHFrac: fs.criticalBboxHFrac,
      criticalDistanceM: fs.criticalDistanceM,
      rangeRateMps: fs.rangeRateMps,
    );

    // Extract driveable area mask (3600 bytes) when available.
    Uint8List? driveableMask;
    if (b.segHasDriveable != 0) {
      driveableMask = Uint8List(3600);
      for (int i = 0; i < 3600; i++) {
        driveableMask[i] = b.segDriveableMask[i];
      }
    }

    return ZyraBatch(
      frameId: b.frameId,
      timestampMs: b.timestampMs,
      rotationDeg: b.rotationDeg,
      origWidth: b.origWidth,
      origHeight: b.origHeight,
      preprocessMs: b.preprocessMs,
      inferMs: b.inferMs,
      nmsMs: b.nmsMs,
      vulkanActive: b.vulkanActive != 0,
      detections: dets,
      lanes: lanes,
      laneMs: b.laneMs,
      curves: curves,
      trackerMs: b.trackerMs,
      assist: assist,
      tracks: tracks,
      objectTrackerMs: b.objectTrackerMs,
      fcwMs: b.fcwMs,
      fcw: fcw,
      egoSpeedMps: b.egoSpeedMps,
      egoPitchDeg: b.egoPitchDeg,
      egoYawRateDegS: b.egoYawRateDegS,
      shadowPlan: ZyraShadowPlan(
        brakeMps2: b.shadowBrakeMps2,
        steerRad: b.shadowSteerRad,
        brakeActive: b.shadowBrakeActive != 0,
        steerActive: b.shadowSteerActive != 0,
      ),
      segInferMs: b.segInferMs,
      segPostMs: b.segPostMs,
      hasDriveable: b.segHasDriveable != 0,
      driveableMask: driveableMask,
      driveableMaskW: b.segMaskW,
      driveableMaskH: b.segMaskH,
    );
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('ZyraEngine has been disposed');
    }
  }
}

class ZyraEngineException implements Exception {
  const ZyraEngineException(this.message);
  final String message;

  @override
  String toString() => 'ZyraEngineException: $message';
}

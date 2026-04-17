// C ABI surface for the Zyra perception engine.
//
// Dart binds to these symbols via dart:ffi (see lib/core/ffi/zyra_native.dart
// and lib/core/ffi/zyra_ffi_bindings.dart which is ffigen-generated). Every
// symbol here MUST be marked `extern "C"` and
// `__attribute__((visibility("default")))` so it survives the release build's
// `-fvisibility=hidden` + `--gc-sections` + `--exclude-libs,ALL` flags.
//
// Layering:
//   Phase 2  — bootstrap stubs (zyra_hello, zyra_log_version, zyra_ncnn_version)
//   Phase 3  — detector self-test (zyra_detector_selftest)
//   Phase 4  — hot-path engine surface (zyra_engine_*, ZyraDetectionBatch)

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef ZYRA_API
#define ZYRA_API __attribute__((visibility("default")))
#endif

// --- Phase 2 bootstrap stubs --------------------------------------------

// Returns the magic number 42. Used by Dart at app startup to confirm the
// library loaded and FFI is wired end-to-end. Semantic-free; do not call
// from hot paths.
ZYRA_API int32_t zyra_hello(void);

// Emits one logcat line (tag "Zyra") with the NCNN version, OpenCV build
// version, and ABI the library was compiled for. Useful for triage.
ZYRA_API void zyra_log_version(void);

// Returns the NCNN version string this .so was linked against (e.g.
// "1.0.20250503"). Caller must NOT free. Lifetime is program-wide (static
// storage).
ZYRA_API const char* zyra_ncnn_version(void);

// --- Phase 3 detector self-test -----------------------------------------
//
// Constructs an `NcnnYoloV8Detector`, loads the given model, and runs a
// single inference on a synthetic grey 640×640 RGB image. On success,
// stats are written into the optional output slots (nullable — pass NULL
// to discard) and the function returns 0.
//
// Return codes:
//    0  — ok
//   -1  — load_param / load_model failed
//   -2  — inference threw or failed
//   -3  — param_path / bin_path was null
ZYRA_API int32_t zyra_detector_selftest(const char* param_path,
                                        const char* bin_path,
                                        int32_t use_vulkan,
                                        int32_t* out_detection_count,
                                        float* out_preprocess_ms,
                                        float* out_infer_ms,
                                        float* out_nms_ms,
                                        int32_t* out_vulkan_active);

// --- Phase 4 engine API -------------------------------------------------
//
// The engine owns a single detector + its threading/bounded-queue machinery.
// Intended lifetime: one instance per app, constructed in Dart on the
// drive-screen entry and destroyed on exit. Not thread-safe across
// handles; a single Dart isolate submits frames on the Flutter raster
// thread and another thread (C++-side worker) drains them.
//
// All frame submission is COPY-ON-ENTRY: the Y/U/V plane pointers only need
// to remain valid for the duration of the call. Callers may free / reuse
// the underlying camera buffers immediately after.

// Must match include/zyra/detection.h layout and Dart-side FFI struct.
typedef struct ZyraDetection {
  float x1;
  float y1;
  float x2;
  float y2;
  int32_t class_id;    // Zyra class id (see detection.h comment)
  float confidence;
} ZyraDetection;

// Maximum per-frame detection cap — keeps ZyraDetectionBatch a fixed size
// and avoids Dart-side allocation. Matches kMaxDetectionsPerFrame in
// detector.cpp.
#define ZYRA_MAX_DETECTIONS 64

// Phase 6 — lane-detection output. Coords are in ORIGINAL image space,
// same convention as ZyraDetection, so the Dart overlay can apply the
// same sensor→display rotation it uses for bboxes.
typedef struct ZyraLane {
  float x1;
  float y1;
  float x2;
  float y2;
  int32_t side;        // 0 = left, 1 = right
  float confidence;    // 0..1 — supporting-segment count, softly normalised
} ZyraLane;

#define ZYRA_MAX_LANES 8

// Phase 7 — temporal lane tracker output. Polynomial x = a*y^2 + b*y + c
// over the range [y_top, y_bot] in ORIGINAL image coords.
typedef struct ZyraLaneCurve {
  float coeffs[3];      // [a, b, c]
  float y_top;
  float y_bot;
  int32_t side;         // 0 = left, 1 = right, 2 = center (synthesised)
  float confidence;     // 0..1
  int32_t locked;       // 1 = tracking, 0 = searching (never emitted when 0)
  int32_t reserved;     // 8-byte padding for the next array
} ZyraLaneCurve;

#define ZYRA_MAX_LANE_CURVES 3   // left, right, center

// Phase 7 — Lane Assist state emitted once per frame.
typedef struct ZyraLaneAssist {
  int32_t ldw_state;              // 0 DISARMED, 1 ARMED, 2 WARN, 3 ALERT
  float lateral_offset_px;        // signed — +ve means drifted LEFT
  float lateral_velocity_px_s;    // signed
  float ttlc_s;                   // Time To Lane Crossing; +INF if safe
  float curvature_px;             // signed radius at y_bot; +INF if straight
  int32_t armed;                  // 1 if ldw_state != DISARMED
  float dist_to_line_px;          // nearest line distance at bottom; -1 = n/a
  int32_t drift_side;             // 0 left, 1 right, -1 none
  // Phase 10 — world-space mirrors of the px fields above. NaN when
  // IPM is not calibrated; otherwise SI units.
  float lateral_offset_m;         // signed metres
  float dist_to_line_m;           // metres, -1 when unknown
} ZyraLaneAssist;

// Phase 8 — persistent-ID tracked object. Coords are smoothed (EMA) in
// ORIGINAL image space; velocity is pixels/second.
typedef struct ZyraTrack {
  int32_t id;                // monotonic; 1-based
  int32_t class_id;          // Zyra class
  float x1, y1, x2, y2;
  float vx_px_s, vy_px_s;
  int32_t age_frames;
  float confidence;
  float height_rate_per_s;   // fractional; +ve = approaching camera
  // Phase 17 — relative depth from monocular depth model (0..1, 0=far).
  float depth_relative;
} ZyraTrack;

#define ZYRA_MAX_TRACKS 32

// Phase 8 — Forward Collision Warning snapshot.
typedef struct ZyraFcw {
  int32_t state;                 // 0 SAFE, 1 CAUTION, 2 WARN, 3 ALERT
  float ttc_s;                   // critical target TTC; +INF if none
  int32_t critical_track_id;     // -1 if no target
  int32_t critical_class_id;     // Zyra class; -1 if no target
  float critical_bbox_h_frac;    // critical bbox height / frame height
  // Phase 10 — world-space metrics. +INF when IPM not calibrated or no
  // target. range_rate_mps is +ve for closing (range shrinking).
  float critical_distance_m;
  float range_rate_mps;
  // Phase 17 — relative depth of the critical target (0..1, 0=far).
  float critical_depth;
} ZyraFcw;

typedef struct ZyraDetectionBatch {
  uint64_t frame_id;          // monotonic, set by producer
  double timestamp_ms;        // producer wall-clock (CLOCK_MONOTONIC × 1e3)
  int32_t count;              // number of valid entries in `detections`
  int32_t rotation_deg;       // rotation the producer tagged on the frame
  int32_t orig_width;         // source frame dimensions (pre-rotation)
  int32_t orig_height;
  float preprocess_ms;        // stage timings for the consumer frame
  float infer_ms;
  float nms_ms;
  int32_t vulkan_active;      // 1 if inference ran on Vulkan, 0 for CPU
  int32_t reserved;           // keeps the detections[] block 8-byte aligned
  ZyraDetection detections[ZYRA_MAX_DETECTIONS];
  // --- Phase 6 lane block (appended to preserve field offsets above). ---
  int32_t lane_count;         // number of valid entries in `lanes`
  float lane_ms;              // wall-clock of the lane stage (ms)
  int32_t reserved2;          // 8-byte alignment before the lanes[] block
  ZyraLane lanes[ZYRA_MAX_LANES];
  // --- Phase 7 advanced lane / lane-assist block ------------------------
  // Tracked polynomial curves (left, right, center). `curve_count` valid
  // entries. `tracker_ms` is the wall clock of fit + EMA, separate from
  // the Hough stage timing above so both can be charted.
  int32_t curve_count;
  float tracker_ms;
  int32_t reserved3;
  ZyraLaneCurve curves[ZYRA_MAX_LANE_CURVES];
  ZyraLaneAssist assist;
  // --- Phase 8 tracker + FCW block --------------------------------------
  int32_t track_count;
  float object_tracker_ms;      // ObjectTracker.update wall-clock
  float fcw_ms;                 // FCW.update wall-clock
  int32_t reserved4;
  ZyraTrack tracks[ZYRA_MAX_TRACKS];
  ZyraFcw fcw;
  // --- Phase 11 ego-state echo -------------------------------------------
  float ego_speed_mps;
  float ego_pitch_deg;
  float ego_yaw_rate_deg_s;
  int32_t reserved5;
  // --- Phase 15 shadow-mode L2 plan -------------------------------------
  float shadow_brake_mps2;
  float shadow_steer_rad;
  int32_t shadow_brake_active;
  int32_t shadow_steer_active;
  // --- Phase 16 road segmentation block ----------------------------------
  float seg_infer_ms;
  float seg_post_ms;
  int32_t seg_has_driveable;
  int32_t seg_mask_w;          // 80
  int32_t seg_mask_h;          // 45
  int32_t seg_reserved;
  uint8_t seg_driveable_mask[80 * 45];  // 3600 bytes, row-major, 1=driveable
  // --- Phase 17 depth estimation block ------------------------------------
  float depth_infer_ms;
  float depth_post_ms;
  int32_t depth_valid;
  int32_t depth_map_w;          // 80
  int32_t depth_map_h;          // 60
  int32_t depth_reserved;
  uint8_t depth_map[80 * 60];   // 4800 bytes, row-major, 0=far 255=near
} ZyraDetectionBatch;

// Create a new engine. Returns an opaque handle > 0 on success, or 0 on
// allocation failure. The returned handle is valid until
// `zyra_engine_destroy` is called on it.
ZYRA_API int64_t zyra_engine_create(void);

// Tear down the engine. Idempotent — passing 0 or a stale handle is a
// no-op.
ZYRA_API void zyra_engine_destroy(int64_t handle);

// Load the NCNN YOLOv8 model. `use_vulkan != 0` requests Vulkan compute;
// falls back to CPU if no GPU is present. Returns:
//    0  — ok
//   -1  — bad handle
//   -2  — null path
//   -3  — load_param / load_model failed inside NCNN
ZYRA_API int32_t zyra_engine_load_model(int64_t handle,
                                        const char* param_path,
                                        const char* bin_path,
                                        int32_t use_vulkan);

// Phase 16 — load the TwinLiteNet road segmentation model.
// Same return codes as zyra_engine_load_model.
ZYRA_API int32_t zyra_engine_load_seg_model(int64_t handle,
                                            const char* param_path,
                                            const char* bin_path,
                                            int32_t use_vulkan);

// Phase 17 — load the Depth Anything V2 monocular depth model.
// Runs on CPU (Vulkan reserved for YOLO). Same return codes.
ZYRA_API int32_t zyra_engine_load_depth_model(int64_t handle,
                                              const char* param_path,
                                              const char* bin_path);

// Warmup — run a single inference on a synthetic 640² frame to force
// Vulkan shader compilation / thread-pool init. Recommended once after
// load_model to keep first real-frame latency off the critical path.
// Returns 0 on success, negative on error (see `zyra_engine_load_model`).
ZYRA_API int32_t zyra_engine_warmup(int64_t handle);

// Override per-Zyra-class thresholds. Missing classes keep defaults. Bad
// ids are silently ignored. Safe to call at any time — applies to the
// next submitted frame.
ZYRA_API void zyra_engine_set_class_threshold(int64_t handle,
                                              int32_t zyra_class_id,
                                              float threshold);

// Global confidence floor applied BEFORE per-class thresholds.
ZYRA_API void zyra_engine_set_conf_threshold(int64_t handle, float threshold);

// NMS IoU for large-area boxes. Small-object IoU (0.30) is hard-coded to
// match the desktop reference.
ZYRA_API void zyra_engine_set_nms_iou(int64_t handle, float iou);

// Submit a YUV_420_888 Android camera frame for detection. Plane pointers
// must be valid for the duration of the call only — the engine copies
// what it needs before returning.
//
// The engine uses a bounded (depth-1) queue: the most recent submitted
// frame always wins. If a submission arrives before the previous one
// finishes inference, the previous is silently dropped (realtime
// contract — mirrors the desktop bounded-queue philosophy).
//
// Returns:
//    0  — accepted
//   -1  — bad handle
//   -2  — model not loaded yet
//   -3  — null plane pointers
ZYRA_API int32_t zyra_engine_submit_frame(int64_t handle,
                                          const uint8_t* y,
                                          const uint8_t* u,
                                          const uint8_t* v,
                                          int32_t width,
                                          int32_t height,
                                          int32_t y_row_stride,
                                          int32_t uv_row_stride,
                                          int32_t uv_pixel_stride,
                                          int32_t rotation_deg,
                                          uint64_t frame_id,
                                          double timestamp_ms);

// Copy the most recently produced detection batch into `out`. The same
// batch is returned on every call until a fresher one becomes available —
// callers compare `out->frame_id` to detect change. Non-blocking.
//
// Returns:
//    1  — `out` was populated with a batch (possibly re-read)
//    0  — no batch available yet (engine just created or nothing submitted)
//   -1  — bad handle
//   -2  — null out
ZYRA_API int32_t zyra_engine_poll_detections(int64_t handle,
                                             ZyraDetectionBatch* out);

// Rolling 1-second average of completed-inference FPS. 0.0 until the
// first batch lands.
ZYRA_API float zyra_engine_get_avg_fps(int64_t handle);

// 1 if the model loaded on Vulkan, 0 for CPU, -1 if not loaded.
ZYRA_API int32_t zyra_engine_is_vulkan_active(int64_t handle);

// Phase 10 — install camera geometry so the engine can project image
// pixels onto the road plane. Mount height in metres, pitch in degrees
// (positive = camera tilted up), horizontal FoV in degrees. `frame_w/_h`
// are the sensor-native landscape dimensions the engine processes. Safe
// to call before or after `zyra_engine_load_model`; takes effect from
// the next submitted frame. Returns 0 ok, -1 bad handle, -2 bad inputs.
// Phase 15 — push vehicle dynamics for the shadow-mode L2 planner.
// Typically called once on profile selection. Thread-safe.
ZYRA_API int32_t zyra_engine_set_vehicle_dynamics(int64_t handle,
    float wheelbase_m, float max_decel_mps2, float comfort_decel_mps2,
    float max_lateral_accel_mps2, float steer_rate_limit_rad_s);

// Phase 11 — push ego-vehicle state (GPS speed, IMU pitch, yaw rate) into
// the engine so speed-gated warnings can suppress false positives at low
// speed or during intentional turns. Called at ~1 Hz from the Dart sensor
// layer. Thread-safe. Returns 0 ok, -1 bad handle.
ZYRA_API int32_t zyra_engine_set_ego_state(int64_t handle,
                                            float ego_speed_mps,
                                            float pitch_deg,
                                            float yaw_rate_deg_s);

ZYRA_API int32_t zyra_engine_set_camera_geometry(int64_t handle,
                                                 float mount_h_m,
                                                 float pitch_deg,
                                                 float hfov_deg,
                                                 int32_t frame_w,
                                                 int32_t frame_h);

#ifdef __cplusplus
}  // extern "C"
#endif

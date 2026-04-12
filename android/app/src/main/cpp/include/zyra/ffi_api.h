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
  int32_t reserved;           // keeps the struct 8-byte aligned
  ZyraDetection detections[ZYRA_MAX_DETECTIONS];
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

#ifdef __cplusplus
}  // extern "C"
#endif

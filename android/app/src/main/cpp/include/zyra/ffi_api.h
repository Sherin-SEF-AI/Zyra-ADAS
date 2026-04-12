// C ABI surface for the Zyra perception engine.
//
// Dart binds to these symbols via dart:ffi (see lib/core/ffi/zyra_native.dart).
// Every symbol here MUST be marked `extern "C"` and
// `__attribute__((visibility("default")))` so it survives the release build's
// `-fvisibility=hidden` + `--gc-sections` flags.
//
// PHASE 2 — this file only exposes the minimal bootstrap surface needed to
// prove the .so loads, links, and is callable from Dart. The full detection
// API (`zyra_engine_create`, `zyra_engine_submit_frame`, `ZyraDetectionBatch`,
// ...) lands in Phase 4.

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

#ifdef __cplusplus
}  // extern "C"
#endif

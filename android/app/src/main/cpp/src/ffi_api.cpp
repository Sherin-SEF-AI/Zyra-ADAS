// FFI surface implementation. See zyra/ffi_api.h for the contract.
//
// Phase 2 added the three bootstrap stubs. Phase 3 adds a detector
// self-test so we can validate the full pipeline (load → preprocess →
// inference → NMS) from Dart before wiring the hot-path FFI in Phase 4.

#include "zyra/ffi_api.h"

#include <cstddef>
#include <exception>
#include <vector>

#include <ncnn/platform.h>

#include "zyra/detection.h"
#include "zyra/detector.h"
#include "zyra/logging.h"

extern "C" {

ZYRA_API int32_t zyra_hello(void) {
  return 42;
}

ZYRA_API void zyra_log_version(void) {
  zyra::log_version_banner();
}

ZYRA_API const char* zyra_ncnn_version(void) {
  return NCNN_VERSION_STRING;
}

ZYRA_API int32_t zyra_detector_selftest(const char* param_path,
                                        const char* bin_path,
                                        int32_t use_vulkan,
                                        int32_t* out_detection_count,
                                        float* out_preprocess_ms,
                                        float* out_infer_ms,
                                        float* out_nms_ms,
                                        int32_t* out_vulkan_active) {
  if (param_path == nullptr || bin_path == nullptr) {
    return -3;
  }

  try {
    zyra::NcnnYoloV8Detector det;
    if (!det.load(param_path, bin_path, use_vulkan != 0)) {
      return -1;
    }

    // Synthetic grey 640×640 input — matches the letterbox pad colour so
    // we exercise load + inference + post-processing without relying on
    // a sample asset. A well-trained model returns ~0 detections here,
    // which is fine — the point is to prove the pipeline doesn't fault.
    std::vector<uint8_t> rgb(640 * 640 * 3, 114);
    const auto dets = det.detect_rgb(rgb.data(), 640, 640);

    if (out_detection_count != nullptr) {
      *out_detection_count = static_cast<int32_t>(dets.size());
    }
    if (out_preprocess_ms != nullptr) {
      *out_preprocess_ms = det.last_preprocess_ms();
    }
    if (out_infer_ms != nullptr) {
      *out_infer_ms = det.last_infer_ms();
    }
    if (out_nms_ms != nullptr) {
      *out_nms_ms = det.last_nms_ms();
    }
    if (out_vulkan_active != nullptr) {
      *out_vulkan_active = det.vulkan_active() ? 1 : 0;
    }

    ZYRA_LOGI(
        "selftest ok — dets=%zu preprocess=%.2fms infer=%.2fms nms=%.2fms vulkan=%d",
        dets.size(), det.last_preprocess_ms(), det.last_infer_ms(),
        det.last_nms_ms(), det.vulkan_active() ? 1 : 0);
    return 0;
  } catch (const std::exception& e) {
    ZYRA_LOGE("selftest exception: %s", e.what());
    return -2;
  } catch (...) {
    ZYRA_LOGE("selftest: unknown exception");
    return -2;
  }
}

}  // extern "C"

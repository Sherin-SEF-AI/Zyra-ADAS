// FFI surface implementation. See zyra/ffi_api.h for the contract.
//
// Phase 2: bootstrap stubs.
// Phase 3: detector_selftest.
// Phase 4: zyra_engine_* — thin extern-C shims over PerceptionEngine.

#include "zyra/ffi_api.h"

#include <cstddef>
#include <exception>
#include <vector>

#include <ncnn/platform.h>

#include "zyra/detection.h"
#include "zyra/detector.h"
#include "zyra/engine.h"
#include "zyra/logging.h"

namespace {

inline zyra::PerceptionEngine* as_engine(int64_t handle) {
  return reinterpret_cast<zyra::PerceptionEngine*>(handle);
}

}  // namespace

extern "C" {

// --- Phase 2 --------------------------------------------------------------

ZYRA_API int32_t zyra_hello(void) {
  return 42;
}

ZYRA_API void zyra_log_version(void) {
  zyra::log_version_banner();
}

ZYRA_API const char* zyra_ncnn_version(void) {
  return NCNN_VERSION_STRING;
}

// --- Phase 3 --------------------------------------------------------------

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

    std::vector<uint8_t> rgb(640 * 640 * 3, 114);
    const auto dets = det.detect_rgb(rgb.data(), 640, 640);

    if (out_detection_count != nullptr) {
      *out_detection_count = static_cast<int32_t>(dets.size());
    }
    if (out_preprocess_ms != nullptr) *out_preprocess_ms = det.last_preprocess_ms();
    if (out_infer_ms != nullptr)      *out_infer_ms      = det.last_infer_ms();
    if (out_nms_ms != nullptr)        *out_nms_ms        = det.last_nms_ms();
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

// --- Phase 4 --------------------------------------------------------------

ZYRA_API int64_t zyra_engine_create(void) {
  auto* eng = new (std::nothrow) zyra::PerceptionEngine();
  if (eng == nullptr) {
    ZYRA_LOGE("engine_create: allocation failed");
    return 0;
  }
  return reinterpret_cast<int64_t>(eng);
}

ZYRA_API void zyra_engine_destroy(int64_t handle) {
  if (handle == 0) return;
  delete as_engine(handle);
}

ZYRA_API int32_t zyra_engine_load_model(int64_t handle,
                                        const char* param_path,
                                        const char* bin_path,
                                        int32_t use_vulkan) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  if (param_path == nullptr || bin_path == nullptr) return -2;
  return eng->load_model(param_path, bin_path, use_vulkan != 0);
}

ZYRA_API int32_t zyra_engine_load_seg_model(int64_t handle,
                                            const char* param_path,
                                            const char* bin_path,
                                            int32_t use_vulkan) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  if (param_path == nullptr || bin_path == nullptr) return -2;
  return eng->load_seg_model(param_path, bin_path, use_vulkan != 0);
}

ZYRA_API int32_t zyra_engine_warmup(int64_t handle) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  return eng->warmup();
}

ZYRA_API void zyra_engine_set_class_threshold(int64_t handle,
                                              int32_t zyra_class_id,
                                              float threshold) {
  auto* eng = as_engine(handle);
  if (eng != nullptr) eng->set_class_threshold(zyra_class_id, threshold);
}

ZYRA_API void zyra_engine_set_conf_threshold(int64_t handle, float threshold) {
  auto* eng = as_engine(handle);
  if (eng != nullptr) eng->set_conf_threshold(threshold);
}

ZYRA_API void zyra_engine_set_nms_iou(int64_t handle, float iou) {
  auto* eng = as_engine(handle);
  if (eng != nullptr) eng->set_nms_iou(iou);
}

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
                                          double timestamp_ms) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  return eng->submit(y, u, v, width, height, y_row_stride, uv_row_stride,
                     uv_pixel_stride, rotation_deg, frame_id, timestamp_ms);
}

ZYRA_API int32_t zyra_engine_poll_detections(int64_t handle,
                                             ZyraDetectionBatch* out) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  if (out == nullptr) return -2;
  return eng->poll(out) ? 1 : 0;
}

ZYRA_API float zyra_engine_get_avg_fps(int64_t handle) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return 0.0f;
  return eng->avg_fps();
}

ZYRA_API int32_t zyra_engine_is_vulkan_active(int64_t handle) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  return eng->vulkan_active();
}

ZYRA_API int32_t zyra_engine_set_vehicle_dynamics(int64_t handle,
    float wheelbase_m, float max_decel_mps2, float comfort_decel_mps2,
    float max_lateral_accel_mps2, float steer_rate_limit_rad_s) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  zyra::VehicleDynamics d;
  d.wheelbase_m = wheelbase_m;
  d.max_decel_mps2 = max_decel_mps2;
  d.comfort_decel_mps2 = comfort_decel_mps2;
  d.max_lateral_accel_mps2 = max_lateral_accel_mps2;
  d.steer_rate_limit_rad_s = steer_rate_limit_rad_s;
  eng->set_vehicle_dynamics(d);
  return 0;
}

ZYRA_API int32_t zyra_engine_set_ego_state(int64_t handle,
                                            float ego_speed_mps,
                                            float pitch_deg,
                                            float yaw_rate_deg_s) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  eng->set_ego_state(ego_speed_mps, pitch_deg, yaw_rate_deg_s);
  return 0;
}

ZYRA_API int32_t zyra_engine_set_camera_geometry(int64_t handle,
                                                 float mount_h_m,
                                                 float pitch_deg,
                                                 float hfov_deg,
                                                 int32_t frame_w,
                                                 int32_t frame_h) {
  auto* eng = as_engine(handle);
  if (eng == nullptr) return -1;
  return eng->set_camera_geometry(mount_h_m, pitch_deg, hfov_deg,
                                  frame_w, frame_h);
}

}  // extern "C"

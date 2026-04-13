// Phase 3 — NCNN-backed YOLOv8n detector. One instance per app (held by the
// Riverpod engine provider in Phase 4). All methods run on the caller's
// thread; synchronisation with the camera thread is layered on top in
// Phase 4/5 via an atomic double-buffer.

#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include <ncnn/net.h>

#include "zyra/detection.h"
#include "zyra/frame.h"

namespace zyra {

// Must match lib/core/constants.dart kZyraClasses.length.
constexpr int kZyraClassCount = 9;

class NcnnYoloV8Detector {
 public:
  NcnnYoloV8Detector();
  ~NcnnYoloV8Detector();

  NcnnYoloV8Detector(const NcnnYoloV8Detector&) = delete;
  NcnnYoloV8Detector& operator=(const NcnnYoloV8Detector&) = delete;

  // Load yolov8s.ncnn.param + .bin from real filesystem paths. `use_vulkan`
  // is a request — we fall back to CPU if `ncnn::get_gpu_count() == 0`.
  // Safe to call more than once (rebinds the underlying Net).
  bool load(const std::string& param_path,
            const std::string& bin_path,
            bool use_vulkan);

  // Detect on an Android camera frame. Returns detections in ORIGINAL image
  // coordinate space (pre-rotation — rotation is applied in the UI layer).
  std::vector<Detection> detect(const FrameView& frame);

  // Detect on an RGB888 image. Used by host unit tests and the FFI
  // self-test entry (see ffi_api.cpp::zyra_detector_selftest).
  std::vector<Detection> detect_rgb(const uint8_t* rgb, int width, int height);

  // Global confidence floor — applied before per-class thresholds.
  void set_conf_threshold(float t) { conf_thresh_ = t; }
  void set_nms_iou(float iou) { nms_iou_ = iou; }

  // Override the per-Zyra-class threshold. Out-of-range ids are ignored.
  void set_class_threshold(int zyra_class_id, float t);

  bool loaded() const { return loaded_; }
  bool vulkan_active() const { return vulkan_active_; }
  float last_preprocess_ms() const { return last_preprocess_ms_; }
  float last_infer_ms() const { return last_infer_ms_; }
  float last_nms_ms() const { return last_nms_ms_; }

 private:
  // Shared inner loop — takes a letterboxed 640×640 RGB buffer and returns
  // detections in ORIGINAL image coords.
  std::vector<Detection> detect_letterboxed_rgb_(const uint8_t* rgb640,
                                                 int orig_w, int orig_h,
                                                 float scale,
                                                 int pad_x, int pad_y);

  ncnn::Net net_;
  int input_size_ = 640;
  float conf_thresh_ = 0.25f;
  float nms_iou_ = 0.45f;
  std::array<float, kZyraClassCount> class_thresholds_{};
  bool use_vulkan_ = false;
  bool vulkan_active_ = false;
  bool loaded_ = false;

  // Most recent stage timings, in milliseconds. Consumed by the HUD (Phase 5).
  float last_preprocess_ms_ = 0.0f;
  float last_infer_ms_ = 0.0f;
  float last_nms_ms_ = 0.0f;
};

}  // namespace zyra

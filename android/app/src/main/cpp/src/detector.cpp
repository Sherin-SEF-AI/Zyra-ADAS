// Phase 3 — NCNN YOLOv8n detector wiring. Single class, single model, no
// backend fallback chain (the desktop code has TRT→Ultralytics as a belt-
// and-suspenders setup; on mobile we only have NCNN so keep it straight).

#include "zyra/detector.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <vector>

#include <opencv2/imgproc.hpp>

#include "zyra/internal/nms.h"
#include "zyra/internal/preprocess.h"
#include "zyra/logging.h"

namespace zyra {

namespace {

using steady_clock = std::chrono::steady_clock;

inline float ms_since(steady_clock::time_point t) {
  const auto now = steady_clock::now();
  const auto ns =
      std::chrono::duration_cast<std::chrono::nanoseconds>(now - t).count();
  return static_cast<float>(ns) / 1.0e6f;
}

// COCO id → Zyra id. Mirrors COCO_ID_TO_ZYRA in the desktop yolo_trt.py.
// Returns -1 for classes we do not care about (everything outside the
// small target set). Uses a tight switch — autovectorises to a jump table
// in every compiler we care about.
inline int coco_to_zyra(int coco_id) {
  switch (coco_id) {
    case 0:  return 0;   // person → pedestrian
    case 1:  return 1;   // bicycle
    case 2:  return 2;   // car
    case 3:  return 3;   // motorcycle
    case 5:  return 4;   // bus
    case 7:  return 5;   // truck
    case 9:  return 7;   // traffic light
    case 11: return 8;   // stop sign → traffic_sign
    default: return -1;
  }
}

// Canonical per-Zyra-class thresholds — copied from
// DEFAULT_CLASS_THRESHOLDS in yolo_trt.py. Indexed by Zyra class id.
constexpr std::array<float, kZyraClassCount> kDefaultClassThresholds = {
    0.20f,  // 0 pedestrian
    0.25f,  // 1 bicycle
    0.30f,  // 2 car
    0.25f,  // 3 motorcycle
    0.30f,  // 4 bus
    0.30f,  // 5 truck
    0.25f,  // 6 auto_rickshaw (custom models only)
    0.35f,  // 7 traffic_light
    0.35f,  // 8 traffic_sign
};

// Max detections we surface to Dart in a single frame. Matches the size of
// ZyraDetectionBatch::detections[] (Phase 4 FFI).
constexpr size_t kMaxDetectionsPerFrame = 64;

// YOLOv8n COCO output has 80 classes + 4 box coords = 84 channels.
constexpr int kYoloOutputChannels = 84;
constexpr int kYoloBoxChannels = 4;
constexpr int kYoloNumClasses = kYoloOutputChannels - kYoloBoxChannels;  // 80

}  // namespace

NcnnYoloV8Detector::NcnnYoloV8Detector() {
  class_thresholds_ = kDefaultClassThresholds;
}

NcnnYoloV8Detector::~NcnnYoloV8Detector() {
  net_.clear();
}

void NcnnYoloV8Detector::set_class_threshold(int zyra_class_id, float t) {
  if (zyra_class_id < 0 || zyra_class_id >= kZyraClassCount) return;
  class_thresholds_[static_cast<size_t>(zyra_class_id)] = t;
}

bool NcnnYoloV8Detector::load(const std::string& param_path,
                              const std::string& bin_path,
                              bool use_vulkan) {
  // Re-bind — clear any previous state so repeated loads don't leak GPU
  // allocators. NCNN's Net::clear() is idempotent and cheap when empty.
  net_.clear();
  loaded_ = false;
  vulkan_active_ = false;
  use_vulkan_ = use_vulkan;

  // Options must be set BEFORE load_param / load_model. NCNN copies them
  // into each layer during parsing.
  ncnn::Option opt;
  opt.use_vulkan_compute = use_vulkan && (ncnn::get_gpu_count() > 0);
  opt.num_threads = 4;                  // Big-little aware on modern SoCs
  opt.use_fp16_packed = true;
  opt.use_fp16_storage = true;
  opt.use_fp16_arithmetic = true;
  opt.use_winograd_convolution = true;
  opt.use_sgemm_convolution = true;
  opt.use_packing_layout = true;
  net_.opt = opt;

  if (net_.load_param(param_path.c_str()) != 0) {
    ZYRA_LOGE("load_param failed: %s", param_path.c_str());
    return false;
  }
  if (net_.load_model(bin_path.c_str()) != 0) {
    ZYRA_LOGE("load_model failed: %s", bin_path.c_str());
    net_.clear();
    return false;
  }

  vulkan_active_ = opt.use_vulkan_compute;
  loaded_ = true;
  ZYRA_LOGI("detector loaded — vulkan=%d threads=%d input=%d",
            vulkan_active_ ? 1 : 0, opt.num_threads, input_size_);
  return true;
}

std::vector<Detection> NcnnYoloV8Detector::detect(const FrameView& frame) {
  if (!loaded_) return {};

  const auto t0 = steady_clock::now();
  cv::Mat rgb = internal::yuv420_to_rgb(frame);
  internal::LetterboxMeta meta;
  cv::Mat lb = internal::letterbox_rgb(rgb, input_size_, meta);
  last_preprocess_ms_ = ms_since(t0);

  return detect_letterboxed_rgb_(lb.data, meta.orig_w, meta.orig_h,
                                 meta.scale, meta.pad_x, meta.pad_y);
}

std::vector<Detection> NcnnYoloV8Detector::detect_rgb(const uint8_t* rgb,
                                                     int width, int height) {
  if (!loaded_) return {};

  const auto t0 = steady_clock::now();
  cv::Mat in(height, width, CV_8UC3, const_cast<uint8_t*>(rgb));
  internal::LetterboxMeta meta;
  cv::Mat lb = internal::letterbox_rgb(in, input_size_, meta);
  last_preprocess_ms_ = ms_since(t0);

  return detect_letterboxed_rgb_(lb.data, width, height,
                                 meta.scale, meta.pad_x, meta.pad_y);
}

std::vector<Detection> NcnnYoloV8Detector::detect_letterboxed_rgb_(
    const uint8_t* rgb640, int orig_w, int orig_h,
    float scale, int pad_x, int pad_y) {
  // -- Inference ------------------------------------------------------------
  const auto t_inf = steady_clock::now();

  // NCNN expects channel-first float. from_pixels copies the uint8 buffer
  // into an ncnn::Mat of shape (input_size_, input_size_, 3).
  ncnn::Mat in = ncnn::Mat::from_pixels(
      rgb640, ncnn::Mat::PIXEL_RGB, input_size_, input_size_);

  // Ultralytics preprocessing: divide by 255.0, no mean subtraction.
  static const float kNorm[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
  in.substract_mean_normalize(nullptr, kNorm);

  ncnn::Extractor ex = net_.create_extractor();
  // pnnx's NCNN export for YOLOv8 uses "in0" / "out0" as layer names.
  // These are part of the model graph — if the model is re-exported the
  // names need to match or this call fails silently with empty out.
  ex.input("in0", in);
  ncnn::Mat out;
  if (ex.extract("out0", out) != 0) {
    ZYRA_LOGE("extract out0 failed");
    last_infer_ms_ = ms_since(t_inf);
    return {};
  }
  last_infer_ms_ = ms_since(t_inf);

  // YOLOv8n NCNN layout: h = 84 (4 box + 80 classes), w = 8400 anchors.
  // We access by channel row — see `ncnn::Mat::row(c)` for dims==2.
  if (out.h < kYoloOutputChannels) {
    ZYRA_LOGW("unexpected yolo output shape: h=%d w=%d c=%d",
              out.h, out.w, out.c);
    return {};
  }

  const int num_anchors = out.w;
  const int lb_max = input_size_;  // letterbox coord clamp

  std::vector<Detection> candidates;
  candidates.reserve(256);

  const float* cx_row = out.row(0);
  const float* cy_row = out.row(1);
  const float* w_row  = out.row(2);
  const float* h_row  = out.row(3);

  // -- Post-processing ------------------------------------------------------
  const auto t_nms = steady_clock::now();

  for (int a = 0; a < num_anchors; ++a) {
    // Argmax over the 80 class channels for anchor `a`.
    int best = 0;
    float best_score = out.row(kYoloBoxChannels)[a];
    for (int k = 1; k < kYoloNumClasses; ++k) {
      const float s = out.row(kYoloBoxChannels + k)[a];
      if (s > best_score) {
        best_score = s;
        best = k;
      }
    }
    if (best_score < conf_thresh_) continue;

    const int zyra_id = coco_to_zyra(best);
    if (zyra_id < 0) continue;  // not a class we care about
    if (best_score < class_thresholds_[static_cast<size_t>(zyra_id)]) continue;

    // cxcywh → xyxy in letterbox space.
    const float cx = cx_row[a];
    const float cy = cy_row[a];
    const float w  = w_row[a];
    const float h  = h_row[a];
    float x1 = cx - 0.5f * w;
    float y1 = cy - 0.5f * h;
    float x2 = cx + 0.5f * w;
    float y2 = cy + 0.5f * h;

    // Clamp to letterbox canvas before unwinding (avoids negative areas
    // for boxes straddling the edge of the padded region).
    if (x1 < 0.0f) x1 = 0.0f; else if (x1 > lb_max) x1 = lb_max;
    if (y1 < 0.0f) y1 = 0.0f; else if (y1 > lb_max) y1 = lb_max;
    if (x2 < 0.0f) x2 = 0.0f; else if (x2 > lb_max) x2 = lb_max;
    if (y2 < 0.0f) y2 = 0.0f; else if (y2 > lb_max) y2 = lb_max;

    // Reverse letterbox: subtract pad, divide by scale, clip to original.
    internal::LetterboxMeta m{scale, pad_x, pad_y, orig_w, orig_h};
    internal::unletterbox_box(x1, y1, x2, y2, m);

    if (x2 - x1 <= 1.0f || y2 - y1 <= 1.0f) continue;  // degenerate

    candidates.push_back(Detection{x1, y1, x2, y2, zyra_id, best_score});
  }

  std::vector<Detection> kept = internal::per_class_nms(candidates, nms_iou_);
  if (kept.size() > kMaxDetectionsPerFrame) {
    // Already sorted by confidence desc — just truncate.
    kept.resize(kMaxDetectionsPerFrame);
  }

  last_nms_ms_ = ms_since(t_nms);
  return kept;
}

}  // namespace zyra

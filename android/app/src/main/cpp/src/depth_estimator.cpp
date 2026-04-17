// Phase 17 — Depth Anything V2 (ViT-S) monocular depth estimation.

#include "zyra/depth_estimator.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <numeric>
#include <vector>

#include <ncnn/net.h>
#include <opencv2/imgproc.hpp>

#include "zyra/internal/preprocess.h"
#include "zyra/logging.h"

namespace zyra {

DepthEstimator::DepthEstimator() = default;
DepthEstimator::~DepthEstimator() = default;

bool DepthEstimator::load(const std::string& param_path,
                           const std::string& bin_path) {
  net_.clear();

  ncnn::Option opt;
  opt.use_vulkan_compute = false;  // CPU only — Vulkan reserved for YOLO
  opt.num_threads = 2;
  opt.use_fp16_packed = true;
  opt.use_fp16_storage = true;
  opt.use_fp16_arithmetic = true;
  opt.use_winograd_convolution = true;
  opt.use_sgemm_convolution = true;
  opt.use_packing_layout = true;
  net_.opt = opt;

  if (net_.load_param(param_path.c_str()) != 0) {
    ZYRA_LOGE("DepthEstimator: failed to load param: %s", param_path.c_str());
    return false;
  }
  if (net_.load_model(bin_path.c_str()) != 0) {
    ZYRA_LOGE("DepthEstimator: failed to load model: %s", bin_path.c_str());
    net_.clear();
    return false;
  }

  full_depth_ = cv::Mat::zeros(kInputSize, kInputSize, CV_32FC1);
  loaded_ = true;
  ZYRA_LOGI("DepthEstimator loaded (CPU, 2 threads)");
  return true;
}

DepthResult DepthEstimator::estimate(const FrameView& frame) {
  if (!loaded_) return DepthResult{};

  ++frame_count_;

  // Run inference every 3rd frame — depth changes slowly at driving speeds.
  if (frame_count_ > 1 && (frame_count_ % 3) != 0) {
    return cached_result_;
  }

  cached_result_ = run_inference_(frame);
  return cached_result_;
}

DepthResult DepthEstimator::run_inference_(const FrameView& frame) {
  DepthResult result;

  using Clock = std::chrono::steady_clock;

  // Convert YUV → RGB.
  cv::Mat rgb = internal::yuv420_to_rgb(frame);

  // Resize to 518x518.
  cv::resize(rgb, resized_buf_, cv::Size(kInputSize, kInputSize), 0, 0,
             cv::INTER_LINEAR);

  // Prepare NCNN input with ImageNet normalization:
  // mean = [0.485, 0.456, 0.406] * 255, std = [0.229, 0.224, 0.225] * 255
  ncnn::Mat in = ncnn::Mat::from_pixels(resized_buf_.data,
                                         ncnn::Mat::PIXEL_RGB,
                                         kInputSize, kInputSize);
  const float mean_vals[3] = {123.675f, 116.28f, 103.53f};
  const float norm_vals[3] = {1.0f / 58.395f, 1.0f / 57.12f, 1.0f / 57.375f};
  in.substract_mean_normalize(mean_vals, norm_vals);

  // Inference.
  auto t0 = Clock::now();

  ncnn::Extractor ex = net_.create_extractor();
  ex.input("in0", in);

  ncnn::Mat depth_out;
  ex.extract("out0", depth_out);

  auto t1 = Clock::now();
  result.inference_ms = std::chrono::duration<float, std::milli>(t1 - t0).count();

  // Post-process: the output is [1, H, W] or [H, W] relative inverse depth.
  // Higher values = closer. Normalize to [0, 1].
  const int out_h = depth_out.h;
  const int out_w = depth_out.w;
  const int pixels = out_h * out_w;

  if (pixels <= 0) {
    result.valid = false;
    return result;
  }

  // Find min/max for normalization.
  const float* data = (const float*)depth_out.data;
  float vmin = data[0], vmax = data[0];
  for (int i = 1; i < pixels; ++i) {
    if (data[i] < vmin) vmin = data[i];
    if (data[i] > vmax) vmax = data[i];
  }

  const float range = vmax - vmin;
  const float inv_range = (range > 1e-6f) ? (1.0f / range) : 0.0f;

  // Store normalized full-resolution depth for per-bbox queries.
  full_depth_.create(out_h, out_w, CV_32FC1);
  float* fdst = full_depth_.ptr<float>();
  for (int i = 0; i < pixels; ++i) {
    fdst[i] = (data[i] - vmin) * inv_range;  // 0=far, 1=near
  }
  has_full_depth_ = true;
  last_frame_w_ = frame.width;
  last_frame_h_ = frame.height;

  // Downsample to 80x60 uint8 for FFI transfer.
  downsample_depth_(full_depth_, result.depth_map);
  result.map_w = kDepthMapW;
  result.map_h = kDepthMapH;
  result.valid = true;

  auto t2 = Clock::now();
  result.postprocess_ms =
      std::chrono::duration<float, std::milli>(t2 - t1).count();

  return result;
}

float DepthEstimator::median_depth_in_bbox(float x1, float y1,
                                            float x2, float y2,
                                            int frame_w, int frame_h) const {
  if (!has_full_depth_ || frame_w <= 0 || frame_h <= 0) return 0.0f;

  const int dh = full_depth_.rows;
  const int dw = full_depth_.cols;

  // Map bbox from original frame coords to depth map coords.
  const float sx = static_cast<float>(dw) / frame_w;
  const float sy = static_cast<float>(dh) / frame_h;

  int dx1 = std::max(0, static_cast<int>(x1 * sx));
  int dy1 = std::max(0, static_cast<int>(y1 * sy));
  int dx2 = std::min(dw - 1, static_cast<int>(x2 * sx));
  int dy2 = std::min(dh - 1, static_cast<int>(y2 * sy));

  if (dx2 <= dx1 || dy2 <= dy1) return 0.0f;

  // Collect depth values in the center 60% of the bbox (avoid edges
  // which may include background).
  const int margin_x = (dx2 - dx1) / 5;
  const int margin_y = (dy2 - dy1) / 5;
  dx1 += margin_x; dx2 -= margin_x;
  dy1 += margin_y; dy2 -= margin_y;
  if (dx2 <= dx1 || dy2 <= dy1) return 0.0f;

  std::vector<float> vals;
  vals.reserve((dx2 - dx1) * (dy2 - dy1));

  for (int y = dy1; y <= dy2; ++y) {
    const float* row = full_depth_.ptr<float>(y);
    for (int x = dx1; x <= dx2; ++x) {
      vals.push_back(row[x]);
    }
  }

  if (vals.empty()) return 0.0f;

  // Median via nth_element.
  const size_t mid = vals.size() / 2;
  std::nth_element(vals.begin(), vals.begin() + mid, vals.end());
  return vals[mid];
}

void DepthEstimator::downsample_depth_(const cv::Mat& depth, uint8_t* out) {
  cv::Mat small;
  cv::resize(depth, small, cv::Size(kDepthMapW, kDepthMapH), 0, 0,
             cv::INTER_AREA);

  // Convert [0..1] float to [0..255] uint8.
  for (int i = 0; i < kDepthMapSize; ++i) {
    float v = small.at<float>(i);
    out[i] = static_cast<uint8_t>(std::min(255.0f, std::max(0.0f, v * 255.0f)));
  }
}

}  // namespace zyra

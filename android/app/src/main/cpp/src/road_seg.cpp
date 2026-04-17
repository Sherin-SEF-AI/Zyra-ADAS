// Phase 16 — TwinLiteNet road segmentation implementation.

#include "zyra/road_seg.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <vector>

#include <ncnn/net.h>
#include <opencv2/imgproc.hpp>

#include "zyra/internal/preprocess.h"
#include "zyra/logging.h"

namespace zyra {

RoadSegmentor::RoadSegmentor() = default;
RoadSegmentor::~RoadSegmentor() = default;

bool RoadSegmentor::load(const std::string& param_path,
                          const std::string& bin_path,
                          bool use_vulkan) {
  net_.clear();

  ncnn::Option opt;
  opt.use_vulkan_compute = use_vulkan && (ncnn::get_gpu_count() > 0);
  opt.num_threads = 2;  // Leave cores for YOLO
  opt.use_fp16_packed = true;
  opt.use_fp16_storage = true;
  opt.use_fp16_arithmetic = true;
  opt.use_winograd_convolution = true;
  opt.use_sgemm_convolution = true;
  opt.use_packing_layout = true;
  net_.opt = opt;

  if (net_.load_param(param_path.c_str()) != 0) {
    ZYRA_LOGE("RoadSegmentor: failed to load param: %s", param_path.c_str());
    return false;
  }
  if (net_.load_model(bin_path.c_str()) != 0) {
    ZYRA_LOGE("RoadSegmentor: failed to load model: %s", bin_path.c_str());
    net_.clear();
    return false;
  }

  loaded_ = true;
  vulkan_active_ = opt.use_vulkan_compute;
  ZYRA_LOGI("RoadSegmentor loaded (vulkan=%d)", vulkan_active_ ? 1 : 0);
  return true;
}

RoadSegResult RoadSegmentor::segment(const FrameView& frame) {
  RoadSegResult result;
  if (!loaded_) return result;

  using Clock = std::chrono::steady_clock;

  // --- Convert YUV to RGB ---
  cv::Mat rgb = internal::yuv420_to_rgb(frame);

  // --- Resize to 256x256 ---
  cv::resize(rgb, resized_buf_, cv::Size(kInputSize, kInputSize), 0, 0,
             cv::INTER_LINEAR);

  // --- Prepare NCNN input: RGB [0,1] normalization ---
  ncnn::Mat in = ncnn::Mat::from_pixels(resized_buf_.data,
                                         ncnn::Mat::PIXEL_RGB,
                                         kInputSize, kInputSize);
  // TwinLiteNet normalizes to [0,1]: divide by 255.
  const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
  in.substract_mean_normalize(nullptr, norm_vals);

  // --- Run inference ---
  auto t0 = Clock::now();

  ncnn::Extractor ex = net_.create_extractor();
  ex.input("in0", in);

  ncnn::Mat da_out;  // driveable area: [2, 256, 256]
  ex.extract("out0", da_out);

  auto t1 = Clock::now();
  result.inference_ms = std::chrono::duration<float, std::milli>(t1 - t0).count();

  // --- Post-process: argmax channel 1 > channel 0 → binary mask ---
  cv::Mat da_mask(kInputSize, kInputSize, CV_8UC1);
  const float* ch0 = da_out.channel(0);
  const float* ch1 = da_out.channel(1);
  for (int i = 0; i < kInputSize * kInputSize; ++i) {
    da_mask.data[i] = (ch1[i] > ch0[i]) ? 255 : 0;
  }

  // Morphological closing to smooth jagged mask edges.
  cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
  cv::morphologyEx(da_mask, da_mask, cv::MORPH_CLOSE, kernel);

  // Check if any driveable area was found.
  int driveable_px = cv::countNonZero(da_mask);
  result.has_driveable = driveable_px > (kInputSize * kInputSize / 20);  // >5%

  if (result.has_driveable) {
    extract_boundaries_(da_mask, frame.width, frame.height,
                        result.synthetic_lanes);
    downsample_mask_(da_mask, result.driveable_mask);
  }

  auto t2 = Clock::now();
  result.postprocess_ms =
      std::chrono::duration<float, std::milli>(t2 - t1).count();

  return result;
}

void RoadSegmentor::extract_boundaries_(const cv::Mat& da_mask_256,
                                         int orig_w, int orig_h,
                                         std::vector<Lane>& out_lanes) {
  // Scale factors from 256x256 mask to original frame coordinates.
  const float sx = static_cast<float>(orig_w) / kInputSize;
  const float sy = static_cast<float>(orig_h) / kInputSize;

  // Scan from bottom of mask upward, sampling every 8 rows (~32 samples).
  // For each row, find leftmost and rightmost driveable pixel.
  struct BoundaryPoint {
    float x, y;
  };
  std::vector<BoundaryPoint> left_pts, right_pts;

  const int step = 8;
  const int start_y = kInputSize - 1;
  const int end_y = kInputSize / 4;  // Don't scan above top quarter (sky)

  for (int y = start_y; y >= end_y; y -= step) {
    const uint8_t* row = da_mask_256.ptr<uint8_t>(y);
    int left_x = -1, right_x = -1;

    for (int x = 0; x < kInputSize; ++x) {
      if (row[x] > 0) {
        if (left_x < 0) left_x = x;
        right_x = x;
      }
    }

    if (left_x >= 0 && right_x > left_x) {
      // Convert to original frame coordinates.
      left_pts.push_back({left_x * sx, y * sy});
      right_pts.push_back({right_x * sx, y * sy});
    }
  }

  // Generate synthetic Lane segments from consecutive boundary points.
  for (size_t i = 0; i + 1 < left_pts.size(); ++i) {
    out_lanes.push_back(Lane{
        left_pts[i].x, left_pts[i].y,
        left_pts[i + 1].x, left_pts[i + 1].y,
        0,     // side = left
        0.85f  // confidence
    });
  }
  for (size_t i = 0; i + 1 < right_pts.size(); ++i) {
    out_lanes.push_back(Lane{
        right_pts[i].x, right_pts[i].y,
        right_pts[i + 1].x, right_pts[i + 1].y,
        1,     // side = right
        0.85f  // confidence
    });
  }
}

void RoadSegmentor::downsample_mask_(const cv::Mat& da_mask_256,
                                      uint8_t* out) {
  cv::Mat small;
  cv::resize(da_mask_256, small, cv::Size(kSegMaskW, kSegMaskH), 0, 0,
             cv::INTER_NEAREST);
  // Threshold: 128+ → 1, else 0.
  for (int i = 0; i < kSegMaskSize; ++i) {
    out[i] = small.data[i] >= 128 ? 1 : 0;
  }
}

}  // namespace zyra

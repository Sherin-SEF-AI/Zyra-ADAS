// Phase 16 — TwinLiteNet road segmentation.
//
// Replaces the classical Hough lane detector with a lightweight neural
// network (TwinLiteNet, ~0.4M params) that outputs two binary masks:
//   1. Driveable area — the road surface the vehicle can drive on.
//   2. Lane lines — painted lane markings (when visible).
//
// The driveable area mask is far more useful on Indian roads where lane
// markings are often absent or faded. Boundary points extracted from the
// mask edges are converted to synthetic Lane segments that feed the
// existing LaneTracker pipeline unchanged.
//
// Accuracy: confidence-weighted argmax, lane line mask reinforcement,
//           largest connected component, temporal EMA smoothing.
// Performance: runs every other frame, reuses previous result on skips.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <ncnn/net.h>
#include <opencv2/core.hpp>

#include "zyra/frame.h"
#include "zyra/lane.h"

namespace zyra {

// Fixed mask dimensions for FFI transfer.
static constexpr int kSegMaskW = 80;
static constexpr int kSegMaskH = 45;
static constexpr int kSegMaskSize = kSegMaskW * kSegMaskH;

struct RoadSegResult {
  uint8_t driveable_mask[kSegMaskSize]{};
  int mask_w = kSegMaskW;
  int mask_h = kSegMaskH;
  std::vector<Lane> synthetic_lanes;
  bool has_driveable = false;
  float inference_ms = 0.0f;
  float postprocess_ms = 0.0f;
};

class RoadSegmentor {
 public:
  RoadSegmentor();
  ~RoadSegmentor();

  bool load(const std::string& param_path, const std::string& bin_path,
            bool use_vulkan);
  bool loaded() const { return loaded_; }

  // Run segmentation on a camera frame. Produces a downsampled driveable
  // area mask and synthetic Lane segments for the LaneTracker.
  // Internally runs every other call, returning the cached result on skips.
  RoadSegResult segment(const FrameView& frame);

 private:
  ncnn::Net net_;
  bool loaded_ = false;
  bool vulkan_active_ = false;
  static constexpr int kInputSize = 256;
  static constexpr int kInputPixels = kInputSize * kInputSize;

  // Reusable buffers to avoid per-frame heap churn.
  cv::Mat resized_buf_;
  cv::Mat da_mask_buf_;           // 256x256 CV_8UC1
  cv::Mat ll_mask_buf_;           // 256x256 CV_8UC1 lane lines
  cv::Mat morph_kernel_open_;     // pre-allocated 3x3 ellipse
  cv::Mat morph_kernel_close_;    // pre-allocated 5x5 ellipse
  cv::Mat ema_mask_;              // temporal EMA accumulator (CV_32FC1)
  bool ema_initialized_ = false;

  // Frame-skip: run inference every other frame, reuse cached result.
  uint64_t frame_count_ = 0;
  RoadSegResult cached_result_;

  // Run the actual NCNN inference + post-processing.
  RoadSegResult run_inference_(const FrameView& frame);

  // Extract the largest connected component from the binary mask.
  void keep_largest_component_(cv::Mat& mask);

  // Extract left/right boundary polylines from the driveable area mask
  // and convert to synthetic Lane segments in original frame coordinates.
  // Scans from center outward for more robust boundary detection.
  void extract_boundaries_(const cv::Mat& da_mask_256, int orig_w, int orig_h,
                           std::vector<Lane>& out_lanes);

  // Downsample the 256x256 binary mask to kSegMaskW x kSegMaskH.
  void downsample_mask_(const cv::Mat& da_mask_256, uint8_t* out);
};

}  // namespace zyra

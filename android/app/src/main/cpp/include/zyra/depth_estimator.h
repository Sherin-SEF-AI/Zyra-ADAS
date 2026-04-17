// Phase 17 — Depth Anything V2 (ViT-S) monocular depth estimation.
//
// Provides relative depth map (higher = closer) for:
//   1. FCW enhancement — per-object median depth for depth-rate TTC
//   2. Depth visualization screen — downsampled uint8 depth map via FFI
//
// Runs on CPU (2 threads), parallel with YOLO on Vulkan GPU.
// Inference: ~200-350ms at 518x518 on Snapdragon 665.
// Frame-skipped to every 3rd frame, cached result reused on skips.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <ncnn/net.h>
#include <opencv2/core.hpp>

#include "zyra/frame.h"

namespace zyra {

// Downsampled depth map for FFI transfer: 80x60 uint8 (0=far, 255=near).
static constexpr int kDepthMapW = 80;
static constexpr int kDepthMapH = 60;
static constexpr int kDepthMapSize = kDepthMapW * kDepthMapH;

struct DepthResult {
  uint8_t depth_map[kDepthMapSize]{};  // 0..255, normalized relative depth
  int map_w = kDepthMapW;
  int map_h = kDepthMapH;
  float inference_ms = 0.0f;
  float postprocess_ms = 0.0f;
  bool valid = false;
};

class DepthEstimator {
 public:
  DepthEstimator();
  ~DepthEstimator();

  bool load(const std::string& param_path, const std::string& bin_path);
  bool loaded() const { return loaded_; }

  // Run depth estimation. Frame-skips internally (every 3rd call).
  DepthResult estimate(const FrameView& frame);

  // Query median relative depth [0..1] for a bounding box region.
  // Uses the full-resolution internal depth buffer. Returns 0 if invalid.
  float median_depth_in_bbox(float x1, float y1, float x2, float y2,
                             int frame_w, int frame_h) const;

 private:
  ncnn::Net net_;
  bool loaded_ = false;
  static constexpr int kInputSize = 518;

  // Full-resolution depth retained for per-bbox queries.
  cv::Mat full_depth_;   // CV_32FC1, kInputSize x kInputSize
  bool has_full_depth_ = false;
  int last_frame_w_ = 0;
  int last_frame_h_ = 0;

  // Frame skip: run every 3rd frame.
  uint64_t frame_count_ = 0;
  DepthResult cached_result_;

  // Reusable buffers.
  cv::Mat resized_buf_;

  DepthResult run_inference_(const FrameView& frame);
  void downsample_depth_(const cv::Mat& depth, uint8_t* out);
};

}  // namespace zyra

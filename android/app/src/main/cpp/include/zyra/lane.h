// Phase 6 — classical CV lane detector.
//
// Consumes a Y-plane (grayscale) view of the camera frame and produces a
// small list of line-segment lanes grouped as left/right of the image
// centerline. Designed to be swappable with a future NCNN-based backend
// (UFLDv2 / CLRNet) without changing the FFI surface.
//
// Pipeline:
//   1. Downsample Y to ~ (processing_width × processing_height).
//   2. Gaussian blur 5×5.
//   3. Canny edges.
//   4. Trapezoidal region-of-interest mask (lower half of frame).
//   5. Probabilistic Hough line transform.
//   6. Slope filter — lanes are neither vertical nor near-horizontal.
//   7. Split by slope sign, weighted-average per side, scale back to
//      original coords.
//
// Cost: ~5-8 ms on a 720p frame downsampled to 480×270 with NEON-enabled
// OpenCV Mobile. Well inside our per-frame inference budget so it runs
// sequentially in the engine worker after YOLO.

#pragma once

#include <cstdint>
#include <vector>

namespace zyra {

struct Lane {
  // Endpoints in ORIGINAL (unrotated) image coordinates so the UI overlay
  // can apply the same rotation as it does for detection bboxes.
  float x1;
  float y1;
  float x2;
  float y2;
  int side;          // 0 = left, 1 = right
  float confidence;  // count of supporting Hough segments, normalised 0..1
};

class HoughLaneDetector {
 public:
  HoughLaneDetector();

  // Detect lanes on a Y plane. `y_row_stride` may exceed `width` to account
  // for hardware alignment padding. Output coords are in the original frame
  // (pre-rotation), matching the detector's convention.
  std::vector<Lane> detect(const uint8_t* y, int width, int height,
                           int y_row_stride);

  // Tuning. Defaults match a phone mounted ~1.2 m above ground, tilted
  // slightly down, pointing forward — the typical dashboard setup.
  void set_canny(float low, float high) { canny_low_ = low; canny_high_ = high; }
  void set_hough(int threshold, int min_line_len, int max_line_gap) {
    hough_threshold_ = threshold;
    min_line_length_ = min_line_len;
    max_line_gap_ = max_line_gap;
  }

  float last_ms() const { return last_ms_; }

 private:
  int processing_width_ = 480;
  int processing_height_ = 270;  // 16:9 target; gets clipped to input aspect

  // Canny hysteresis thresholds (grayscale 0..255 scale).
  float canny_low_ = 50.0f;
  float canny_high_ = 150.0f;

  // HoughLinesP tuning.
  int hough_threshold_ = 35;
  int min_line_length_ = 30;
  int max_line_gap_ = 20;

  // Slope gate — reject near-horizontal and near-vertical segments.
  // abs(dy / dx) outside [min_abs_slope_, max_abs_slope_] is dropped.
  float min_abs_slope_ = 0.4f;
  float max_abs_slope_ = 4.0f;

  float last_ms_ = 0.0f;
};

}  // namespace zyra

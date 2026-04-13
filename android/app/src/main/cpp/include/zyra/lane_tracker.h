// Phase 7 — temporal lane tracker.
//
// Consumes the per-frame Hough line segments from HoughLaneDetector and
// turns them into smooth, persistent left/right/center lane curves.
//
// Pipeline per frame:
//   1. Bucket incoming Hough segments by side (already tagged by the
//      detector).
//   2. Fit a 2nd-order polynomial x = a*y^2 + b*y + c to each side's
//      pooled endpoint samples, least-squares.
//   3. EMA-smooth the coefficients across frames (alpha tuned for ~0.5s
//      response time at 15-30 fps).
//   4. Derive a center polynomial as the per-coefficient average of
//      left and right when both are locked; otherwise the last known
//      center with decaying confidence.
//   5. Emit TrackedLane {coeffs, y range, confidence, locked}.
//
// Why polynomial rather than straight: real roads curve. Evaluating the
// polynomial at N y-values and drawing the resulting path gives smooth
// overlays that match real lane markings, not the chunky straight-line
// approximations of Phase 6.
//
// Why EMA rather than Kalman: EMA is O(1) per frame, needs no state
// covariance, and its parameters are driver-intuitive ("how many frames
// until the curve catches up"). Kalman earns its keep when we start
// fusing IMU data in Phase 7+.

#pragma once

#include <cstdint>
#include <vector>

#include "zyra/lane.h"

namespace zyra {

struct TrackedLane {
  // x = coeffs[0]*y^2 + coeffs[1]*y + coeffs[2]  (ORIGINAL image space)
  float coeffs[3];
  // y range over which this curve is supported (pixels, pre-rotation).
  float y_top;
  float y_bot;
  int side;          // 0 = left, 1 = right, 2 = center (synthesised)
  float confidence;  // 0..1 — fused inlier count + age
  int locked;        // 0 = searching / 1 = tracking
};

class LaneTracker {
 public:
  LaneTracker();

  // Update from the current frame's Hough segments. frame_width/height
  // are the ORIGINAL image dims (before rotation) — we need the width to
  // anchor the synthesised center curve if one side is missing.
  void update(const std::vector<Lane>& hough, int frame_width,
              int frame_height);

  // Returns up to 3 tracked curves: left (side=0), right (side=1),
  // center (side=2). Sides absent this frame are omitted.
  const std::vector<TrackedLane>& curves() const { return curves_; }

  // Instantaneous lateral offset of frame-center from the synthesised
  // lane center at the bottom of the image, in pixels. Positive = frame
  // center is right of the lane center (driver has drifted left). 0 if
  // center not locked.
  float lateral_offset_px() const { return lateral_offset_px_; }

  // Rate-of-change of lateral_offset_px across the last ~200 ms
  // (px/second in ORIGINAL image coords). Signed, with the same sign
  // convention as lateral_offset_px. 0 if insufficient history.
  float lateral_velocity_px_s() const { return lateral_velocity_px_s_; }

  // Radius of curvature in ORIGINAL image pixels at y = y_bot, using the
  // center curve's polynomial. Positive = curve bends right, negative =
  // left. +INF when straight (capped at 1e6 for FFI safety).
  float curvature_px() const { return curvature_px_; }

  float last_ms() const { return last_ms_; }

  // Tuning knobs. Defaults live in the cpp.
  void set_ema_alpha(float a);
  void set_lock_thresholds(int hits_to_lock, int misses_to_lose);
  void set_min_samples_per_fit(int n) { min_samples_per_fit_ = n; }

 private:
  // One side's running state.
  struct SideState {
    bool has_prev = false;
    float coeffs[3] = {0, 0, 0};
    float y_top = 0, y_bot = 0;
    int hit_streak = 0;
    int miss_streak = 0;
    bool locked = false;
    float confidence = 0.0f;
  };

  bool fit_poly2_(const std::vector<Lane>& segments, int side,
                  float out_coeffs[3], float* out_y_top, float* out_y_bot,
                  int* out_samples);
  void ema_(SideState& s, const float in_coeffs[3], float in_y_top,
            float in_y_bot);
  void decay_(SideState& s);

  SideState left_{};
  SideState right_{};
  SideState center_{};
  bool has_center_history_ = false;

  std::vector<TrackedLane> curves_;

  // Sliding window of center x @ y_bot samples, timestamped (ms), for
  // lateral velocity estimation.
  struct OffsetSample {
    double t_ms;
    float offset_px;
  };
  std::vector<OffsetSample> offset_history_;

  float lateral_offset_px_ = 0.0f;
  float lateral_velocity_px_s_ = 0.0f;
  float curvature_px_ = 0.0f;

  // Tuning.
  float ema_alpha_ = 0.35f;            // higher = snappier, lower = smoother
  int hits_to_lock_ = 3;
  int misses_to_lose_ = 6;
  int min_samples_per_fit_ = 4;        // below this, fall back to linear
  float history_window_ms_ = 250.0f;   // for lateral velocity
  float max_fit_residual_px_ = 40.0f;  // guard against wild polynomials

  float last_ms_ = 0.0f;
};

}  // namespace zyra

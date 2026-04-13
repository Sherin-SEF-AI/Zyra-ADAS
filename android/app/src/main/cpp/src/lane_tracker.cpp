// Phase 7 — LaneTracker implementation. See include/zyra/lane_tracker.h.
//
// Uses OpenCV's cv::solve for the least-squares polynomial fit. Keeping
// the solver inside the lane stage (not leaking into detector/nms)
// isolates the numerics from the rest of the pipeline.

#include "zyra/lane_tracker.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>

#include <opencv2/core.hpp>

#include "zyra/logging.h"

namespace zyra {

namespace {

using clk = std::chrono::steady_clock;

inline double now_ms() {
  const auto d = clk::now().time_since_epoch();
  return std::chrono::duration<double, std::milli>(d).count();
}

inline float eval_poly_(const float c[3], float y) {
  return c[0] * y * y + c[1] * y + c[2];
}

// Residual between fitted curve and the samples used to fit it. We use
// this as a sanity check — if the road is too noisy (other traffic,
// shadows), the fit can blow up and we'd rather emit "no lane" than
// a spurious curve.
float mean_abs_residual_(const std::vector<Lane>& segments, int side,
                         const float coeffs[3]) {
  double sum = 0.0;
  int n = 0;
  for (const auto& s : segments) {
    if (s.side != side) continue;
    const float ex1 = eval_poly_(coeffs, s.y1);
    const float ex2 = eval_poly_(coeffs, s.y2);
    sum += std::abs(ex1 - s.x1);
    sum += std::abs(ex2 - s.x2);
    n += 2;
  }
  if (n == 0) return std::numeric_limits<float>::infinity();
  return static_cast<float>(sum / n);
}

}  // namespace

LaneTracker::LaneTracker() { curves_.reserve(3); }

void LaneTracker::set_ema_alpha(float a) {
  ema_alpha_ = std::clamp(a, 0.05f, 1.0f);
}

void LaneTracker::set_lock_thresholds(int hits_to_lock, int misses_to_lose) {
  hits_to_lock_ = std::max(1, hits_to_lock);
  misses_to_lose_ = std::max(1, misses_to_lose);
}

void LaneTracker::decay_(SideState& s) {
  s.hit_streak = 0;
  s.miss_streak = std::min(misses_to_lose_ + 4, s.miss_streak + 1);
  s.confidence = std::max(0.0f, s.confidence - 0.15f);
  if (s.miss_streak >= misses_to_lose_) {
    s.locked = false;
    s.has_prev = false;
  }
}

void LaneTracker::ema_(SideState& s, const float in_coeffs[3],
                       float in_y_top, float in_y_bot) {
  const float a = ema_alpha_;
  if (!s.has_prev) {
    for (int i = 0; i < 3; ++i) s.coeffs[i] = in_coeffs[i];
    s.y_top = in_y_top;
    s.y_bot = in_y_bot;
    s.has_prev = true;
  } else {
    for (int i = 0; i < 3; ++i) {
      s.coeffs[i] = (1.0f - a) * s.coeffs[i] + a * in_coeffs[i];
    }
    s.y_top = (1.0f - a) * s.y_top + a * in_y_top;
    s.y_bot = (1.0f - a) * s.y_bot + a * in_y_bot;
  }
  s.miss_streak = 0;
  s.hit_streak = std::min(hits_to_lock_ + 4, s.hit_streak + 1);
  if (s.hit_streak >= hits_to_lock_) s.locked = true;
  s.confidence = std::min(1.0f, s.confidence + 0.2f);
}

bool LaneTracker::fit_poly2_(const std::vector<Lane>& segments, int side,
                             float out_coeffs[3], float* out_y_top,
                             float* out_y_bot, int* out_samples) {
  // Collect (y, x) samples from both endpoints of every same-side segment.
  std::vector<cv::Point2f> pts;
  pts.reserve(segments.size() * 2);
  float y_top = std::numeric_limits<float>::infinity();
  float y_bot = -std::numeric_limits<float>::infinity();
  for (const auto& s : segments) {
    if (s.side != side) continue;
    pts.emplace_back(s.y1, s.x1);
    pts.emplace_back(s.y2, s.x2);
    y_top = std::min(y_top, std::min(s.y1, s.y2));
    y_bot = std::max(y_bot, std::max(s.y1, s.y2));
  }

  *out_samples = static_cast<int>(pts.size());
  if (pts.size() < 2) return false;

  // Build the design matrix [y^2  y  1] and RHS = x.
  const int n = static_cast<int>(pts.size());
  // For very few samples, solve degenerate quadratic as linear (a = 0).
  const bool linear = n < min_samples_per_fit_;
  const int cols = linear ? 2 : 3;

  cv::Mat A(n, cols, CV_32F);
  cv::Mat b(n, 1, CV_32F);
  for (int i = 0; i < n; ++i) {
    const float y = pts[i].x;  // we stored y in .x, x in .y (see above)
    const float x = pts[i].y;
    if (linear) {
      A.at<float>(i, 0) = y;
      A.at<float>(i, 1) = 1.0f;
    } else {
      A.at<float>(i, 0) = y * y;
      A.at<float>(i, 1) = y;
      A.at<float>(i, 2) = 1.0f;
    }
    b.at<float>(i, 0) = x;
  }

  cv::Mat sol;
  if (!cv::solve(A, b, sol, cv::DECOMP_SVD)) return false;

  if (linear) {
    out_coeffs[0] = 0.0f;
    out_coeffs[1] = sol.at<float>(0, 0);
    out_coeffs[2] = sol.at<float>(1, 0);
  } else {
    out_coeffs[0] = sol.at<float>(0, 0);
    out_coeffs[1] = sol.at<float>(1, 0);
    out_coeffs[2] = sol.at<float>(2, 0);
  }
  *out_y_top = y_top;
  *out_y_bot = y_bot;
  return true;
}

void LaneTracker::update(const std::vector<Lane>& hough, int frame_width,
                         int frame_height) {
  const double t0 = now_ms();
  curves_.clear();
  (void)frame_height;

  // ---- Left side --------------------------------------------------------
  {
    float c[3]; float yt = 0, yb = 0; int samples = 0;
    if (fit_poly2_(hough, /*side=*/0, c, &yt, &yb, &samples) &&
        mean_abs_residual_(hough, 0, c) < max_fit_residual_px_) {
      ema_(left_, c, yt, yb);
    } else {
      decay_(left_);
    }
  }
  // ---- Right side -------------------------------------------------------
  {
    float c[3]; float yt = 0, yb = 0; int samples = 0;
    if (fit_poly2_(hough, /*side=*/1, c, &yt, &yb, &samples) &&
        mean_abs_residual_(hough, 1, c) < max_fit_residual_px_) {
      ema_(right_, c, yt, yb);
    } else {
      decay_(right_);
    }
  }

  // ---- Center synthesis -------------------------------------------------
  // Coefficient-wise average of left/right when both are locked — safe
  // because a*y^2 + b*y + c is linear in its coefficients, so the per-
  // coefficient mean IS the midline polynomial.
  SideState synth{};
  synth.has_prev = false;
  if (left_.locked && right_.locked) {
    for (int i = 0; i < 3; ++i) {
      synth.coeffs[i] = 0.5f * (left_.coeffs[i] + right_.coeffs[i]);
    }
    synth.y_top = std::max(left_.y_top, right_.y_top);
    synth.y_bot = std::min(left_.y_bot, right_.y_bot);
    synth.has_prev = true;
    synth.locked = true;
    synth.confidence = 0.5f * (left_.confidence + right_.confidence);
    ema_(center_, synth.coeffs, synth.y_top, synth.y_bot);
    has_center_history_ = true;
  } else if (left_.locked || right_.locked) {
    // Only one side visible — project a parallel line half a lane width
    // away. Lane width unknown without IPM, but frame-center-to-line
    // distance is a reasonable proxy in image space for shadow-mode UX.
    const SideState& src = left_.locked ? left_ : right_;
    for (int i = 0; i < 3; ++i) synth.coeffs[i] = src.coeffs[i];
    // Nudge the intercept toward frame center by the current mean
    // separation between src and frame center at y_bot.
    const float src_x_bot = eval_poly_(src.coeffs, src.y_bot);
    const float half_width = std::abs(frame_width * 0.5f - src_x_bot);
    if (left_.locked) synth.coeffs[2] += half_width;   // shift right
    else              synth.coeffs[2] -= half_width;   // shift left
    synth.y_top = src.y_top;
    synth.y_bot = src.y_bot;
    synth.locked = true;
    synth.confidence = 0.6f * src.confidence;
    ema_(center_, synth.coeffs, synth.y_top, synth.y_bot);
    has_center_history_ = true;
  } else {
    decay_(center_);
  }

  // ---- Publish curves ---------------------------------------------------
  auto push_if = [&](const SideState& s, int side) {
    if (!s.locked) return;
    TrackedLane t{};
    t.coeffs[0] = s.coeffs[0];
    t.coeffs[1] = s.coeffs[1];
    t.coeffs[2] = s.coeffs[2];
    t.y_top = s.y_top;
    t.y_bot = s.y_bot;
    t.side = side;
    t.confidence = s.confidence;
    t.locked = 1;
    curves_.push_back(t);
  };
  push_if(left_, 0);
  push_if(right_, 1);
  push_if(center_, 2);

  // ---- Derived metrics --------------------------------------------------
  const float frame_cx = frame_width * 0.5f;
  if (center_.locked) {
    const float cx_bot = eval_poly_(center_.coeffs, center_.y_bot);
    // Sign convention: positive = frame-center is RIGHT of lane-center,
    // which means the driver has drifted LEFT relative to the lane.
    lateral_offset_px_ = frame_cx - cx_bot;

    // Curvature of y = f(x) is κ = |f''| / (1 + f'^2)^(3/2).
    // Here x = a*y^2 + b*y + c, so dx/dy = 2ay + b, d²x/dy² = 2a.
    const float yb = center_.y_bot;
    const float dxdy = 2.0f * center_.coeffs[0] * yb + center_.coeffs[1];
    const float d2xdy2 = 2.0f * center_.coeffs[0];
    const float denom = std::pow(1.0f + dxdy * dxdy, 1.5f);
    float kappa = 0.0f;
    if (denom > 1e-6f) kappa = d2xdy2 / denom;
    if (std::abs(kappa) < 1e-6f) {
      curvature_px_ = std::numeric_limits<float>::infinity();
    } else {
      curvature_px_ = 1.0f / kappa;   // signed radius
      if (curvature_px_ > 1.0e6f) curvature_px_ = 1.0e6f;
      if (curvature_px_ < -1.0e6f) curvature_px_ = -1.0e6f;
    }
  } else {
    lateral_offset_px_ = 0.0f;
    curvature_px_ = std::numeric_limits<float>::infinity();
  }

  // Sliding-window lateral velocity.
  const double tnow = now_ms();
  offset_history_.push_back({tnow, lateral_offset_px_});
  while (!offset_history_.empty() &&
         offset_history_.front().t_ms < tnow - history_window_ms_) {
    offset_history_.erase(offset_history_.begin());
  }
  if (offset_history_.size() >= 2 && center_.locked) {
    const auto& a = offset_history_.front();
    const auto& b = offset_history_.back();
    const double dt = b.t_ms - a.t_ms;
    if (dt > 1.0) {
      lateral_velocity_px_s_ =
          static_cast<float>((b.offset_px - a.offset_px) * 1000.0 / dt);
    }
  } else {
    lateral_velocity_px_s_ = 0.0f;
  }

  last_ms_ = static_cast<float>(now_ms() - t0);
}

}  // namespace zyra

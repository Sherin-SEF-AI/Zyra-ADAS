// Phase 6 — HoughLaneDetector implementation. See include/zyra/lane.h.

#include "zyra/lane.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include "zyra/logging.h"

namespace zyra {

namespace {

using clk = std::chrono::steady_clock;

inline double now_ms() {
  const auto d = clk::now().time_since_epoch();
  return std::chrono::duration<double, std::milli>(d).count();
}

// Build a trapezoidal ROI mask tuned for a dashboard-mounted phone. The
// ROI discards the top half (sky / distant scenery) and the far left/right
// edges at the bottom (dashboard / wipers).
cv::Mat build_roi_mask(int w, int h) {
  cv::Mat mask = cv::Mat::zeros(h, w, CV_8UC1);
  std::vector<cv::Point> poly = {
      cv::Point(static_cast<int>(w * 0.05f), h),
      cv::Point(static_cast<int>(w * 0.40f), static_cast<int>(h * 0.55f)),
      cv::Point(static_cast<int>(w * 0.60f), static_cast<int>(h * 0.55f)),
      cv::Point(static_cast<int>(w * 0.95f), h),
  };
  std::vector<std::vector<cv::Point>> polys{poly};
  cv::fillPoly(mask, polys, cv::Scalar(255));
  return mask;
}

// Weighted line fit across a list of segments — used to collapse the many
// Hough segments on each side into a single displayed lane. Weights by
// segment length so the long, confident segments dominate.
bool fit_line(const std::vector<cv::Vec4i>& segs,
              float& out_x1, float& out_y1,
              float& out_x2, float& out_y2,
              int proc_h) {
  if (segs.empty()) return false;
  double sum_w = 0.0;
  double sum_slope = 0.0;     // weighted slope (dy / dx)
  double sum_intercept = 0.0; // weighted x-intercept at y = bottom
  for (const cv::Vec4i& s : segs) {
    const double dx = static_cast<double>(s[2] - s[0]);
    const double dy = static_cast<double>(s[3] - s[1]);
    const double len = std::sqrt(dx * dx + dy * dy);
    if (len < 1e-3 || std::abs(dx) < 1e-3) continue;
    const double slope = dy / dx;                 // in proc coords
    const double b = s[1] - slope * s[0];          // y = slope*x + b
    sum_slope += slope * len;
    sum_intercept += b * len;
    sum_w += len;
  }
  if (sum_w <= 0.0) return false;
  const double slope = sum_slope / sum_w;
  const double b = sum_intercept / sum_w;
  // Render from y = proc_h (bottom) up to y = proc_h * 0.60 (above the ROI
  // top edge). Lines that extend past the ROI in Hough space get clipped
  // by the 0.60 cut.
  const double y_bot = proc_h - 1;
  const double y_top = proc_h * 0.60;
  if (std::abs(slope) < 1e-3) return false;
  const double x_bot = (y_bot - b) / slope;
  const double x_top = (y_top - b) / slope;
  out_x1 = static_cast<float>(x_bot);
  out_y1 = static_cast<float>(y_bot);
  out_x2 = static_cast<float>(x_top);
  out_y2 = static_cast<float>(y_top);
  return true;
}

}  // namespace

HoughLaneDetector::HoughLaneDetector() = default;

std::vector<Lane> HoughLaneDetector::detect(const uint8_t* y, int width,
                                            int height, int y_row_stride) {
  const double t0 = now_ms();
  std::vector<Lane> out;
  if (y == nullptr || width <= 0 || height <= 0) return out;

  // --- Wrap Y plane as an OpenCV Mat (no copy). ----------------------------
  cv::Mat full(height, width, CV_8UC1,
               const_cast<uint8_t*>(y),
               static_cast<size_t>(y_row_stride));

  // --- Downsample to a fixed processing resolution. ------------------------
  const int proc_w = processing_width_;
  const int proc_h = std::max(
      1, static_cast<int>(std::round(proc_w * static_cast<double>(height) /
                                     static_cast<double>(width))));

  // Cache the ROI mask — it only depends on (proc_w, proc_h) which are
  // constant across frames. Avoids re-building + fillPoly on every call.
  if (roi_cache_.empty() || roi_cache_.cols != proc_w ||
      roi_cache_.rows != proc_h) {
    roi_cache_ = build_roi_mask(proc_w, proc_h);
  }

  cv::resize(full, small_buf_, cv::Size(proc_w, proc_h), 0, 0,
             cv::INTER_LINEAR);

  // --- Blur + Canny (reuse pre-allocated Mats). ----------------------------
  cv::GaussianBlur(small_buf_, blur_buf_, cv::Size(5, 5), 0);
  cv::Canny(blur_buf_, edges_buf_, canny_low_, canny_high_);
  cv::bitwise_and(edges_buf_, roi_cache_, roi_buf_);

  // --- Probabilistic Hough. ------------------------------------------------
  std::vector<cv::Vec4i> segs;
  cv::HoughLinesP(roi_buf_, segs, 1.0, CV_PI / 180.0, hough_threshold_,
                  static_cast<double>(min_line_length_),
                  static_cast<double>(max_line_gap_));

  // --- Slope filter + split into left / right. -----------------------------
  std::vector<cv::Vec4i> left_segs, right_segs;
  const int cx = proc_w / 2;
  for (const cv::Vec4i& s : segs) {
    const double dx = s[2] - s[0];
    const double dy = s[3] - s[1];
    if (std::abs(dx) < 1e-3) continue;  // vertical
    const double slope = dy / dx;
    const double abs_slope = std::abs(slope);
    if (abs_slope < min_abs_slope_ || abs_slope > max_abs_slope_) continue;
    // Anchor to the bottom of the ROI: segments whose midpoint sits left of
    // center AND slope negatively (going up-left) are left lanes; opposite
    // for right. (y increases downward, so left lane slopes have dy/dx > 0
    // after the image-coord sign swap… careful: in OpenCV coords a line
    // going from bottom-left to top-right has dy/dx < 0.)
    const double mx = 0.5 * (s[0] + s[2]);
    const bool is_left = (mx < cx) && (slope < 0);
    const bool is_right = (mx >= cx) && (slope > 0);
    if (is_left) left_segs.push_back(s);
    else if (is_right) right_segs.push_back(s);
  }

  // --- Fit one line per side and rescale back to original frame coords. ---
  const float sx = static_cast<float>(width) / static_cast<float>(proc_w);
  const float sy = static_cast<float>(height) / static_cast<float>(proc_h);

  auto push = [&](const std::vector<cv::Vec4i>& segs_side, int side) {
    float x1, y1, x2, y2;
    if (!fit_line(segs_side, x1, y1, x2, y2, proc_h)) return;
    Lane ln{};
    ln.x1 = x1 * sx;
    ln.y1 = y1 * sy;
    ln.x2 = x2 * sx;
    ln.y2 = y2 * sy;
    ln.side = side;
    // Confidence = number of supporting segments, softly normalised so a
    // dozen or more segments saturate at 1.0.
    ln.confidence =
        std::min(1.0f, static_cast<float>(segs_side.size()) / 12.0f);
    out.push_back(ln);
  };
  push(left_segs, 0);
  push(right_segs, 1);

  last_ms_ = static_cast<float>(now_ms() - t0);
  return out;
}

}  // namespace zyra

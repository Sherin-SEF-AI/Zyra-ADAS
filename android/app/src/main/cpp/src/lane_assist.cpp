// Phase 7 — LaneAssist implementation. See include/zyra/lane_assist.h.

#include "zyra/lane_assist.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace zyra {

namespace {

constexpr int DISARMED = 0;
constexpr int ARMED = 1;
constexpr int WARN = 2;
constexpr int ALERT = 3;

// Evaluate x at y for a 2nd-order polynomial with coeffs[0..2].
inline float eval_poly(const float c[3], float y) {
  return c[0] * y * y + c[1] * y + c[2];
}

}  // namespace

LaneAssist::LaneAssist() {
  state_.ldw_state = DISARMED;
  state_.ttlc_s = std::numeric_limits<float>::infinity();
  state_.curvature_px = std::numeric_limits<float>::infinity();
  state_.dist_to_line_px = -1.0f;
  state_.drift_side = -1;
  state_.lateral_offset_m = std::numeric_limits<float>::quiet_NaN();
  state_.dist_to_line_m = -1.0f;
}

void LaneAssist::update(const LaneTracker& tracker, int frame_width,
                        int frame_height, const Ipm* ipm,
                        float ego_speed_mps, float yaw_rate_deg_s) {
  (void)frame_height;

  const auto& curves = tracker.curves();

  // Locate curves by side.
  const TrackedLane* left = nullptr;
  const TrackedLane* right = nullptr;
  const TrackedLane* center = nullptr;
  for (const auto& c : curves) {
    if (c.side == 0) left = &c;
    else if (c.side == 1) right = &c;
    else if (c.side == 2) center = &c;
  }

  const bool any_lock = (left || right || center);

  // Update the center-lock hysteresis counters.
  if (center != nullptr) {
    lose_misses_counter_ = 0;
    arm_hits_counter_ = std::min(arm_hits_ + 4, arm_hits_counter_ + 1);
  } else {
    arm_hits_counter_ = 0;
    lose_misses_counter_ = std::min(lose_misses_ + 4,
                                    lose_misses_counter_ + 1);
  }

  state_.lateral_offset_px = tracker.lateral_offset_px();
  state_.lateral_velocity_px_s = tracker.lateral_velocity_px_s();
  state_.curvature_px = tracker.curvature_px();

  // Distance to nearest lane line at bottom of image.
  float dist_px = -1.0f;
  int drift_side = -1;
  if ((left || right) && center != nullptr) {
    const float cx = frame_width * 0.5f;
    // Use y_bot of the center curve as the anchor for the "bottom" read.
    const float yb = center->y_bot;
    float dist_left = std::numeric_limits<float>::infinity();
    float dist_right = std::numeric_limits<float>::infinity();
    if (left) {
      const float xl = eval_poly(left->coeffs, yb);
      dist_left = cx - xl;  // positive when driver is right of left line
    }
    if (right) {
      const float xr = eval_poly(right->coeffs, yb);
      dist_right = xr - cx;  // positive when driver is left of right line
    }
    if (dist_left < dist_right) {
      dist_px = dist_left;
      drift_side = 0;  // drifting toward LEFT line
    } else {
      dist_px = dist_right;
      drift_side = 1;  // drifting toward RIGHT line
    }
  }
  state_.dist_to_line_px = dist_px;
  state_.drift_side = drift_side;

  // Phase 10 — world-space mirrors. We rely on the IPM's ground
  // projection at the bottom-centre of the image: that's the patch of
  // road directly under the ego's nose, and the reference point that
  // makes "lateral offset" intuitive (metres left/right of where the
  // tyres meet the road). If the IPM isn't calibrated, emit NaN so
  // downstream code can distinguish "not available" from "zero".
  const float nan_f = std::numeric_limits<float>::quiet_NaN();
  state_.lateral_offset_m = nan_f;
  state_.dist_to_line_m = -1.0f;
  if (ipm != nullptr && ipm->calibrated()) {
    // Reference: bottom-centre pixel → world point under ego nose.
    const zyra::WorldPoint ref =
        ipm->project_ground(frame_width * 0.5f,
                            static_cast<float>(frame_height) - 1.0f);
    // Offset: where the centre curve crosses y_bot (same pixel anchor
    // that the px-space offset uses) → world x.
    if (center != nullptr && std::isfinite(ref.z_m)) {
      const float cx_at_yb = eval_poly(center->coeffs, center->y_bot);
      const zyra::WorldPoint p =
          ipm->project_ground(cx_at_yb, center->y_bot);
      if (std::isfinite(p.z_m)) {
        // Positive = driver drifted to the LEFT (lane centre is to
        // driver's right relative to ego nose), matching
        // lateral_offset_px sign convention.
        state_.lateral_offset_m = ref.x_m - p.x_m;
      }
    }
    if (dist_px > 0.0f) {
      // Distance to line in metres: project the line's crossing pixel
      // back to ground. We approximate by using `lateral_offset_m` as
      // a lower bound, or falling back to px→m scaling at the bottom
      // row if unavailable.
      state_.dist_to_line_m = std::abs(state_.lateral_offset_m);
    }
  }

  // TTLC: use the signed lateral velocity that moves TOWARD the nearest
  // line. If the driver is drifting away (or dist_px unknown), TTLC = +INF.
  float ttlc = std::numeric_limits<float>::infinity();
  if (dist_px > 0.0f && drift_side >= 0) {
    const float v = state_.lateral_velocity_px_s;  // signed
    // Signs: lateral_offset_px positive = drifted LEFT (toward left line).
    //        lateral_velocity same sign when accelerating that drift.
    // Convert to toward-line speed by picking the correct sign.
    const float toward = (drift_side == 0) ? v : -v;
    if (toward > 5.0f) {
      ttlc = dist_px / toward;
    }
  }
  state_.ttlc_s = ttlc;

  // ---- State machine ----------------------------------------------------
  const float warn_px = warn_frac_ * frame_width;
  const float clear_px = warn_px * warn_clear_ratio_;
  const float abs_off = std::abs(state_.lateral_offset_px);

  int next = state_.ldw_state;

  if (lose_misses_counter_ >= lose_misses_ || !any_lock) {
    next = DISARMED;
  } else if (state_.ldw_state == DISARMED) {
    if (arm_hits_counter_ >= arm_hits_) next = ARMED;
  } else if (state_.ldw_state == ARMED) {
    if (abs_off > warn_px) next = WARN;
  } else if (state_.ldw_state == WARN) {
    if (abs_off < clear_px) next = ARMED;
    else if (ttlc < alert_ttlc_s_) next = ALERT;
  } else if (state_.ldw_state == ALERT) {
    if (abs_off < clear_px) next = ARMED;
    else if (ttlc > alert_ttlc_s_ * 2.0f) next = WARN;
  }

  // Phase 11 — speed gating: below 30 km/h force DISARMED (parking,
  // crawl). Yaw rate > 3°/s blocks WARN/ALERT escalation (intentional
  // turn; the driver is deliberately crossing the lane line).
  const float speed_kmh = ego_speed_mps * 3.6f;
  if (speed_kmh < 30.0f) {
    next = DISARMED;
  } else if (std::abs(yaw_rate_deg_s) > 3.0f) {
    if (next == WARN || next == ALERT) next = ARMED;
  }

  state_.ldw_state = next;
  state_.armed = (next == DISARMED) ? 0 : 1;
}

}  // namespace zyra

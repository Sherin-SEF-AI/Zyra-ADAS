// Phase 7 — Lane Assist state machine.
//
// Converts the LaneTracker's continuous metrics (lateral offset, lateral
// velocity, curvature, center lock) into a discrete LDW (Lane Departure
// Warning) state that drives UI alerts and haptics.
//
// State machine:
//
//   DISARMED (0)  ── center locked for >= arm_hits frames ──▶  ARMED (1)
//   ARMED    (1)  ── |offset| > warn_threshold               ──▶ WARN (2)
//   WARN     (2)  ── TTLC < alert_ttlc                        ──▶ ALERT (3)
//   any except DISARMED ── center lost for >= lose_misses      ──▶ DISARMED
//   WARN     (2)  ── |offset| < warn_threshold * warn_clear_ratio ──▶ ARMED
//   ALERT    (3)  ── |offset| < warn_threshold * warn_clear_ratio ──▶ ARMED
//
// TTLC (Time To Lane Crossing) is estimated from the signed lateral
// velocity + the distance to the NEAREST lane line at the bottom of
// the image. Negative TTLC (moving away) is capped to +INF.
//
// Thresholds are in image-space pixels for Phase 7 (no camera
// calibration yet — Phase 8 will upgrade to meters once we have
// intrinsics + GPS speed).

#pragma once

#include <cstdint>

#include "zyra/lane_tracker.h"

namespace zyra {

struct LaneAssistState {
  int ldw_state;           // 0 DISARMED, 1 ARMED, 2 WARN, 3 ALERT
  float lateral_offset_px; // signed, same convention as LaneTracker
  float lateral_velocity_px_s;
  float ttlc_s;            // time to lane crossing; +INF if safe
  float curvature_px;      // signed radius at y_bot; +INF if straight
  int armed;               // 1 if ldw_state != DISARMED
  // Optional dist-to-nearest-line-at-bottom, px. -1 if unknown.
  float dist_to_line_px;
  // Which side the driver is drifting toward (0 left, 1 right, -1 none).
  int drift_side;
};

class LaneAssist {
 public:
  LaneAssist();

  void update(const LaneTracker& tracker, int frame_width, int frame_height);

  const LaneAssistState& state() const { return state_; }

  // Tuning. Thresholds are fractions of frame width for portability.
  void set_warn_frac(float f) { warn_frac_ = f; }
  void set_alert_ttlc_s(float t) { alert_ttlc_s_ = t; }
  void set_arm_hits(int n) { arm_hits_ = n; }
  void set_lose_misses(int n) { lose_misses_ = n; }

 private:
  LaneAssistState state_{};
  int arm_hits_counter_ = 0;
  int lose_misses_counter_ = 0;

  float warn_frac_ = 0.12f;          // of frame width
  float warn_clear_ratio_ = 0.75f;
  float alert_ttlc_s_ = 0.8f;
  int arm_hits_ = 4;
  int lose_misses_ = 8;
};

}  // namespace zyra

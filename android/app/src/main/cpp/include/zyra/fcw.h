// Phase 8 — Forward Collision Warning.
//
// Classifies the most critical tracked object ahead of the ego camera
// into one of four states based on Time-To-Collision (TTC) estimated
// from bbox height expansion rate. Standalone from any ego-speed sensor;
// works purely from visual cues.
//
// TTC derivation:
//   Given bbox height h growing at fractional rate r = Δh / (h · Δt),
//   the time for h to diverge (i.e. reach camera) is 1 / r. Noisy but
//   serviceable for qualitative warnings — refined with a smoothed
//   (hysteresis-guarded) state machine, so we don't flip at every frame.

#pragma once

#include <cstdint>
#include <vector>

#include "zyra/object_tracker.h"

namespace zyra {

enum FcwStateId : int32_t {
  FCW_SAFE    = 0,
  FCW_CAUTION = 1,
  FCW_WARN    = 2,
  FCW_ALERT   = 3,
};

struct FcwSnapshot {
  int32_t state;                // FcwStateId
  float   ttc_s;                // time-to-collision of the critical target; +INF if none
  int32_t critical_track_id;    // -1 if no target
  int32_t critical_class_id;    // Zyra class id of the critical target, -1 if none
  float   critical_bbox_h_frac; // critical bbox height / frame height, for HUD sizing hint
};

class ForwardCollisionWarning {
 public:
  ForwardCollisionWarning();

  // Evaluate FCW against the current set of confirmed tracks. `frame_w/h`
  // are the ORIGINAL image dimensions (sensor-native landscape) so we can
  // compute ego-corridor membership without a projection matrix.
  void update(const std::vector<TrackedObject>& tracks,
              int frame_w, int frame_h);

  const FcwSnapshot& state() const { return state_; }

  // Tuning --------------------------------------------------------------
  void set_caution_ttc_s(float s) { caution_ttc_s_ = s; }
  void set_warn_ttc_s(float s)    { warn_ttc_s_ = s; }
  void set_alert_ttc_s(float s)   { alert_ttc_s_ = s; }
  void set_corridor_half_frac(float f) { corridor_half_frac_ = f; }
  void set_min_height_frac(float f) { min_height_frac_ = f; }

 private:
  FcwSnapshot state_{};

  // Only consider tracks whose bbox centre falls inside a horizontal
  // corridor of total width = corridor_half_frac_ * 2 around the frame
  // centre. 0.45 covers the ego lane plus immediate adjacent — we'd
  // rather over-warn than miss.
  float corridor_half_frac_ = 0.45f;

  // Ignore objects that occupy less than this fraction of the frame
  // height — they're too distant / jittery to TTC reliably from bbox
  // expansion alone.
  float min_height_frac_ = 0.08f;

  // TTC state thresholds.
  float caution_ttc_s_ = 4.0f;
  float warn_ttc_s_    = 2.5f;
  float alert_ttc_s_   = 1.2f;

  // Hysteresis — once raised, state stays at N consecutive below-threshold
  // frames to drop. Prevents flipping between states at border TTC.
  int raise_hits_ = 2;
  int clear_hits_ = 4;

  int32_t pending_state_ = FCW_SAFE;
  int32_t pending_count_ = 0;

  // Classes that we warn against. Everything else (traffic_sign,
  // traffic_light, …) is ignored here.
  bool class_is_threat_(int32_t class_id) const;

  // Convert TTC → FcwStateId using the configured thresholds.
  int32_t ttc_to_state_(float ttc_s) const;
};

}  // namespace zyra

// Phase 8 — ForwardCollisionWarning implementation.

#include "zyra/fcw.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace zyra {

namespace {

constexpr float kInf = std::numeric_limits<float>::infinity();

}  // namespace

ForwardCollisionWarning::ForwardCollisionWarning() {
  state_.state = FCW_SAFE;
  state_.ttc_s = kInf;
  state_.critical_track_id = -1;
  state_.critical_class_id = -1;
  state_.critical_bbox_h_frac = 0.0f;
}

bool ForwardCollisionWarning::class_is_threat_(int32_t class_id) const {
  // Keep in sync with kZyraClasses in lib/core/constants.dart.
  //   0 pedestrian / 1 bicycle / 2 car / 3 motorcycle / 4 bus /
  //   5 truck / 6 auto_rickshaw
  switch (class_id) {
    case 0: case 1: case 2: case 3: case 4: case 5: case 6:
      return true;
    default:
      return false;
  }
}

int32_t ForwardCollisionWarning::ttc_to_state_(float ttc_s) const {
  if (!std::isfinite(ttc_s)) return FCW_SAFE;
  if (ttc_s <= alert_ttc_s_)   return FCW_ALERT;
  if (ttc_s <= warn_ttc_s_)    return FCW_WARN;
  if (ttc_s <= caution_ttc_s_) return FCW_CAUTION;
  return FCW_SAFE;
}

void ForwardCollisionWarning::update(const std::vector<TrackedObject>& tracks,
                                     int frame_w, int frame_h) {
  const float fh = static_cast<float>(frame_h);
  const float fw = static_cast<float>(frame_w);
  const float corridor_lo = fw * (0.5f - corridor_half_frac_);
  const float corridor_hi = fw * (0.5f + corridor_half_frac_);

  float best_ttc = kInf;
  const TrackedObject* best = nullptr;

  for (const TrackedObject& t : tracks) {
    if (!class_is_threat_(t.class_id)) continue;
    const float cx = t.cx();
    if (cx < corridor_lo || cx > corridor_hi) continue;

    const float h = t.height();
    if (h < min_height_frac_ * fh) continue;

    // Only a positive height-rate indicates closing. Negative (receding)
    // or ~zero (stationary) yields +INF — safe.
    if (t.height_rate_per_s <= 1e-3f) continue;

    const float ttc = 1.0f / t.height_rate_per_s;
    if (ttc < best_ttc) {
      best_ttc = ttc;
      best = &t;
    }
  }

  const int32_t observed_state = ttc_to_state_(best_ttc);

  // Hysteresis. We raise the state quickly (raise_hits_) but clear slowly
  // (clear_hits_) so a momentary drop in bbox height from a tracker jitter
  // doesn't instantly silence an alert.
  if (observed_state != state_.state) {
    if (observed_state != pending_state_) {
      pending_state_ = observed_state;
      pending_count_ = 1;
    } else {
      pending_count_ += 1;
    }
    const int threshold = (observed_state > state_.state)
                              ? raise_hits_
                              : clear_hits_;
    if (pending_count_ >= threshold) {
      state_.state = observed_state;
      pending_count_ = 0;
    }
  } else {
    pending_state_ = state_.state;
    pending_count_ = 0;
  }

  // Report the critical track regardless of hysteresis so the HUD always
  // points at the worst offender.
  state_.ttc_s = best_ttc;
  state_.critical_track_id = best ? best->id : -1;
  state_.critical_class_id = best ? best->class_id : -1;
  state_.critical_bbox_h_frac = best ? (best->height() / fh) : 0.0f;
}

}  // namespace zyra

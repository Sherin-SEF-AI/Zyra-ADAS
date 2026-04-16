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
  state_.critical_distance_m = kInf;
  state_.range_rate_mps = 0.0f;
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
                                     int frame_w, int frame_h,
                                     const Ipm* ipm, double now_ms) {
  const float fh = static_cast<float>(frame_h);
  const float fw = static_cast<float>(frame_w);
  const float corridor_lo = fw * (0.5f - corridor_half_frac_);
  const float corridor_hi = fw * (0.5f + corridor_half_frac_);
  const bool have_ipm = (ipm != nullptr && ipm->calibrated());

  float best_ttc = kInf;
  float best_range_m = kInf;
  float best_rate_mps = 0.0f;
  const TrackedObject* best = nullptr;

  // Mark which track ids we've seen this frame, so we can prune stale
  // history entries after the loop.
  std::unordered_map<int32_t, bool> seen;
  seen.reserve(tracks.size());

  for (const TrackedObject& t : tracks) {
    if (!class_is_threat_(t.class_id)) continue;
    const float cx = t.cx();
    if (cx < corridor_lo || cx > corridor_hi) continue;

    const float h = t.height();
    if (h < min_height_frac_ * fh) continue;

    seen[t.id] = true;

    // Two independent TTC estimators. Prefer the world-space one when
    // available — a bounding box's height derivative is dominated by
    // tracker jitter at long range; an explicit range rate doesn't
    // suffer from that as badly.
    float track_ttc = kInf;
    float track_range_m = kInf;
    float track_rate_mps = 0.0f;

    if (have_ipm) {
      // Project the bbox's tyre contact point (bottom-centre) to the
      // ground. A standing object's foot is its closest ground contact
      // and the stablest pixel to track range from.
      const zyra::WorldPoint wp =
          ipm->project_ground(t.cx(), t.y2);
      if (std::isfinite(wp.z_m) && wp.z_m > 0.0f) {
        const float inst_range =
            std::sqrt(wp.x_m * wp.x_m + wp.z_m * wp.z_m);
        track_range_m = inst_range;

        auto it = ranges_.find(t.id);
        if (it != ranges_.end()) {
          const RangeHistory& prev = it->second;
          const float dt = static_cast<float>(
              std::max(1e-3, (now_ms - prev.last_ts_ms) / 1000.0));
          // Closing rate is positive when range shrinks. Single-sided
          // EMA: we smooth the rate, not the range, so a lone noisy
          // frame can't alone flip sign.
          const float inst_rate = (prev.range_m - inst_range) / dt;
          const float new_rate = rate_ema_ * inst_rate +
                                 (1.0f - rate_ema_) * prev.range_rate_mps;
          const float new_range = range_ema_ * inst_range +
                                  (1.0f - range_ema_) * prev.range_m;
          ranges_[t.id] =
              RangeHistory{new_range, new_rate, now_ms};
          track_rate_mps = new_rate;
          if (new_rate > 0.1f) {
            track_ttc = new_range / new_rate;
          }
        } else {
          ranges_[t.id] = RangeHistory{inst_range, 0.0f, now_ms};
        }
      }
    }

    // Bbox height-rate TTC — fallback + sanity cross-check. A positive
    // rate indicates closing. We take whichever estimator returns the
    // *smaller* TTC (more conservative from the driver's perspective).
    if (t.height_rate_per_s > 1e-3f) {
      const float bbox_ttc = 1.0f / t.height_rate_per_s;
      if (bbox_ttc < track_ttc) track_ttc = bbox_ttc;
    }

    if (track_ttc < best_ttc) {
      best_ttc = track_ttc;
      best_range_m = track_range_m;
      best_rate_mps = track_rate_mps;
      best = &t;
    }
  }

  // Drop history for tracks that didn't appear this frame (ID reuse
  // would otherwise inherit stale range estimates from an unrelated
  // object).
  for (auto it = ranges_.begin(); it != ranges_.end();) {
    if (seen.find(it->first) == seen.end()) {
      it = ranges_.erase(it);
    } else {
      ++it;
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
  state_.critical_distance_m = best ? best_range_m : kInf;
  state_.range_rate_mps = best ? best_rate_mps : 0.0f;
}

}  // namespace zyra

// Phase 8 — ObjectTracker implementation. See object_tracker.h for the
// contract. The algorithm is deliberately simple: greedy IoU matching,
// EMA on bbox, explicit confirmation + lifecycle.

#include "zyra/object_tracker.h"

#include <algorithm>
#include <chrono>
#include <cmath>

namespace zyra {

namespace {

using clk = std::chrono::steady_clock;

inline double now_ms() {
  const auto d = clk::now().time_since_epoch();
  return std::chrono::duration<double, std::milli>(d).count();
}

}  // namespace

ObjectTracker::ObjectTracker() = default;

float ObjectTracker::iou_(const TrackedObject& t, const Detection& d) {
  const float xx1 = std::max(t.x1, d.x1);
  const float yy1 = std::max(t.y1, d.y1);
  const float xx2 = std::min(t.x2, d.x2);
  const float yy2 = std::min(t.y2, d.y2);
  const float w = std::max(0.0f, xx2 - xx1);
  const float h = std::max(0.0f, yy2 - yy1);
  const float inter = w * h;
  const float area_t = std::max(0.0f, (t.x2 - t.x1)) * std::max(0.0f, (t.y2 - t.y1));
  const float area_d = std::max(0.0f, (d.x2 - d.x1)) * std::max(0.0f, (d.y2 - d.y1));
  const float uni = area_t + area_d - inter;
  return uni > 1e-3f ? inter / uni : 0.0f;
}

void ObjectTracker::update(const std::vector<Detection>& dets,
                           double timestamp_ms) {
  const double t0 = now_ms();

  const double dt_s = (prev_timestamp_ms_ > 0 &&
                       timestamp_ms > prev_timestamp_ms_)
                          ? (timestamp_ms - prev_timestamp_ms_) * 1e-3
                          : 0.0;
  prev_timestamp_ms_ = timestamp_ms;

  // -------------------------------------------------------------------
  // Greedy association. Build all (track, det) pairs above the IoU
  // threshold with matching class, sort descending by IoU, consume pairs
  // whose endpoints are both still free.
  // -------------------------------------------------------------------
  struct Pair {
    int t_idx;
    int d_idx;
    float iou;
  };
  std::vector<Pair> pairs;
  pairs.reserve(tracks_.size() * dets.size());
  for (size_t ti = 0; ti < tracks_.size(); ++ti) {
    for (size_t di = 0; di < dets.size(); ++di) {
      if (tracks_[ti].class_id != dets[di].class_id) continue;
      const float v = iou_(tracks_[ti], dets[di]);
      if (v < iou_threshold_) continue;
      pairs.push_back({static_cast<int>(ti), static_cast<int>(di), v});
    }
  }
  std::sort(pairs.begin(), pairs.end(),
            [](const Pair& a, const Pair& b) { return a.iou > b.iou; });

  std::vector<int> t_to_d(tracks_.size(), -1);
  std::vector<int> d_to_t(dets.size(), -1);
  for (const Pair& p : pairs) {
    if (t_to_d[p.t_idx] >= 0 || d_to_t[p.d_idx] >= 0) continue;
    t_to_d[p.t_idx] = p.d_idx;
    d_to_t[p.d_idx] = p.t_idx;
  }

  // -------------------------------------------------------------------
  // Update matched tracks: EMA on bbox + height-rate derivation.
  // -------------------------------------------------------------------
  const float a = pos_ema_;
  const float ar = rate_ema_;
  for (size_t ti = 0; ti < tracks_.size(); ++ti) {
    const int di = t_to_d[ti];
    if (di < 0) {
      tracks_[ti].missed += 1;
      continue;
    }
    const Detection& d = dets[di];
    TrackedObject& t = tracks_[ti];
    const float prev_cx = t.cx();
    const float prev_cy = t.cy();
    const float prev_h = t.height();

    t.x1 = (1.0f - a) * t.x1 + a * d.x1;
    t.y1 = (1.0f - a) * t.y1 + a * d.y1;
    t.x2 = (1.0f - a) * t.x2 + a * d.x2;
    t.y2 = (1.0f - a) * t.y2 + a * d.y2;
    t.confidence = d.confidence;
    t.age_frames += 1;
    t.missed = 0;
    if (t.age_frames >= min_hits_) t.confirmed = true;

    if (dt_s > 1e-3) {
      const float inst_vx = (t.cx() - prev_cx) / static_cast<float>(dt_s);
      const float inst_vy = (t.cy() - prev_cy) / static_cast<float>(dt_s);
      t.vx_px_s = 0.7f * t.vx_px_s + 0.3f * inst_vx;
      t.vy_px_s = 0.7f * t.vy_px_s + 0.3f * inst_vy;

      if (prev_h > 1e-3f) {
        const float inst_rate =
            (t.height() - prev_h) / (prev_h * static_cast<float>(dt_s));
        t.height_rate_per_s =
            (1.0f - ar) * t.height_rate_per_s + ar * inst_rate;
      }
    }
    last_seen_ms_[ti] = timestamp_ms;
    last_height_[ti] = t.height();
  }

  // -------------------------------------------------------------------
  // Spawn tracks for unmatched detections.
  // -------------------------------------------------------------------
  for (size_t di = 0; di < dets.size(); ++di) {
    if (d_to_t[di] >= 0) continue;
    const Detection& d = dets[di];
    TrackedObject t{};
    t.id = next_id_++;
    t.class_id = d.class_id;
    t.x1 = d.x1; t.y1 = d.y1; t.x2 = d.x2; t.y2 = d.y2;
    t.vx_px_s = 0.0f; t.vy_px_s = 0.0f;
    t.age_frames = 1;
    t.missed = 0;
    t.confidence = d.confidence;
    t.confirmed = (min_hits_ <= 1);
    t.height_rate_per_s = 0.0f;
    tracks_.push_back(t);
    last_seen_ms_.push_back(timestamp_ms);
    last_height_.push_back(t.height());
  }

  // -------------------------------------------------------------------
  // Cull tracks that have been unmatched for too long.
  // -------------------------------------------------------------------
  for (size_t i = 0; i < tracks_.size();) {
    if (tracks_[i].missed > max_missed_) {
      tracks_.erase(tracks_.begin() + i);
      last_seen_ms_.erase(last_seen_ms_.begin() + i);
      last_height_.erase(last_height_.begin() + i);
    } else {
      ++i;
    }
  }

  last_ms_ = static_cast<float>(now_ms() - t0);
}

std::vector<TrackedObject> ObjectTracker::tracks() const {
  std::vector<TrackedObject> out;
  out.reserve(tracks_.size());
  for (const TrackedObject& t : tracks_) {
    if (t.confirmed && t.missed == 0) out.push_back(t);
  }
  return out;
}

}  // namespace zyra

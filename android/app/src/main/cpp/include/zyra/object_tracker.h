// Phase 8 — lightweight IoU + constant-velocity object tracker.
//
// Associates per-frame YOLO detections to persistent tracks using a greedy
// IoU-over-threshold matcher (ByteTrack-lite). Each track maintains an EMA
// on centre position and size, plus a velocity estimate from centre
// displacement over time. The tracker smooths jittery detector boxes,
// filters one-frame false positives, and — most importantly — gives each
// object a stable ID so downstream consumers (FCW, shadow planner) can
// reason about individual targets across time.
//
// Design notes:
//   * Greedy IoU association is O(N·M) — fine for N < 32 which is our cap.
//     Hungarian would be a constant-factor win at this scale; not worth it.
//   * Only detections with IoU >= iou_threshold_ are matched. Unmatched
//     detections become new tentative tracks; unmatched confirmed tracks
//     age and eventually die.
//   * A track is "confirmed" once it has been hit in `min_hits_` of its
//     first `min_hits_ + 2` frames and is kept alive for `max_missed_`
//     further frames before deletion. Tentative tracks are not exported.

#pragma once

#include <cstdint>
#include <vector>

#include "zyra/detection.h"

namespace zyra {

struct TrackedObject {
  int32_t id;
  int32_t class_id;
  // Smoothed bbox in ORIGINAL image pixels (same space as Detection).
  float x1;
  float y1;
  float x2;
  float y2;
  // Centre velocity in px/sec. Updated each frame from Δ(centre) / Δt.
  float vx_px_s;
  float vy_px_s;
  int32_t age_frames;   // total frames the track has been matched.
  int32_t missed;       // consecutive frames unmatched since last hit.
  float confidence;     // last detection confidence that landed on this track.
  bool confirmed;       // true once age_frames >= min_hits_.

  // Size rate: (height_now - height_prev) / height_prev per second. Positive
  // means the box is growing → object is approaching the camera. Consumed
  // by ForwardCollisionWarning as the raw TTC signal.
  float height_rate_per_s;

  // Phase 17 — relative depth from Depth Anything V2 (0..1, 0=far, 1=near).
  // Populated by the engine after depth inference. 0 when depth unavailable.
  float depth_relative = 0.0f;

  // Derived helpers.
  float cx() const { return 0.5f * (x1 + x2); }
  float cy() const { return 0.5f * (y1 + y2); }
  float width() const { return x2 - x1; }
  float height() const { return y2 - y1; }
};

class ObjectTracker {
 public:
  ObjectTracker();

  // Reconcile a fresh detection batch into persistent tracks. `timestamp_ms`
  // is the frame's monotonic clock in ms — used for velocity estimation.
  void update(const std::vector<Detection>& dets, double timestamp_ms);

  // Confirmed tracks only. Tentative ones are held internally until they
  // pass the hit threshold.
  std::vector<TrackedObject> tracks() const;

  // Wall-clock of the last update() call in ms.
  float last_ms() const { return last_ms_; }

  // Tuning --------------------------------------------------------------
  void set_iou_threshold(float iou) { iou_threshold_ = iou; }
  void set_min_hits(int n) { min_hits_ = n; }
  void set_max_missed(int n) { max_missed_ = n; }
  void set_position_ema(float a) { pos_ema_ = a; }

 private:
  std::vector<TrackedObject> tracks_;
  std::vector<double> last_seen_ms_;      // parallel to tracks_
  std::vector<float> last_height_;        // for height-rate derivation
  int32_t next_id_ = 1;
  double prev_timestamp_ms_ = -1.0;

  // Tuning defaults — chosen on the conservative side; we'd rather drop a
  // flickery detection than hand out unstable IDs.
  float iou_threshold_ = 0.30f;
  int   min_hits_      = 3;
  int   max_missed_    = 8;
  float pos_ema_       = 0.55f;   // new-weight on position EMA.
  float rate_ema_      = 0.35f;   // new-weight on height-rate EMA.

  float last_ms_ = 0.0f;

  static float iou_(const TrackedObject& t, const Detection& d);
};

}  // namespace zyra

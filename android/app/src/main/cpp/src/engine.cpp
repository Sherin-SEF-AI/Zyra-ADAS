// Phase 4 — PerceptionEngine implementation. See include/zyra/engine.h for
// the contract.

#include "zyra/engine.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <future>
#include <vector>

#include "zyra/detection.h"
#include "zyra/frame.h"
#include "zyra/logging.h"

namespace zyra {

namespace {

using clk = std::chrono::steady_clock;

inline double now_ms() {
  const auto d = clk::now().time_since_epoch();
  return std::chrono::duration<double, std::milli>(d).count();
}

}  // namespace

PerceptionEngine::PerceptionEngine() = default;

PerceptionEngine::~PerceptionEngine() {
  // Signal the worker to exit and kick the CV. joining without signalling
  // would hang because the thread is asleep on `pending_cv_`.
  stop_.store(true, std::memory_order_relaxed);
  pending_cv_.notify_all();
  if (worker_.joinable()) worker_.join();
}

int PerceptionEngine::load_model(const std::string& param_path,
                                 const std::string& bin_path,
                                 bool use_vulkan) {
  if (param_path.empty() || bin_path.empty()) return -2;
  if (!detector_.load(param_path, bin_path, use_vulkan)) return -3;
  loaded_.store(true, std::memory_order_release);

  // Start the worker if this is the first successful load. Re-loading the
  // model on an already-running engine reuses the existing worker — the
  // detector_ instance is rebound in place.
  if (!worker_.joinable()) {
    worker_ = std::thread([this] { worker_loop_(); });
  }
  return 0;
}

int PerceptionEngine::load_seg_model(const std::string& param_path,
                                     const std::string& bin_path,
                                     bool use_vulkan) {
  if (param_path.empty() || bin_path.empty()) return -2;
  if (!road_segmentor_.load(param_path, bin_path, use_vulkan)) return -3;
  return 0;
}

int PerceptionEngine::warmup() {
  if (!loaded_.load(std::memory_order_acquire)) return -1;
  std::vector<uint8_t> grey(640 * 640 * 3, 114);
  (void)detector_.detect_rgb(grey.data(), 640, 640);
  return 0;
}

void PerceptionEngine::set_class_threshold(int id, float t) {
  detector_.set_class_threshold(id, t);
}
void PerceptionEngine::set_conf_threshold(float t) {
  detector_.set_conf_threshold(t);
}
void PerceptionEngine::set_nms_iou(float iou) {
  detector_.set_nms_iou(iou);
}

int PerceptionEngine::set_camera_geometry(float mount_h_m, float pitch_deg,
                                          float hfov_deg,
                                          int frame_w, int frame_h) {
  if (mount_h_m <= 0.0f || hfov_deg <= 0.0f || hfov_deg >= 180.0f ||
      frame_w <= 0 || frame_h <= 0) {
    return -2;
  }
  std::lock_guard<std::mutex> lk(ipm_mu_);
  ipm_.set_geometry(mount_h_m, pitch_deg, hfov_deg, frame_w, frame_h);
  return 0;
}

void PerceptionEngine::set_ego_state(float ego_speed_mps, float pitch_deg,
                                     float yaw_rate_deg_s) {
  std::lock_guard<std::mutex> lk(ego_mu_);
  ego_state_.speed_mps = ego_speed_mps;
  ego_state_.yaw_rate_deg_s = yaw_rate_deg_s;
  // Update IPM pitch when the change exceeds 0.5° to avoid churn.
  const float delta = std::abs(pitch_deg - ego_state_.pitch_deg);
  ego_state_.pitch_deg = pitch_deg;
  if (delta > 0.5f) {
    std::lock_guard<std::mutex> ipm_lk(ipm_mu_);
    if (ipm_.calibrated()) {
      ipm_.set_pitch(pitch_deg);
    }
  }
}

void PerceptionEngine::set_vehicle_dynamics(const VehicleDynamics& d) {
  // Shadow planner is only read from the worker thread, but dynamics
  // are pushed from Dart. A simple lock keeps them consistent.
  std::lock_guard<std::mutex> lk(ego_mu_);
  shadow_planner_.set_dynamics(d);
}

int PerceptionEngine::vulkan_active() const {
  if (!loaded_.load(std::memory_order_acquire)) return -1;
  return detector_.vulkan_active() ? 1 : 0;
}

int PerceptionEngine::submit(const uint8_t* y, const uint8_t* u,
                             const uint8_t* v, int W, int H,
                             int y_row_stride, int uv_row_stride,
                             int uv_pixel_stride, int rotation_deg,
                             uint64_t frame_id, double timestamp_ms) {
  if (!loaded_.load(std::memory_order_acquire)) return -2;
  if (y == nullptr || u == nullptr || v == nullptr) return -3;
  if (W <= 0 || H <= 0) return -3;

  Pending next;
  next.width = W;
  next.height = H;
  next.uv_row_stride = 0;  // filled per variant below
  next.uv_pixel_stride = uv_pixel_stride;
  next.rotation = rotation_deg;
  next.frame_id = frame_id;
  next.timestamp_ms = timestamp_ms;
  next.is_nv21 = (v < u);

  // --- Y plane: strip row-stride padding, land in exactly W*H bytes ----
  next.y_buf.resize(static_cast<size_t>(W) * H);
  if (y_row_stride == W) {
    std::memcpy(next.y_buf.data(), y, static_cast<size_t>(W) * H);
  } else {
    for (int r = 0; r < H; ++r) {
      std::memcpy(next.y_buf.data() + static_cast<size_t>(r) * W,
                  y + static_cast<size_t>(r) * y_row_stride,
                  static_cast<size_t>(W));
    }
  }

  // --- UV plane: preserve byte ordering so preprocess detects the
  //     variant the same way it would from the original camera buffers.
  if (uv_pixel_stride == 2) {
    // Semi-planar — copy one contiguous block starting from min(u,v).
    const uint8_t* uv_src = (v < u) ? v : u;
    const int uv_rows = H / 2;
    next.uv_buf.resize(static_cast<size_t>(W) * uv_rows);
    if (uv_row_stride == W) {
      std::memcpy(next.uv_buf.data(), uv_src,
                  static_cast<size_t>(W) * uv_rows);
    } else {
      for (int r = 0; r < uv_rows; ++r) {
        std::memcpy(next.uv_buf.data() + static_cast<size_t>(r) * W,
                    uv_src + static_cast<size_t>(r) * uv_row_stride,
                    static_cast<size_t>(W));
      }
    }
    next.uv_row_stride = W;
  } else {
    // Fully planar I420 — pack U then V into uv_buf.
    const int uv_cols = W / 2;
    const int uv_rows = H / 2;
    next.uv_buf.resize(static_cast<size_t>(2) * uv_cols * uv_rows);
    uint8_t* u_dst = next.uv_buf.data();
    uint8_t* v_dst = u_dst + static_cast<size_t>(uv_cols) * uv_rows;
    for (int r = 0; r < uv_rows; ++r) {
      std::memcpy(u_dst + static_cast<size_t>(r) * uv_cols,
                  u + static_cast<size_t>(r) * uv_row_stride,
                  static_cast<size_t>(uv_cols));
      std::memcpy(v_dst + static_cast<size_t>(r) * uv_cols,
                  v + static_cast<size_t>(r) * uv_row_stride,
                  static_cast<size_t>(uv_cols));
    }
    next.uv_row_stride = uv_cols;
  }
  next.has_data = true;

  {
    std::lock_guard<std::mutex> lk(pending_mu_);
    pending_ = std::move(next);
  }
  pending_cv_.notify_one();
  return 0;
}

bool PerceptionEngine::poll(ZyraDetectionBatch* out) {
  if (out == nullptr) return false;
  std::lock_guard<std::mutex> lk(result_mu_);
  if (!result_valid_) return false;
  *out = result_;
  return true;
}

void PerceptionEngine::worker_loop_() {
  ZYRA_LOGI("engine worker thread started");

  while (!stop_.load(std::memory_order_relaxed)) {
    Pending p;
    {
      std::unique_lock<std::mutex> lk(pending_mu_);
      pending_cv_.wait(lk, [this] {
        return stop_.load(std::memory_order_relaxed) || pending_.has_data;
      });
      if (stop_.load(std::memory_order_relaxed)) break;
      p = std::move(pending_);
      pending_.has_data = false;
    }

    // --- Reconstruct a FrameView over the copied buffers. ----------------
    FrameView fv{};
    fv.y = p.y_buf.data();
    fv.width = p.width;
    fv.height = p.height;
    fv.y_row_stride = p.width;
    fv.uv_pixel_stride = p.uv_pixel_stride;
    fv.uv_row_stride = p.uv_row_stride;
    fv.rotation_deg = p.rotation;

    if (p.uv_pixel_stride == 2) {
      // Preserved original byte ordering. V=buf[0]/U=buf[1] for NV21,
      // U=buf[0]/V=buf[1] for NV12.
      if (p.is_nv21) {
        fv.v = p.uv_buf.data();
        fv.u = p.uv_buf.data() + 1;
      } else {
        fv.u = p.uv_buf.data();
        fv.v = p.uv_buf.data() + 1;
      }
    } else {
      // I420 — U then V planes in uv_buf.
      const int plane = (p.width / 2) * (p.height / 2);
      fv.u = p.uv_buf.data();
      fv.v = p.uv_buf.data() + plane;
    }

    // --- Run YOLO detection + road segmentation in PARALLEL. ---------------
    // YOLO runs on Vulkan GPU; TwinLiteNet runs on CPU threads.
    // They don't compete for the same compute resources, so overlapping
    // them effectively hides the seg latency.
    std::vector<Detection> dets;
    RoadSegResult seg;
    std::vector<Lane> lanes;

    if (road_segmentor_.loaded()) {
      // Launch seg on a background thread (CPU) while YOLO runs on GPU.
      auto seg_future = std::async(std::launch::async, [this, &fv]() {
        return road_segmentor_.segment(fv);
      });

      // YOLO detection on the main worker thread (Vulkan GPU).
      try {
        dets = detector_.detect(fv);
      } catch (...) {
        ZYRA_LOGE("detector threw — dropping frame %llu",
                  static_cast<unsigned long long>(p.frame_id));
        seg_future.wait();  // don't leak the async
        continue;
      }

      // Collect seg result (should already be done or nearly done).
      try {
        seg = seg_future.get();
        lanes = std::move(seg.synthetic_lanes);
      } catch (...) {
        ZYRA_LOGE("road segmentor threw — emitting empty lanes for frame %llu",
                  static_cast<unsigned long long>(p.frame_id));
        lanes.clear();
      }
    } else {
      // No seg model — sequential YOLO then Hough fallback.
      try {
        dets = detector_.detect(fv);
      } catch (...) {
        ZYRA_LOGE("detector threw — dropping frame %llu",
                  static_cast<unsigned long long>(p.frame_id));
        continue;
      }
      try {
        lanes = lane_detector_.detect(p.y_buf.data(), p.width, p.height,
                                      p.width);
      } catch (...) {
        ZYRA_LOGE("lane detector threw — emitting empty lanes for frame %llu",
                  static_cast<unsigned long long>(p.frame_id));
        lanes.clear();
      }
    }

    // --- Snapshot IPM under the lock so stages work off a consistent
    //     projection even if set_camera_geometry fires mid-frame.
    Ipm ipm_snapshot;
    {
      std::lock_guard<std::mutex> lk(ipm_mu_);
      ipm_snapshot = ipm_;
    }
    const Ipm* ipm_for_stages =
        ipm_snapshot.calibrated() ? &ipm_snapshot : nullptr;

    // --- Phase 11: snapshot ego state once per frame. --------------------
    EgoState ego_snap;
    {
      std::lock_guard<std::mutex> lk(ego_mu_);
      ego_snap = ego_state_;
    }

    // --- Phase 7 / 10 / 11: temporal tracker + lane assist. -------------
    try {
      lane_tracker_.update(lanes, p.width, p.height);
      lane_assist_.update(lane_tracker_, p.width, p.height, ipm_for_stages,
                          ego_snap.speed_mps, ego_snap.yaw_rate_deg_s);
    } catch (...) {
      ZYRA_LOGE("lane tracker/assist threw on frame %llu",
                static_cast<unsigned long long>(p.frame_id));
    }

    // --- Phase 8 / 10 / 11: object tracker + forward collision warning. -
    try {
      object_tracker_.update(dets, p.timestamp_ms);
      fcw_.update(object_tracker_.tracks(), p.width, p.height,
                  ipm_for_stages, p.timestamp_ms, ego_snap.speed_mps);
    } catch (...) {
      ZYRA_LOGE("object tracker / fcw threw on frame %llu",
                static_cast<unsigned long long>(p.frame_id));
    }

    // --- Phase 15: shadow-mode L2 planner. --------------------------------
    try {
      const FcwSnapshot& fcw_snap = fcw_.state();
      const LaneAssistState& la_snap = lane_assist_.state();
      shadow_planner_.compute(
          ego_snap.speed_mps,
          fcw_snap.critical_distance_m,
          fcw_snap.range_rate_mps,
          la_snap.lateral_offset_m,
          la_snap.lateral_velocity_px_s * 0.001f,  // rough px→m approx
          0.0f);  // curvature feed-forward placeholder
    } catch (...) {
      ZYRA_LOGE("shadow planner threw on frame %llu",
                static_cast<unsigned long long>(p.frame_id));
    }

    // --- Publish the batch. ---------------------------------------------
    ZyraDetectionBatch batch{};
    batch.frame_id = p.frame_id;
    batch.timestamp_ms = p.timestamp_ms;
    const int n = std::min<int>(static_cast<int>(dets.size()),
                                ZYRA_MAX_DETECTIONS);
    batch.count = n;
    batch.rotation_deg = p.rotation;
    batch.orig_width = p.width;
    batch.orig_height = p.height;
    batch.preprocess_ms = detector_.last_preprocess_ms();
    batch.infer_ms = detector_.last_infer_ms();
    batch.nms_ms = detector_.last_nms_ms();
    batch.vulkan_active = detector_.vulkan_active() ? 1 : 0;
    for (int i = 0; i < n; ++i) {
      batch.detections[i] = ZyraDetection{
          dets[i].x1, dets[i].y1, dets[i].x2, dets[i].y2,
          dets[i].class_id, dets[i].confidence,
      };
    }
    const int ln = std::min<int>(static_cast<int>(lanes.size()),
                                 ZYRA_MAX_LANES);
    batch.lane_count = ln;
    batch.lane_ms = lane_detector_.last_ms();
    for (int i = 0; i < ln; ++i) {
      batch.lanes[i] = ZyraLane{
          lanes[i].x1, lanes[i].y1, lanes[i].x2, lanes[i].y2,
          lanes[i].side, lanes[i].confidence,
      };
    }

    // Phase 7 — tracker curves + assist state.
    const auto& tracked = lane_tracker_.curves();
    const int cc = std::min<int>(static_cast<int>(tracked.size()),
                                 ZYRA_MAX_LANE_CURVES);
    batch.curve_count = cc;
    batch.tracker_ms = lane_tracker_.last_ms();
    for (int i = 0; i < cc; ++i) {
      batch.curves[i].coeffs[0] = tracked[i].coeffs[0];
      batch.curves[i].coeffs[1] = tracked[i].coeffs[1];
      batch.curves[i].coeffs[2] = tracked[i].coeffs[2];
      batch.curves[i].y_top = tracked[i].y_top;
      batch.curves[i].y_bot = tracked[i].y_bot;
      batch.curves[i].side = tracked[i].side;
      batch.curves[i].confidence = tracked[i].confidence;
      batch.curves[i].locked = tracked[i].locked;
      batch.curves[i].reserved = 0;
    }
    const auto& st = lane_assist_.state();
    batch.assist.ldw_state = st.ldw_state;
    batch.assist.lateral_offset_px = st.lateral_offset_px;
    batch.assist.lateral_velocity_px_s = st.lateral_velocity_px_s;
    batch.assist.ttlc_s = st.ttlc_s;
    batch.assist.curvature_px = st.curvature_px;
    batch.assist.armed = st.armed;
    batch.assist.dist_to_line_px = st.dist_to_line_px;
    batch.assist.drift_side = st.drift_side;
    batch.assist.lateral_offset_m = st.lateral_offset_m;
    batch.assist.dist_to_line_m = st.dist_to_line_m;

    // --- Phase 8: tracks + FCW pack. -------------------------------------
    const std::vector<TrackedObject> live_tracks = object_tracker_.tracks();
    const int tc = std::min<int>(static_cast<int>(live_tracks.size()),
                                 ZYRA_MAX_TRACKS);
    batch.track_count = tc;
    batch.object_tracker_ms = object_tracker_.last_ms();
    for (int i = 0; i < tc; ++i) {
      const TrackedObject& t = live_tracks[i];
      batch.tracks[i].id = t.id;
      batch.tracks[i].class_id = t.class_id;
      batch.tracks[i].x1 = t.x1; batch.tracks[i].y1 = t.y1;
      batch.tracks[i].x2 = t.x2; batch.tracks[i].y2 = t.y2;
      batch.tracks[i].vx_px_s = t.vx_px_s;
      batch.tracks[i].vy_px_s = t.vy_px_s;
      batch.tracks[i].age_frames = t.age_frames;
      batch.tracks[i].confidence = t.confidence;
      batch.tracks[i].height_rate_per_s = t.height_rate_per_s;
    }
    const FcwSnapshot& f = fcw_.state();
    batch.fcw.state = f.state;
    batch.fcw.ttc_s = f.ttc_s;
    batch.fcw.critical_track_id = f.critical_track_id;
    batch.fcw.critical_class_id = f.critical_class_id;
    batch.fcw.critical_bbox_h_frac = f.critical_bbox_h_frac;
    batch.fcw.critical_distance_m = f.critical_distance_m;
    batch.fcw.range_rate_mps = f.range_rate_mps;
    batch.fcw_ms = 0.0f;  // tracker + fcw already budgeted under object_tracker_ms

    // Phase 11 — echo ego state so Dart HUD can read back what the engine
    // used for speed-gating this frame.
    batch.ego_speed_mps = ego_snap.speed_mps;
    batch.ego_pitch_deg = ego_snap.pitch_deg;
    batch.ego_yaw_rate_deg_s = ego_snap.yaw_rate_deg_s;

    // Phase 15 — shadow plan.
    const ShadowPlan& sp = shadow_planner_.plan();
    batch.shadow_brake_mps2 = sp.brake_mps2;
    batch.shadow_steer_rad = sp.steer_rad;
    batch.shadow_brake_active = sp.brake_active;
    batch.shadow_steer_active = sp.steer_active;

    // Phase 16 — road segmentation mask.
    batch.seg_infer_ms = seg.inference_ms;
    batch.seg_post_ms = seg.postprocess_ms;
    batch.seg_has_driveable = seg.has_driveable ? 1 : 0;
    batch.seg_mask_w = seg.mask_w;
    batch.seg_mask_h = seg.mask_h;
    if (seg.has_driveable) {
      std::memcpy(batch.seg_driveable_mask, seg.driveable_mask,
                  sizeof(seg.driveable_mask));
    }

    {
      std::lock_guard<std::mutex> lk(result_mu_);
      result_ = batch;
      result_valid_ = true;
    }

    // --- FPS tracking: sliding 1-second window. --------------------------
    const double t = now_ms();
    {
      std::lock_guard<std::mutex> lk(fps_mu_);
      fps_samples_ms_.push_back(t);
      while (!fps_samples_ms_.empty() && fps_samples_ms_.front() < t - 1000.0) {
        fps_samples_ms_.pop_front();
      }
      avg_fps_.store(static_cast<float>(fps_samples_ms_.size()),
                     std::memory_order_relaxed);
    }
  }

  ZYRA_LOGI("engine worker thread exiting");
}

}  // namespace zyra

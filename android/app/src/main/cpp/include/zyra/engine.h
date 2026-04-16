// Phase 4 — Perception engine: single detector + producer/consumer thread
// + bounded (depth-1) frame queue + mutex-guarded result slot.
//
// Design matches the bounded-queue realtime contract described in the
// desktop Zyra CLAUDE.md §19: the most recently submitted frame always
// wins, older frames are dropped silently. This keeps end-to-end latency
// bounded even when inference briefly falls behind camera delivery.

#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "zyra/detector.h"
#include "zyra/fcw.h"
#include "zyra/ffi_api.h"  // ZyraDetectionBatch
#include "zyra/ipm.h"
#include "zyra/lane.h"
#include "zyra/lane_assist.h"
#include "zyra/lane_tracker.h"
#include "zyra/object_tracker.h"

namespace zyra {

class PerceptionEngine {
 public:
  PerceptionEngine();
  ~PerceptionEngine();

  PerceptionEngine(const PerceptionEngine&) = delete;
  PerceptionEngine& operator=(const PerceptionEngine&) = delete;

  // Load the NCNN model. Starts the worker thread on first successful call.
  // Returns:  0 ok / -2 null path / -3 load failed.
  int load_model(const std::string& param_path,
                 const std::string& bin_path,
                 bool use_vulkan);

  // Force-compile Vulkan shaders by running a single synthetic inference.
  // Must be called after load_model. Returns 0 ok / -1 not loaded.
  int warmup();

  void set_class_threshold(int zyra_class_id, float t);
  void set_conf_threshold(float t);
  void set_nms_iou(float iou);

  // Phase 10 — camera optics + mount geometry. Pushed through to the
  // IPM module so downstream stages (FCW range, lane-assist metres) can
  // project pixels onto the ground plane. Returns 0 ok, -2 bad inputs.
  int set_camera_geometry(float mount_h_m, float pitch_deg, float hfov_deg,
                          int frame_w, int frame_h);

  // Phase 11 — push ego speed + IMU data. Thread-safe, ~1 Hz from Dart.
  void set_ego_state(float ego_speed_mps, float pitch_deg,
                     float yaw_rate_deg_s);

  // Submit a YUV_420_888 frame. The engine copies what it needs before
  // returning; callers may free plane pointers immediately.
  int submit(const uint8_t* y, const uint8_t* u, const uint8_t* v,
             int width, int height,
             int y_row_stride, int uv_row_stride, int uv_pixel_stride,
             int rotation_deg, uint64_t frame_id, double timestamp_ms);

  // Copy the most recent batch into `out`. Returns true if populated.
  bool poll(ZyraDetectionBatch* out);

  // Rolling 1-second average of completed inferences per second.
  float avg_fps() const { return avg_fps_.load(std::memory_order_relaxed); }

  // 1 / 0 / -1 (not loaded).
  int vulkan_active() const;

 private:
  // One-slot pending queue. The worker holds `pending_mu_` only long enough
  // to move fields out; inference runs unlocked.
  struct Pending {
    std::vector<uint8_t> y_buf;   // contiguous width*height
    std::vector<uint8_t> uv_buf;  // variant-dependent — see submit()
    int width = 0;
    int height = 0;
    int uv_row_stride = 0;
    int uv_pixel_stride = 0;   // 1 = I420, 2 = NV12/NV21
    int rotation = 0;
    bool is_nv21 = false;      // only meaningful when uv_pixel_stride == 2
    uint64_t frame_id = 0;
    double timestamp_ms = 0.0;
    bool has_data = false;
  };

  void worker_loop_();

  NcnnYoloV8Detector detector_;
  HoughLaneDetector lane_detector_;
  LaneTracker lane_tracker_;
  LaneAssist lane_assist_;
  ObjectTracker object_tracker_;
  ForwardCollisionWarning fcw_;
  Ipm ipm_;
  std::mutex ipm_mu_;  // guards ipm_ across set_camera_geometry / worker reads

  // Phase 11 — ego-vehicle state pushed from Dart sensor layer.
  struct EgoState {
    float speed_mps = 0.0f;
    float pitch_deg = 0.0f;
    float yaw_rate_deg_s = 0.0f;
  };
  std::mutex ego_mu_;
  EgoState ego_state_;
  std::thread worker_;
  std::atomic<bool> stop_{false};
  std::atomic<bool> loaded_{false};

  std::mutex pending_mu_;
  std::condition_variable pending_cv_;
  Pending pending_;

  std::mutex result_mu_;
  ZyraDetectionBatch result_{};
  bool result_valid_ = false;

  std::mutex fps_mu_;
  std::deque<double> fps_samples_ms_;  // completion timestamps (monotonic ms)
  std::atomic<float> avg_fps_{0.0f};
};

}  // namespace zyra

// Phase 10 — Inverse Perspective Mapping.
//
// Projects image-plane pixels to a flat-ground-plane world frame. The
// world frame is centred under the camera:
//   +z = straight ahead (metres)
//   +x = right of ego (metres)
//   y  = 0 (camera height above road; kept implicit)
//
// We stay with a simplified pinhole-on-ground-plane model. It assumes:
//   * Flat ground below the camera.
//   * Camera yaw ≈ 0 (looking straight ahead).
//   * Square pixels (fy = fx).
// Pitch is supported so a dashboard-mounted phone angled toward the
// hood can still project correctly.
//
// Focal length is derived from HFoV rather than read from EXIF, since
// we can't trust camera intrinsics to survive the image pipeline — the
// Flutter `camera` plugin picks a resolution that may not match the
// sensor's full FoV. HFoV is treated as a vehicle-profile parameter so
// users with unusual mounts can override per vehicle in the future.
//
// The projector is null-safe: `project_ground` returns a sentinel
// (positive infinity) above the horizon, and `calibrated()` gates
// callers that want to fall back to pixel-space behaviour.

#pragma once

#include <cmath>
#include <cstdint>
#include <limits>

namespace zyra {

struct WorldPoint {
  float x_m;  // lateral — positive = right of ego
  float z_m;  // longitudinal — positive = ahead of ego
};

class Ipm {
 public:
  Ipm() = default;

  // Install (or re-install) the projector from vehicle + optics
  // geometry. `frame_w/_h` are the sensor-native dimensions of the
  // image the tracker + FCW will pass pixels in (i.e. pre-rotation,
  // landscape). Pitch is positive when the camera tilts up, negative
  // when it tilts down toward the hood — the convention a dash-cam
  // installer would describe.
  void set_geometry(float mount_h_m, float pitch_deg, float hfov_deg,
                    int frame_w, int frame_h) {
    if (frame_w <= 0 || frame_h <= 0 || mount_h_m <= 0.0f ||
        hfov_deg <= 0.0f || hfov_deg >= 180.0f) {
      calibrated_ = false;
      return;
    }
    mount_h_m_ = mount_h_m;
    pitch_rad_ = pitch_deg * kPi_ / 180.0f;
    const float hfov_rad = hfov_deg * kPi_ / 180.0f;
    fx_ = 0.5f * static_cast<float>(frame_w) /
          std::tan(0.5f * hfov_rad);
    fy_ = fx_;
    cx_ = 0.5f * static_cast<float>(frame_w);
    cy_ = 0.5f * static_cast<float>(frame_h);
    calibrated_ = true;
  }

  bool calibrated() const { return calibrated_; }
  float mount_h_m() const { return mount_h_m_; }

  // Phase 11 — update pitch without re-deriving the focal length.
  // Call from the IMU sensor path when the device tilt changes.
  void set_pitch(float pitch_deg) {
    pitch_rad_ = pitch_deg * kPi_ / 180.0f;
  }

  // Project image pixel (u, v) to the ground plane. Returns {+INF,
  // +INF} if the pixel is at or above the apparent horizon, which is
  // equivalent to "no finite ground intersection". Callers must check
  // `isfinite(z_m)` before using the result.
  WorldPoint project_ground(float u, float v) const {
    if (!calibrated_) return WorldPoint{kInf_, kInf_};
    // Ray in camera frame (before pitch): d = (x_n, y_n, 1).
    const float x_n = (u - cx_) / fx_;
    const float y_n = (v - cy_) / fy_;
    // Rotate about X axis by -pitch_ (camera pitched up ⇒ ground appears
    // lower in image).
    const float cp = std::cos(pitch_rad_);
    const float sp = std::sin(pitch_rad_);
    const float ry = y_n * cp - sp;
    const float rz = y_n * sp + cp;
    // Ground plane at y = -mount_h_m in camera frame. We want t such
    // that (ray origin y = 0) + t*ry = -mount_h_m. Ground only visible
    // when ry > 0 (point below horizon after pitch rotation).
    if (ry <= 1e-4f) return WorldPoint{kInf_, kInf_};
    const float t = mount_h_m_ / ry;
    const float x_world = t * x_n;
    const float z_world = t * rz;
    if (z_world <= 0.0f) return WorldPoint{kInf_, kInf_};
    return WorldPoint{x_world, z_world};
  }

  // Straight-line range, metres, from camera to the ground point the
  // pixel rests on. +INF when the pixel is above the horizon.
  float range_m(float u, float v) const {
    const WorldPoint p = project_ground(u, v);
    if (!std::isfinite(p.z_m)) return kInf_;
    return std::sqrt(p.x_m * p.x_m + p.z_m * p.z_m);
  }

 private:
  static constexpr float kPi_ = 3.14159265358979323846f;
  static constexpr float kInf_ = std::numeric_limits<float>::infinity();

  bool calibrated_ = false;
  float mount_h_m_ = 1.25f;
  float pitch_rad_ = 0.0f;
  float fx_ = 0.0f;
  float fy_ = 0.0f;
  float cx_ = 0.0f;
  float cy_ = 0.0f;
};

}  // namespace zyra

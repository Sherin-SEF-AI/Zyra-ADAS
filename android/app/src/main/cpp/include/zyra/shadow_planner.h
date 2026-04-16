// Phase 15 — Shadow-Mode L2 Planner.
//
// Computes what a theoretical L2 system WOULD command (brake, steer)
// given the current perception state. The output is purely advisory —
// displayed on the HUD as "L2: BRAKE" / "L2: STEER" badges. The app
// never actuates anything.
//
// Longitudinal: if the lead vehicle is closing and range < safe-stop
//   distance, compute required decel from v²/(2d), clamp to
//   [comfort_decel, max_decel].
//
// Lateral: bicycle-model steering angle from lateral offset +
//   velocity, clamped to the steer rate limit.
//
// ~20 FLOPs per frame — runs inside the existing worker thread after
// the FCW stage.

#pragma once

#include <algorithm>
#include <cmath>

namespace zyra {

struct VehicleDynamics {
  float wheelbase_m = 2.70f;
  float max_decel_mps2 = 7.5f;
  float comfort_decel_mps2 = 3.0f;
  float max_lateral_accel_mps2 = 4.0f;
  float steer_rate_limit_rad_s = 0.6f;
};

struct ShadowPlan {
  float brake_mps2 = 0.0f;   // required deceleration, m/s² (positive = braking)
  float steer_rad = 0.0f;    // desired steering angle, radians (positive = left)
  int32_t brake_active = 0;  // 1 if shadow brake would engage
  int32_t steer_active = 0;  // 1 if shadow steer would engage
};

class ShadowPlanner {
 public:
  ShadowPlanner() = default;

  void set_dynamics(const VehicleDynamics& d) { dyn_ = d; }

  // Compute the shadow plan for the current frame.
  //   ego_speed_mps  — from GPS/IMU ego state
  //   range_m        — ground range to critical target (+INF = no target)
  //   range_rate_mps — closing rate (positive = closing)
  //   lat_offset_m   — signed lateral offset from lane centre (NaN = n/a)
  //   lat_vel_mps    — lateral velocity in m/s (NaN = n/a; approximated
  //                    from px velocity + IPM scale when available)
  //   curvature_inv  — 1/R of the lane ahead, 1/metres (0 = straight)
  void compute(float ego_speed_mps, float range_m, float range_rate_mps,
               float lat_offset_m, float lat_vel_mps, float curvature_inv) {
    plan_ = ShadowPlan{};

    // ---- Longitudinal: safe-stop braking --------------------------------
    if (std::isfinite(range_m) && range_m > 0.0f &&
        range_rate_mps > 0.5f && ego_speed_mps > 1.0f) {
      // Distance needed to stop at comfort decel.
      const float v = ego_speed_mps;
      const float safe_dist =
          (v * v) / (2.0f * dyn_.comfort_decel_mps2) + 2.0f;  // +2m margin
      if (range_m < safe_dist) {
        // Required decel to stop in remaining range.
        const float required = (v * v) / (2.0f * std::max(range_m, 0.5f));
        plan_.brake_mps2 =
            std::clamp(required, dyn_.comfort_decel_mps2, dyn_.max_decel_mps2);
        plan_.brake_active = 1;
      }
    }

    // ---- Lateral: bicycle-model corrective steer ------------------------
    if (std::isfinite(lat_offset_m) && ego_speed_mps > 5.0f) {
      const float lat_v =
          std::isfinite(lat_vel_mps) ? lat_vel_mps : 0.0f;
      // PD-style: proportional on offset + derivative on velocity.
      const float kp = 0.3f;
      const float kd = 0.15f;
      float desired = kp * lat_offset_m + kd * lat_v;
      // Add feed-forward from lane curvature.
      if (std::isfinite(curvature_inv)) {
        desired += dyn_.wheelbase_m * curvature_inv;
      }
      // Convert to steering angle via bicycle model: delta = L * kappa.
      // Here `desired` is already in lateral-acceleration-like units
      // from the PD, so we convert: delta = atan(L * ay / v²).
      const float v2 = ego_speed_mps * ego_speed_mps;
      float delta = std::atan2(dyn_.wheelbase_m * desired, v2);
      // Clamp by steer rate limit (assume 1 frame = ~0.1s).
      const float max_delta = dyn_.steer_rate_limit_rad_s * 0.1f;
      delta = std::clamp(delta, -max_delta, max_delta);
      if (std::abs(delta) > 0.005f) {
        plan_.steer_rad = delta;
        plan_.steer_active = 1;
      }
    }
  }

  const ShadowPlan& plan() const { return plan_; }

 private:
  VehicleDynamics dyn_;
  ShadowPlan plan_;
};

}  // namespace zyra

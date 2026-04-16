import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gps_service.dart';
import 'imu_service.dart';

/// Unified ego-vehicle state combining the latest GPS + IMU readings.
/// Single source of truth for speed, pitch, and yaw rate consumed by the
/// engine and UI.
class EgoState {
  const EgoState({
    this.speedMps = 0.0,
    this.pitchDeg = 0.0,
    this.yawRateDegPerS = 0.0,
    this.gpsAvailable = false,
    this.imuAvailable = false,
  });

  final double speedMps;
  final double pitchDeg;
  final double yawRateDegPerS;
  final bool gpsAvailable;
  final bool imuAvailable;

  double get speedKmh => speedMps * 3.6;
}

/// Combines the latest GPS and IMU snapshots into a single [EgoState].
final Provider<EgoState> egoStateProvider = Provider<EgoState>((Ref ref) {
  final AsyncValue<GpsSnapshot> gps = ref.watch(gpsSnapshotProvider);
  final AsyncValue<ImuSnapshot> imu = ref.watch(imuSnapshotProvider);

  return EgoState(
    speedMps: gps.valueOrNull?.speedMps ?? 0.0,
    pitchDeg: imu.valueOrNull?.pitchDeg ?? 0.0,
    yawRateDegPerS: imu.valueOrNull?.yawRateDegPerS ?? 0.0,
    gpsAvailable: gps.hasValue,
    imuAvailable: imu.hasValue,
  );
});

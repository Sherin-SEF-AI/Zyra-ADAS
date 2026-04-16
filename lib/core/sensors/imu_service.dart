import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Fused pitch + yaw rate from accelerometer + gyroscope.
class ImuSnapshot {
  const ImuSnapshot({
    required this.pitchDeg,
    required this.yawRateDegPerS,
  });

  /// Estimated device pitch in degrees. 0 = level, positive = tilted up.
  final double pitchDeg;

  /// Yaw rotation rate from the gyroscope, degrees/second.
  /// Positive = turning left (counter-clockwise when viewed from above).
  final double yawRateDegPerS;
}

/// Streams IMU snapshots at ~2 Hz (throttled from the raw 50 Hz sensor
/// stream). Uses a simple complementary filter to fuse accelerometer
/// gravity pitch with gyroscope integration.
final StreamProvider<ImuSnapshot> imuSnapshotProvider =
    StreamProvider<ImuSnapshot>((Ref ref) {
  return _ImuFusion().stream;
});

class _ImuFusion {
  static const double _kGyroAlpha = 0.98;
  static const double _kAccelAlpha = 1.0 - _kGyroAlpha;
  static const double _kRad2Deg = 180.0 / math.pi;
  static const double _kEmitThresholdDeg = 0.3;
  static const Duration _kMinEmitInterval = Duration(milliseconds: 500);

  final StreamController<ImuSnapshot> _controller =
      StreamController<ImuSnapshot>.broadcast();
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double _pitchDeg = 0.0;
  double _lastEmittedPitch = double.nan;
  double _yawRateDegPerS = 0.0;
  DateTime? _lastGyroTs;
  DateTime _lastEmitTs = DateTime(2000);

  Stream<ImuSnapshot> get stream {
    _start();
    return _controller.stream;
  }

  void _start() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_onAccel);
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_onGyro);

    _controller.onCancel = _dispose;
  }

  void _onAccel(AccelerometerEvent e) {
    // Pitch from gravity: atan2(ax, sqrt(ay² + az²)).
    final double accelPitch =
        math.atan2(e.x, math.sqrt(e.y * e.y + e.z * e.z)) * _kRad2Deg;
    _pitchDeg = _kGyroAlpha * _pitchDeg + _kAccelAlpha * accelPitch;
    _maybeEmit();
  }

  void _onGyro(GyroscopeEvent e) {
    final DateTime now = DateTime.now();
    if (_lastGyroTs != null) {
      final double dt =
          now.difference(_lastGyroTs!).inMicroseconds / 1e6;
      if (dt > 0 && dt < 0.5) {
        // Integrate pitch from gyro X axis (phone in landscape-left:
        // X points along the direction of travel).
        _pitchDeg += e.x * _kRad2Deg * dt;
        // Complementary blend happens in _onAccel.
      }
    }
    _lastGyroTs = now;
    _yawRateDegPerS = e.z * _kRad2Deg;
    _maybeEmit();
  }

  void _maybeEmit() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastEmitTs) < _kMinEmitInterval) return;
    if (_lastEmittedPitch.isFinite &&
        (_pitchDeg - _lastEmittedPitch).abs() < _kEmitThresholdDeg) {
      return;
    }
    _lastEmitTs = now;
    _lastEmittedPitch = _pitchDeg;
    _controller.add(ImuSnapshot(
      pitchDeg: _pitchDeg,
      yawRateDegPerS: _yawRateDegPerS,
    ));
  }

  void _dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _controller.close();
  }
}

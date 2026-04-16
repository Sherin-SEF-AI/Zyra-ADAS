import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Snapshot of GPS state at a single instant.
class GpsSnapshot {
  const GpsSnapshot({
    required this.speedMps,
    required this.headingDeg,
    required this.lat,
    required this.lon,
    required this.timestamp,
  });

  /// Speed in metres/second from the platform fused-location provider.
  /// 0 when stationary or unavailable.
  final double speedMps;

  /// Compass heading in degrees [0, 360). -1 when unavailable.
  final double headingDeg;

  final double lat;
  final double lon;
  final DateTime timestamp;

  double get speedKmh => speedMps * 3.6;
}

/// Streams GPS snapshots at ~1 Hz. Emits only when location permission is
/// already granted — the drive screen handles the permission request before
/// this provider is first read.
final StreamProvider<GpsSnapshot> gpsSnapshotProvider =
    StreamProvider<GpsSnapshot>((Ref ref) {
  final LocationSettings settings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    intervalDuration: const Duration(seconds: 1),
    distanceFilter: 0,
  );

  return Geolocator.getPositionStream(locationSettings: settings).map(
    (Position p) => GpsSnapshot(
      speedMps: p.speed < 0 ? 0.0 : p.speed,
      headingDeg: p.heading,
      lat: p.latitude,
      lon: p.longitude,
      timestamp: p.timestamp,
    ),
  );
});

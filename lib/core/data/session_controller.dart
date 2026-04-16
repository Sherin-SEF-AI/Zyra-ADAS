// Phase 13 — drive-session lifecycle controller.
//
// Manages trip creation/finalization, event buffering, frame-stat sampling,
// and GPS point accumulation. All DB writes are batched to minimise I/O
// during a live drive session:
//   - Events: flushed every 5 seconds.
//   - Frame stats: flushed every 10 seconds.
//   - GPS track: accumulated in memory, zlib-compressed on trip end.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/zyra_detection.dart';
import '../sensors/ego_state.dart';
import '../sensors/gps_service.dart';
import '../../features/vehicle_select/data/vehicle_profile.dart';
import 'trip_models.dart';
import 'trip_repository.dart';

/// Riverpod provider for the session controller.
final StateNotifierProvider<SessionController, int?> sessionControllerProvider =
    StateNotifierProvider<SessionController, int?>((Ref ref) {
  return SessionController();
});

/// State = the current trip ID (null when no session is active).
class SessionController extends StateNotifier<int?> {
  SessionController() : super(null);

  final TripRepository _repo = TripRepository.instance;

  // Buffers flushed periodically.
  final List<TripEvent> _eventBuffer = <TripEvent>[];
  final List<FrameStat> _statBuffer = <FrameStat>[];
  final List<GpsPoint> _gpsPoints = <GpsPoint>[];

  Timer? _eventFlushTimer;
  Timer? _statFlushTimer;
  DateTime? _lastStatTs;

  /// Start a new drive session.
  Future<void> start(VehicleProfile profile) async {
    if (state != null) return; // already active
    try {
      final int tripId = await _repo.createTrip(
        vehicleProfileId: profile.id,
        vehicleProfileJson: profile.encode(),
      );
      state = tripId;

      _eventFlushTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _flushEvents(),
      );
      _statFlushTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _flushStats(),
      );
    } catch (e) {
      debugPrint('[Session] start failed: $e');
    }
  }

  /// Stop the current drive session and finalize the trip.
  Future<void> stop() async {
    final int? tripId = state;
    if (tripId == null) return;

    _eventFlushTimer?.cancel();
    _statFlushTimer?.cancel();
    _eventFlushTimer = null;
    _statFlushTimer = null;

    // Final flush of any remaining buffered data.
    await _flushEvents();
    await _flushStats();

    try {
      await _repo.endTrip(tripId, _gpsPoints);
    } catch (e) {
      debugPrint('[Session] endTrip failed: $e');
    }

    _eventBuffer.clear();
    _statBuffer.clear();
    _gpsPoints.clear();
    _lastStatTs = null;
    state = null;
  }

  // ---------------------------------------------------------------------------
  //  Event recording
  // ---------------------------------------------------------------------------

  /// Record an ADAS event (called from haptic callbacks on rising transitions).
  void recordEvent(String type, {String? metadataJson}) {
    final int? tripId = state;
    if (tripId == null) return;
    _eventBuffer.add(TripEvent(
      id: null,
      tripId: tripId,
      timestamp: DateTime.now(),
      type: type,
      metadataJson: metadataJson,
    ));
  }

  // ---------------------------------------------------------------------------
  //  Frame stats — throttled to ~1 Hz
  // ---------------------------------------------------------------------------

  /// Sample frame stats. Internally throttled to 1 Hz.
  void recordFrameStats(ZyraBatch batch, EgoState ego, double fps) {
    final int? tripId = state;
    if (tripId == null) return;

    final DateTime now = DateTime.now();
    if (_lastStatTs != null &&
        now.difference(_lastStatTs!).inMilliseconds < 1000) {
      return;
    }
    _lastStatTs = now;

    _statBuffer.add(FrameStat(
      id: null,
      tripId: tripId,
      timestamp: now,
      fps: fps,
      inferMs: batch.inferMs,
      detectionCount: batch.detections.length,
      trackCount: batch.tracks.length,
      speedKmh: ego.speedKmh,
      pitchDeg: ego.pitchDeg,
    ));
  }

  // ---------------------------------------------------------------------------
  //  GPS point accumulation
  // ---------------------------------------------------------------------------

  /// Append a GPS sample (called at ~1 Hz from the ego timer).
  void recordGpsPoint(GpsSnapshot gps) {
    if (state == null) return;
    _gpsPoints.add(GpsPoint(
      lat: gps.lat,
      lon: gps.lon,
      speedMps: gps.speedMps,
      headingDeg: gps.headingDeg,
      timestamp: gps.timestamp,
    ));
  }

  // ---------------------------------------------------------------------------
  //  Flush helpers
  // ---------------------------------------------------------------------------

  Future<void> _flushEvents() async {
    if (_eventBuffer.isEmpty) return;
    final List<TripEvent> batch = List<TripEvent>.of(_eventBuffer);
    _eventBuffer.clear();
    try {
      await _repo.insertEvents(batch);
    } catch (e) {
      debugPrint('[Session] event flush failed: $e');
    }
  }

  Future<void> _flushStats() async {
    if (_statBuffer.isEmpty) return;
    final List<FrameStat> batch = List<FrameStat>.of(_statBuffer);
    _statBuffer.clear();
    try {
      await _repo.insertFrameStats(batch);
    } catch (e) {
      debugPrint('[Session] stat flush failed: $e');
    }
  }

  @override
  void dispose() {
    _eventFlushTimer?.cancel();
    _statFlushTimer?.cancel();
    super.dispose();
  }
}

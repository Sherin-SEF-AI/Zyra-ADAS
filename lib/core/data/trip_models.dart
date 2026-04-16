// Phase 13 — data models for session recording.

class GpsPoint {
  const GpsPoint({
    required this.lat,
    required this.lon,
    required this.speedMps,
    required this.headingDeg,
    required this.timestamp,
  });

  final double lat;
  final double lon;
  final double speedMps;
  final double headingDeg;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': lat,
        'lon': lon,
        'speed': speedMps,
        'heading': headingDeg,
        'ts': timestamp.toIso8601String(),
      };

  factory GpsPoint.fromJson(Map<String, dynamic> j) => GpsPoint(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        speedMps: (j['speed'] as num).toDouble(),
        headingDeg: (j['heading'] as num).toDouble(),
        timestamp: DateTime.parse(j['ts'] as String),
      );
}

class TripEvent {
  const TripEvent({
    required this.id,
    required this.tripId,
    required this.timestamp,
    required this.type,
    this.metadataJson,
  });

  final int? id;
  final int tripId;
  final DateTime timestamp;

  /// One of: fcw_caution, fcw_warn, fcw_alert, ldw_warn, ldw_alert
  final String type;
  final String? metadataJson;

  Map<String, dynamic> toMap() => <String, dynamic>{
        if (id != null) 'id': id,
        'trip_id': tripId,
        'timestamp': timestamp.toIso8601String(),
        'type': type,
        'metadata_json': metadataJson,
      };

  factory TripEvent.fromMap(Map<String, dynamic> m) => TripEvent(
        id: m['id'] as int?,
        tripId: m['trip_id'] as int,
        timestamp: DateTime.parse(m['timestamp'] as String),
        type: m['type'] as String,
        metadataJson: m['metadata_json'] as String?,
      );
}

class FrameStat {
  const FrameStat({
    required this.id,
    required this.tripId,
    required this.timestamp,
    required this.fps,
    required this.inferMs,
    required this.detectionCount,
    required this.trackCount,
    required this.speedKmh,
    required this.pitchDeg,
  });

  final int? id;
  final int tripId;
  final DateTime timestamp;
  final double fps;
  final double inferMs;
  final int detectionCount;
  final int trackCount;
  final double speedKmh;
  final double pitchDeg;

  Map<String, dynamic> toMap() => <String, dynamic>{
        if (id != null) 'id': id,
        'trip_id': tripId,
        'timestamp': timestamp.toIso8601String(),
        'fps': fps,
        'infer_ms': inferMs,
        'detection_count': detectionCount,
        'track_count': trackCount,
        'speed_kmh': speedKmh,
        'pitch_deg': pitchDeg,
      };

  factory FrameStat.fromMap(Map<String, dynamic> m) => FrameStat(
        id: m['id'] as int?,
        tripId: m['trip_id'] as int,
        timestamp: DateTime.parse(m['timestamp'] as String),
        fps: (m['fps'] as num).toDouble(),
        inferMs: (m['infer_ms'] as num).toDouble(),
        detectionCount: m['detection_count'] as int,
        trackCount: m['track_count'] as int,
        speedKmh: (m['speed_kmh'] as num).toDouble(),
        pitchDeg: (m['pitch_deg'] as num).toDouble(),
      );
}

class Trip {
  const Trip({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.vehicleProfileId,
    required this.vehicleProfileJson,
    this.gpsTrackBlob,
  });

  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final String vehicleProfileId;
  final String vehicleProfileJson;

  /// zlib-compressed JSON list of GpsPoint.
  final List<int>? gpsTrackBlob;

  Map<String, dynamic> toMap() => <String, dynamic>{
        if (id != null) 'id': id,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'vehicle_profile_id': vehicleProfileId,
        'vehicle_profile_json': vehicleProfileJson,
        'gps_track_blob': gpsTrackBlob,
      };

  factory Trip.fromMap(Map<String, dynamic> m) => Trip(
        id: m['id'] as int?,
        startTime: DateTime.parse(m['start_time'] as String),
        endTime: m['end_time'] != null
            ? DateTime.parse(m['end_time'] as String)
            : null,
        vehicleProfileId: m['vehicle_profile_id'] as String,
        vehicleProfileJson: m['vehicle_profile_json'] as String,
        gpsTrackBlob: m['gps_track_blob'] != null
            ? List<int>.from(m['gps_track_blob'] as List<dynamic>)
            : null,
      );
}

// Phase 13 — CRUD repository for trip session data.
//
// Batches event and stat inserts to minimize SQLite I/O during a live
// drive session. GPS points are accumulated in memory and zlib-compressed
// on trip end.

import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'trip_database.dart';
import 'trip_models.dart';

class TripRepository {
  TripRepository._();

  static final TripRepository instance = TripRepository._();

  Database? _db;

  Future<Database> get _database async {
    return _db ??= await openTripDatabase();
  }

  // ---------------------------------------------------------------------------
  //  Trips
  // ---------------------------------------------------------------------------

  /// Insert a new trip row. Returns the auto-generated trip ID.
  Future<int> createTrip({
    required String vehicleProfileId,
    required String vehicleProfileJson,
  }) async {
    final Database db = await _database;
    return db.insert('trips', <String, dynamic>{
      'start_time': DateTime.now().toIso8601String(),
      'vehicle_profile_id': vehicleProfileId,
      'vehicle_profile_json': vehicleProfileJson,
    });
  }

  /// Finalize the trip: write end time and compressed GPS track.
  Future<void> endTrip(int tripId, List<GpsPoint> gpsPoints) async {
    final Database db = await _database;
    List<int>? blob;
    if (gpsPoints.isNotEmpty) {
      final String json = jsonEncode(
        gpsPoints.map((GpsPoint p) => p.toJson()).toList(),
      );
      blob = gzip.encode(utf8.encode(json));
    }
    await db.update(
      'trips',
      <String, dynamic>{
        'end_time': DateTime.now().toIso8601String(),
        'gps_track_blob': blob,
      },
      where: 'id = ?',
      whereArgs: <int>[tripId],
    );
  }

  /// Fetch all trips, most recent first.
  Future<List<Trip>> getAllTrips() async {
    final Database db = await _database;
    final List<Map<String, dynamic>> rows = await db.query(
      'trips',
      orderBy: 'start_time DESC',
    );
    return rows.map(Trip.fromMap).toList();
  }

  /// Fetch a single trip by ID.
  Future<Trip?> getTrip(int id) async {
    final Database db = await _database;
    final List<Map<String, dynamic>> rows = await db.query(
      'trips',
      where: 'id = ?',
      whereArgs: <int>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Trip.fromMap(rows.first);
  }

  /// Decode the compressed GPS track from a trip.
  List<GpsPoint> decodeGpsTrack(List<int> blob) {
    final String json = utf8.decode(gzip.decode(blob));
    final List<dynamic> list = jsonDecode(json) as List<dynamic>;
    return list
        .map((dynamic e) => GpsPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  //  Events — batched insert
  // ---------------------------------------------------------------------------

  /// Insert a batch of events in a single transaction.
  Future<void> insertEvents(List<TripEvent> events) async {
    if (events.isEmpty) return;
    final Database db = await _database;
    final Batch batch = db.batch();
    for (final TripEvent e in events) {
      batch.insert('events', e.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Fetch all events for a trip, chronological.
  Future<List<TripEvent>> getEventsForTrip(int tripId) async {
    final Database db = await _database;
    final List<Map<String, dynamic>> rows = await db.query(
      'events',
      where: 'trip_id = ?',
      whereArgs: <int>[tripId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(TripEvent.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  //  Frame stats — batched insert
  // ---------------------------------------------------------------------------

  /// Insert a batch of frame stats in a single transaction.
  Future<void> insertFrameStats(List<FrameStat> stats) async {
    if (stats.isEmpty) return;
    final Database db = await _database;
    final Batch batch = db.batch();
    for (final FrameStat s in stats) {
      batch.insert('frame_stats', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Fetch all frame stats for a trip, chronological.
  Future<List<FrameStat>> getStatsForTrip(int tripId) async {
    final Database db = await _database;
    final List<Map<String, dynamic>> rows = await db.query(
      'frame_stats',
      where: 'trip_id = ?',
      whereArgs: <int>[tripId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(FrameStat.fromMap).toList();
  }

  /// Count events by type for a trip (for safety score calculation).
  Future<Map<String, int>> eventCountsByType(int tripId) async {
    final Database db = await _database;
    final List<Map<String, dynamic>> rows = await db.rawQuery(
      'SELECT type, COUNT(*) as cnt FROM events WHERE trip_id = ? GROUP BY type',
      <int>[tripId],
    );
    return <String, int>{
      for (final Map<String, dynamic> r in rows)
        r['type'] as String: r['cnt'] as int,
    };
  }
}

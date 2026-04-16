// Phase 13 — SQLite database for trip session recording.

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const String _kDbName = 'zyra_trips.db';
const int _kDbVersion = 1;

/// Opens (or creates) the Zyra trips database.
///
/// Safe to call multiple times — `openDatabase` caches the instance.
Future<Database> openTripDatabase() async {
  final String dbPath = p.join(await getDatabasesPath(), _kDbName);
  return openDatabase(
    dbPath,
    version: _kDbVersion,
    onCreate: (Database db, int version) async {
      await db.execute('''
        CREATE TABLE trips (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          start_time TEXT NOT NULL,
          end_time TEXT,
          vehicle_profile_id TEXT NOT NULL,
          vehicle_profile_json TEXT NOT NULL,
          gps_track_blob BLOB
        )
      ''');
      await db.execute('''
        CREATE TABLE events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL REFERENCES trips(id),
          timestamp TEXT NOT NULL,
          type TEXT NOT NULL,
          metadata_json TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE frame_stats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL REFERENCES trips(id),
          timestamp TEXT NOT NULL,
          fps REAL,
          infer_ms REAL,
          detection_count INTEGER,
          track_count INTEGER,
          speed_kmh REAL,
          pitch_deg REAL
        )
      ''');
      // Index on trip_id for fast lookups.
      await db.execute(
          'CREATE INDEX idx_events_trip ON events(trip_id)');
      await db.execute(
          'CREATE INDEX idx_stats_trip ON frame_stats(trip_id)');
    },
  );
}

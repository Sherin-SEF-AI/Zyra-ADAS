import 'package:shared_preferences/shared_preferences.dart';

import 'vehicle_profile.dart';

/// Persistence for the user's chosen vehicle profile. SharedPreferences is
/// deliberate — the profile is a single scalar struct, loaded once at app
/// start, and there's no query pattern that would benefit from a database.
class VehicleProfileRepository {
  VehicleProfileRepository(this._prefs);

  static const String _key = 'vehicle_profile_v1';

  final SharedPreferences _prefs;

  Future<VehicleProfile?> load() async {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return VehicleProfile.decode(raw);
    } catch (_) {
      // Corrupt record — treat as unset and let the UI prompt again.
      await _prefs.remove(_key);
      return null;
    }
  }

  Future<void> save(VehicleProfile profile) async {
    await _prefs.setString(_key, profile.encode());
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}

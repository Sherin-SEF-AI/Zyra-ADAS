import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/vehicle_profile.dart';
import '../data/vehicle_profile_repository.dart';

/// Async-bootstrapped SharedPreferences instance, exposed as a provider so the
/// repository can be constructed lazily without a main-level await chain.
final FutureProvider<SharedPreferences> sharedPreferencesProvider =
    FutureProvider<SharedPreferences>((Ref ref) {
  return SharedPreferences.getInstance();
});

final FutureProvider<VehicleProfileRepository> vehicleProfileRepositoryProvider =
    FutureProvider<VehicleProfileRepository>((Ref ref) async {
  final SharedPreferences prefs =
      await ref.watch(sharedPreferencesProvider.future);
  return VehicleProfileRepository(prefs);
});

/// AsyncNotifier holding the current vehicle profile (null = none chosen yet).
///
/// Exposing `null` as a valid loaded state keeps the UI simple: the select
/// screen uses `AsyncValue.when` and forwards to /drive only on non-null.
class VehicleProfileNotifier
    extends AsyncNotifier<VehicleProfile?> {
  @override
  Future<VehicleProfile?> build() async {
    final VehicleProfileRepository repo =
        await ref.watch(vehicleProfileRepositoryProvider.future);
    return repo.load();
  }

  Future<void> select(VehicleProfile profile) async {
    state = const AsyncValue<VehicleProfile?>.loading();
    try {
      final VehicleProfileRepository repo =
          await ref.read(vehicleProfileRepositoryProvider.future);
      await repo.save(profile);
      state = AsyncValue<VehicleProfile?>.data(profile);
    } catch (e, st) {
      state = AsyncValue<VehicleProfile?>.error(e, st);
    }
  }

  Future<void> clear() async {
    final VehicleProfileRepository repo =
        await ref.read(vehicleProfileRepositoryProvider.future);
    await repo.clear();
    state = const AsyncValue<VehicleProfile?>.data(null);
  }
}

final AsyncNotifierProvider<VehicleProfileNotifier, VehicleProfile?>
    vehicleProfileProvider =
    AsyncNotifierProvider<VehicleProfileNotifier, VehicleProfile?>(
  VehicleProfileNotifier.new,
);

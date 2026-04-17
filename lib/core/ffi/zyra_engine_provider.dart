import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assets/asset_bootstrap.dart';
import '../constants.dart';
import '../../features/vehicle_select/application/vehicle_profile_notifier.dart';
import '../../features/vehicle_select/data/vehicle_profile.dart';
import 'zyra_engine.dart';

/// Resolves the single shared `DynamicLibrary` handle for libzyra_perception.so.
/// Flutter loads it once per process — all FFI wrappers share this handle.
final Provider<ffi.DynamicLibrary> zyraLibraryProvider =
    Provider<ffi.DynamicLibrary>((Ref ref) {
  return ffi.DynamicLibrary.open('libzyra_perception.so');
});

/// Engine lifecycle: create → load model → warmup → apply profile thresholds
/// → expose [ZyraEngine] to the rest of the app. On dispose, tears the
/// native engine down cleanly.
final AsyncNotifierProvider<ZyraEngineNotifier, ZyraEngine>
    zyraEngineProvider =
    AsyncNotifierProvider<ZyraEngineNotifier, ZyraEngine>(
        ZyraEngineNotifier.new);

class ZyraEngineNotifier extends AsyncNotifier<ZyraEngine> {
  ZyraEngine? _engine;

  @override
  Future<ZyraEngine> build() async {
    ref.onDispose(() {
      _engine?.dispose();
      _engine = null;
    });

    final ffi.DynamicLibrary lib = ref.watch(zyraLibraryProvider);
    final ModelPaths paths = await AssetBootstrap.ensureModelsExtracted();

    final ZyraEngine engine = ZyraEngine.create(lib);
    try {
      engine.loadModel(
        paramPath: paths.paramPath,
        binPath: paths.binPath,
        useVulkan: true,
      );
      engine.warmup();

      // TwinLiteNet road segmentation — runs on CPU (Vulkan reserved for YOLO).
      try {
        engine.loadSegModel(
          paramPath: paths.segParamPath,
          binPath: paths.segBinPath,
        );
        if (kDebugMode) {
          debugPrint('[Zyra] engine: seg model loaded (CPU)');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Zyra] engine: seg model failed: $e — lane fallback');
        }
      }

      // Depth Anything V2 — NOT loaded at startup. Loaded on-demand when
      // the user opens the depth screen to avoid CPU contention on the
      // main drive pipeline.
    } catch (_) {
      engine.dispose();
      rethrow;
    }

    // Apply the current vehicle profile's class thresholds (Phase 1 scalar
    // struct doesn't tune thresholds yet, so we push the global defaults
    // from constants.dart). When thresholds move onto the profile, replace
    // this block.
    _applyDefaultThresholds(engine);

    // Push profile-specific tuning. Listen for changes so switching
    // vehicles mid-session updates thresholds and dynamics.
    _pushVehicleDynamics(engine, ref.read(vehicleProfileProvider).valueOrNull);
    ref.listen<AsyncValue<VehicleProfile?>>(vehicleProfileProvider,
        (AsyncValue<VehicleProfile?>? _,
            AsyncValue<VehicleProfile?> next) {
      next.whenData((VehicleProfile? p) {
        _pushVehicleDynamics(engine, p);
        if (p != null && kDebugMode) {
          debugPrint('[Zyra] engine: vehicle profile=${p.id}');
        }
      });
    });

    _engine = engine;
    return engine;
  }
}

void _pushVehicleDynamics(ZyraEngine engine, VehicleProfile? p) {
  if (p == null) return;
  engine.setVehicleDynamics(
    wheelbaseM: p.wheelbaseM,
    maxDecelMps2: p.maxDecelMps2,
    comfortDecelMps2: p.comfortDecelMps2,
    maxLateralAccelMps2: p.maxLateralAccelMps2,
    steerRateLimitRadPerS: p.steerRateLimitRadPerS,
  );
}

void _applyDefaultThresholds(ZyraEngine engine) {
  kClassThresholds.forEach((String className, double threshold) {
    final int id = kZyraClasses.indexOf(className);
    if (id >= 0) engine.setClassThreshold(id, threshold);
  });
  engine.setNmsIou(kDefaultNmsIou);
}

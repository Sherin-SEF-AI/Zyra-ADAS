import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Scalar vehicle profile — mirrors the desktop `zyra/vehicle/profiles.py`
/// structure. Every field is a plain scalar so the struct can later be passed
/// to the C++ engine via FFI without refactor.
///
/// Units:
///   - lengths  → metres
///   - speeds   → m/s
///   - decels   → m/s² (positive = deceleration magnitude)
///   - times    → seconds
///   - angles   → radians (unless suffixed `_deg`)
@immutable
class VehicleProfile {
  const VehicleProfile({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.wheelbaseM,
    required this.trackWidthM,
    required this.mountHeightM,
    required this.maxDecelMps2,
    required this.comfortDecelMps2,
    required this.maxLateralAccelMps2,
    required this.fcwTtcS,
    required this.aebTtcS,
    required this.steerRateLimitRadPerS,
    required this.throttleRateLimitPerS,
  });

  /// Zyra car reference profile — mid-size sedan / compact SUV. Values chosen
  /// to match the desktop `profiles.py` "car" defaults so later phases that
  /// push this struct into C++ planners produce identical outputs on identical
  /// session logs.
  factory VehicleProfile.car() => const VehicleProfile(
        id: 'car',
        displayName: 'Car',
        kind: VehicleKind.car,
        wheelbaseM: 2.70,
        trackWidthM: 1.55,
        mountHeightM: 1.25, // dashboard mount — desktop reference
        maxDecelMps2: 7.5,
        comfortDecelMps2: 3.0,
        maxLateralAccelMps2: 4.0,
        fcwTtcS: 2.6,
        aebTtcS: 1.6,
        steerRateLimitRadPerS: 0.6,
        throttleRateLimitPerS: 1.0,
      );

  /// Zyra scooter reference profile — 125cc class two-wheeler, phone on
  /// handlebar mount. Matches desktop `profiles.py` "scooter" defaults.
  factory VehicleProfile.scooter() => const VehicleProfile(
        id: 'scooter',
        displayName: 'Scooter',
        kind: VehicleKind.scooter,
        wheelbaseM: 1.30,
        trackWidthM: 0.35,
        mountHeightM: 1.05, // handlebar height, approximate
        maxDecelMps2: 5.5,
        comfortDecelMps2: 2.0,
        maxLateralAccelMps2: 5.5,
        fcwTtcS: 2.0,
        aebTtcS: 1.2,
        steerRateLimitRadPerS: 1.2,
        throttleRateLimitPerS: 2.0,
      );

  /// Canonical list of profiles the UI exposes. Order controls display order
  /// on the vehicle-select screen.
  static List<VehicleProfile> all() => <VehicleProfile>[
        VehicleProfile.car(),
        VehicleProfile.scooter(),
      ];

  final String id;
  final String displayName;
  final VehicleKind kind;

  // --- Geometry ----------------------------------------------------------
  final double wheelbaseM;
  final double trackWidthM;
  final double mountHeightM;

  // --- Dynamics limits ---------------------------------------------------
  final double maxDecelMps2;
  final double comfortDecelMps2;
  final double maxLateralAccelMps2;

  // --- ADAS thresholds ---------------------------------------------------
  final double fcwTtcS;
  final double aebTtcS;

  // --- Actuator limits (used by shadow planners in later phases) ---------
  final double steerRateLimitRadPerS;
  final double throttleRateLimitPerS;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'kind': kind.name,
        'wheelbaseM': wheelbaseM,
        'trackWidthM': trackWidthM,
        'mountHeightM': mountHeightM,
        'maxDecelMps2': maxDecelMps2,
        'comfortDecelMps2': comfortDecelMps2,
        'maxLateralAccelMps2': maxLateralAccelMps2,
        'fcwTtcS': fcwTtcS,
        'aebTtcS': aebTtcS,
        'steerRateLimitRadPerS': steerRateLimitRadPerS,
        'throttleRateLimitPerS': throttleRateLimitPerS,
      };

  factory VehicleProfile.fromJson(Map<String, dynamic> json) {
    return VehicleProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      kind: VehicleKind.values.firstWhere(
        (VehicleKind k) => k.name == json['kind'],
        orElse: () => VehicleKind.car,
      ),
      wheelbaseM: (json['wheelbaseM'] as num).toDouble(),
      trackWidthM: (json['trackWidthM'] as num).toDouble(),
      mountHeightM: (json['mountHeightM'] as num).toDouble(),
      maxDecelMps2: (json['maxDecelMps2'] as num).toDouble(),
      comfortDecelMps2: (json['comfortDecelMps2'] as num).toDouble(),
      maxLateralAccelMps2: (json['maxLateralAccelMps2'] as num).toDouble(),
      fcwTtcS: (json['fcwTtcS'] as num).toDouble(),
      aebTtcS: (json['aebTtcS'] as num).toDouble(),
      steerRateLimitRadPerS:
          (json['steerRateLimitRadPerS'] as num).toDouble(),
      throttleRateLimitPerS:
          (json['throttleRateLimitPerS'] as num).toDouble(),
    );
  }

  String encode() => jsonEncode(toJson());

  static VehicleProfile decode(String raw) =>
      VehicleProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      other is VehicleProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum VehicleKind { car, scooter, bicycle, autoRickshaw, truck }

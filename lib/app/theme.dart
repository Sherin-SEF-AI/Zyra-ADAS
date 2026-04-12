import 'package:flutter/material.dart';

/// Zyra dark theme — tuned for sunlit driving, AMOLED panels, and a primary
/// "ADAS amber" that matches the desktop reference system.
///
/// Design notes:
///   - Near-black background (`#0A0E14`) rather than pure black to avoid AMOLED
///     mura banding while still pitch-dark enough for night driving.
///   - ADAS amber `#FF6B35` for alerts / selection — high contrast on dark,
///     distinct from the reds that will be used for pedestrian bounding boxes.
///   - Cyan `#4ECDC4` as secondary / info accent — matches the per-class color
///     used for "car" bounding boxes in Phase 5.
///   - Body text minimum 18 sp (driver readability, glance-time < 0.5 s).
class ZyraTheme {
  ZyraTheme._();

  // --- Surface palette ----------------------------------------------------
  static const Color background = Color(0xFF0A0E14);
  static const Color surface = Color(0xFF12171F);
  static const Color surfaceElevated = Color(0xFF1A202B);
  static const Color outline = Color(0xFF2A313D);

  // --- Brand palette ------------------------------------------------------
  static const Color primary = Color(0xFFFF6B35); // ADAS amber
  static const Color secondary = Color(0xFF4ECDC4); // info cyan
  static const Color danger = Color(0xFFFF3131); // pedestrian / collision red
  static const Color warning = Color(0xFFFFB84D); // caution amber-yellow
  static const Color success = Color(0xFF2ECC71); // green light / go

  // --- Text palette -------------------------------------------------------
  static const Color onBackground = Color(0xFFE8ECEF);
  static const Color onSurfaceMuted = Color(0xFF8A95A5);

  static ThemeData dark() {
    final ColorScheme scheme = const ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.black,
      secondary: secondary,
      onSecondary: Colors.black,
      error: danger,
      onError: Colors.black,
      surface: surface,
      onSurface: onBackground,
      surfaceContainerHighest: surfaceElevated,
      outline: outline,
    );

    final TextTheme textTheme = const TextTheme(
      displayLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: onBackground,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: onBackground,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: onBackground,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: onBackground,
      ),
      bodyLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: onBackground,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: onBackground,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onBackground,
        letterSpacing: 0.5,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: onBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: onBackground,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          minimumSize: const Size(double.infinity, 56),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[AdasColors.defaults()],
    );
  }
}

/// Per-class bounding-box colors for the detection overlay (used in Phase 5).
///
/// Chosen so each class is visually distinct on a camera preview in daylight
/// AND at night, and so that the most safety-critical classes (pedestrian,
/// cyclist) pop first.
@immutable
class AdasColors extends ThemeExtension<AdasColors> {
  const AdasColors({
    required this.pedestrian,
    required this.bicycle,
    required this.motorcycle,
    required this.car,
    required this.truck,
    required this.bus,
    required this.autoRickshaw,
    required this.trafficLight,
    required this.trafficSign,
  });

  factory AdasColors.defaults() => const AdasColors(
        pedestrian: Color(0xFFFF3131),
        bicycle: Color(0xFFFFB84D),
        motorcycle: Color(0xFFFFD93D),
        car: Color(0xFF4ECDC4),
        truck: Color(0xFF9B59B6),
        bus: Color(0xFF9B59B6),
        autoRickshaw: Color(0xFFF39C12),
        trafficLight: Color(0xFF2ECC71),
        trafficSign: Color(0xFF3498DB),
      );

  final Color pedestrian;
  final Color bicycle;
  final Color motorcycle;
  final Color car;
  final Color truck;
  final Color bus;
  final Color autoRickshaw;
  final Color trafficLight;
  final Color trafficSign;

  /// Look up the color for a Zyra class id. Unknown ids fall back to white so
  /// a missed mapping is visually obvious.
  Color forClass(String zyraClass) {
    switch (zyraClass) {
      case 'pedestrian':
        return pedestrian;
      case 'bicycle':
        return bicycle;
      case 'motorcycle':
        return motorcycle;
      case 'car':
        return car;
      case 'truck':
        return truck;
      case 'bus':
        return bus;
      case 'auto_rickshaw':
        return autoRickshaw;
      case 'traffic_light':
        return trafficLight;
      case 'traffic_sign':
        return trafficSign;
      default:
        return Colors.white;
    }
  }

  @override
  AdasColors copyWith({
    Color? pedestrian,
    Color? bicycle,
    Color? motorcycle,
    Color? car,
    Color? truck,
    Color? bus,
    Color? autoRickshaw,
    Color? trafficLight,
    Color? trafficSign,
  }) {
    return AdasColors(
      pedestrian: pedestrian ?? this.pedestrian,
      bicycle: bicycle ?? this.bicycle,
      motorcycle: motorcycle ?? this.motorcycle,
      car: car ?? this.car,
      truck: truck ?? this.truck,
      bus: bus ?? this.bus,
      autoRickshaw: autoRickshaw ?? this.autoRickshaw,
      trafficLight: trafficLight ?? this.trafficLight,
      trafficSign: trafficSign ?? this.trafficSign,
    );
  }

  @override
  AdasColors lerp(ThemeExtension<AdasColors>? other, double t) {
    if (other is! AdasColors) return this;
    return AdasColors(
      pedestrian: Color.lerp(pedestrian, other.pedestrian, t)!,
      bicycle: Color.lerp(bicycle, other.bicycle, t)!,
      motorcycle: Color.lerp(motorcycle, other.motorcycle, t)!,
      car: Color.lerp(car, other.car, t)!,
      truck: Color.lerp(truck, other.truck, t)!,
      bus: Color.lerp(bus, other.bus, t)!,
      autoRickshaw: Color.lerp(autoRickshaw, other.autoRickshaw, t)!,
      trafficLight: Color.lerp(trafficLight, other.trafficLight, t)!,
      trafficSign: Color.lerp(trafficSign, other.trafficSign, t)!,
    );
  }
}

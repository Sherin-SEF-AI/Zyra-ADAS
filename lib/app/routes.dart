import 'package:flutter/material.dart';

import '../features/debug/presentation/engine_debug_screen.dart';
import '../features/drive/presentation/drive_screen.dart';
import '../features/vehicle_select/presentation/vehicle_select_screen.dart';

/// Central route table.
///
/// Root ('/') decides between vehicle-select and drive based on whether a
/// profile is already persisted. Decision happens inside [_RootDecider] so
/// Riverpod is available.
class ZyraRoutes {
  ZyraRoutes._();

  static const String root = '/';
  static const String vehicleSelect = '/vehicle-select';
  static const String drive = '/drive';
  static const String engineDebug = '/debug/engine';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case root:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const _RootDecider(),
        );
      case vehicleSelect:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const VehicleSelectScreen(),
        );
      case drive:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const DriveScreen(),
        );
      case engineDebug:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const EngineDebugScreen(),
        );
    }
    return null;
  }
}

/// At the very first frame, decide where to send the user:
///   - persisted profile  →  /drive
///   - no profile         →  /vehicle-select
///
/// Extracted to its own widget to avoid doing routing logic at app build time
/// (which would force a rebuild of the whole MaterialApp on profile changes).
class _RootDecider extends StatelessWidget {
  const _RootDecider();

  @override
  Widget build(BuildContext context) {
    // Profile lookup itself happens inside VehicleSelectScreen + DriveScreen
    // via Riverpod; this decider is a thin async shell so cold-start renders
    // a branded splash instead of a white flash.
    //
    // We route to /vehicle-select by default. That screen watches the
    // repository, and if a profile is already persisted it immediately
    // forwards to /drive. This keeps the routing logic in one place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed(ZyraRoutes.vehicleSelect);
    });
    return const _Splash();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'ZYRA',
              style: theme.textTheme.displayLarge?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mobile ADAS — Shadow Mode',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

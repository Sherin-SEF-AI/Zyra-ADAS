import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../data/vehicle_profile.dart';

/// Large, glance-readable card for choosing a vehicle profile.
///
/// Design goals:
///   - Tap target ≥ 120 dp tall — driver / operator may be gloved.
///   - Strong visual selection state (amber border + subtle fill) so the
///     chosen card is unambiguous at a glance.
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final VehicleProfile profile;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (profile.kind) {
      case VehicleKind.car:
        return Icons.directions_car_rounded;
      case VehicleKind.scooter:
        return Icons.two_wheeler_rounded;
      case VehicleKind.bicycle:
        return Icons.pedal_bike_rounded;
      case VehicleKind.autoRickshaw:
        return Icons.electric_rickshaw_rounded;
      case VehicleKind.truck:
        return Icons.local_shipping_rounded;
    }
  }

  String get _subtitle {
    switch (profile.kind) {
      case VehicleKind.car:
        return 'Dashboard-mounted — 4-wheeler profile';
      case VehicleKind.scooter:
        return 'Handlebar-mounted — 2-wheeler profile';
      case VehicleKind.bicycle:
        return 'Handlebar-mounted — bicycle profile';
      case VehicleKind.autoRickshaw:
        return '3-wheeler profile';
      case VehicleKind.truck:
        return 'Commercial vehicle profile';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color borderColor =
        selected ? theme.colorScheme.primary : ZyraTheme.outline;
    final Color fillColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : ZyraTheme.surface;

    return Semantics(
      button: true,
      selected: selected,
      label: '${profile.displayName} profile',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : ZyraTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _icon,
                  size: 36,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      profile.displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ZyraTheme.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: selected ? 1 : 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

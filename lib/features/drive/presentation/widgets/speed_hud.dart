import 'package:flutter/material.dart';

import '../../../../core/sensors/ego_state.dart';

/// Small speed readout positioned bottom-left of the drive screen.
/// Shows the current GPS speed in km/h, or "--" when GPS is unavailable.
class SpeedHud extends StatelessWidget {
  const SpeedHud({super.key, required this.ego});

  final EgoState ego;

  @override
  Widget build(BuildContext context) {
    final String label = ego.gpsAvailable
        ? '${ego.speedKmh.round()}'
        : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            ego.gpsAvailable
                ? Icons.speed_rounded
                : Icons.gps_off_rounded,
            color: ego.gpsAvailable ? Colors.white : Colors.white38,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 2),
          Text(
            'km/h',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

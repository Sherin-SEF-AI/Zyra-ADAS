import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

/// Small badge showing what the shadow L2 planner would command.
/// Hidden when inactive. Shows "L2: BRAKE" (red) and/or "L2: STEER"
/// (blue) with magnitude.
class ShadowL2Badge extends StatelessWidget {
  const ShadowL2Badge({super.key, required this.plan});

  final ZyraShadowPlan plan;

  @override
  Widget build(BuildContext context) {
    if (!plan.isActive) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (plan.brakeActive)
          _Badge(
            label: 'L2: BRAKE',
            value: '${plan.brakeMps2.toStringAsFixed(1)} m/s\u00B2',
            color: Colors.red.shade400,
          ),
        if (plan.steerActive) ...<Widget>[
          if (plan.brakeActive) const SizedBox(height: 4),
          _Badge(
            label: 'L2: STEER',
            value:
                '${(plan.steerRad * 57.2958).toStringAsFixed(1)}\u00B0',
            color: Colors.blue.shade400,
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

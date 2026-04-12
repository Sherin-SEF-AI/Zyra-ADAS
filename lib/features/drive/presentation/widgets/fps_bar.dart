import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Top overlay on the drive screen.
///
/// Shows the rolling engine FPS (sampled over the trailing ~1 s by the native
/// side), the compute backend (Vulkan vs CPU), and the active vehicle profile
/// so the driver can verify the right tuning is loaded.
class FpsBar extends StatelessWidget {
  const FpsBar({
    super.key,
    required this.fps,
    required this.vulkanActive,
    required this.vehicleName,
  });

  final double fps;
  final bool vulkanActive;
  final String vehicleName;

  @override
  Widget build(BuildContext context) {
    final TextStyle mono = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );

    final Color backendColor =
        vulkanActive ? ZyraTheme.success : ZyraTheme.warning;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.black.withValues(alpha: 0.55),
      child: Row(
        children: <Widget>[
          Text('${fps.toStringAsFixed(0).padLeft(2)} FPS', style: mono),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: backendColor.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: backendColor, width: 1),
            ),
            child: Text(
              vulkanActive ? 'VULKAN' : 'CPU',
              style: mono.copyWith(color: backendColor, fontSize: 12),
            ),
          ),
          const Spacer(),
          Icon(Icons.directions_car_outlined,
              color: Colors.white.withValues(alpha: 0.8), size: 18),
          const SizedBox(width: 6),
          Text(vehicleName, style: mono),
        ],
      ),
    );
  }
}

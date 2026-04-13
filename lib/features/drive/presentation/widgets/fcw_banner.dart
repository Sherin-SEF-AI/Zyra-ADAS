import 'package:flutter/material.dart';

import '../../../../core/constants.dart';
import '../../../../core/ffi/zyra_detection.dart';

/// Phase 8 — Forward Collision Warning banner.
///
/// Renders at the TOP of the drive screen when the FCW state machine is
/// above SAFE. Colour keyed to severity:
///   * CAUTION — amber, subtle ("keep distance")
///   * WARN — orange, high-contrast ("SLOW DOWN")
///   * ALERT — red, pulsing ("BRAKE")
///
/// Also shows the class of the critical target and TTC. Silent in SAFE.
class FcwBanner extends StatelessWidget {
  const FcwBanner({super.key, required this.fcw});

  final ZyraFcw fcw;

  @override
  Widget build(BuildContext context) {
    if (fcw.isSafe) return const SizedBox.shrink();

    final Color bg;
    final String label;
    final IconData icon;
    switch (fcw.state) {
      case ZyraFcwState.alert:
        bg = const Color(0xFFFF3B30);
        label = 'BRAKE';
        icon = Icons.warning_amber_rounded;
        break;
      case ZyraFcwState.warn:
        bg = const Color(0xFFFF6B35);
        label = 'SLOW DOWN';
        icon = Icons.error_rounded;
        break;
      case ZyraFcwState.caution:
        bg = const Color(0xFFFFB84D);
        label = 'KEEP DISTANCE';
        icon = Icons.info_rounded;
        break;
      case ZyraFcwState.safe:
        return const SizedBox.shrink();
    }

    final String targetClass = fcw.criticalClassId >= 0 &&
            fcw.criticalClassId < kZyraClasses.length
        ? kZyraClasses[fcw.criticalClassId].toUpperCase()
        : '';
    final String ttc = fcw.ttcS.isFinite && fcw.ttcS > 0
        ? '${fcw.ttcS.toStringAsFixed(1)}s'
        : '--';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: bg.withValues(alpha: 0.5),
            blurRadius: 22,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                if (targetClass.isNotEmpty)
                  Text(
                    'FCW · $targetClass',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'TTC ',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  ttc,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

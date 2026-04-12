import 'package:flutter/material.dart';

/// Bottom overlay on the drive screen.
///
/// Pulls the most recent batch's detection count + pipeline timings so the
/// driver (and dev) can see whether the engine is keeping up in the current
/// environment. Minimal chrome — driver glance-time matters more than data
/// density here.
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.detections,
    required this.totalMs,
    required this.inferMs,
  });

  final int detections;
  final double totalMs;
  final double inferMs;

  @override
  Widget build(BuildContext context) {
    const TextStyle mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.black.withValues(alpha: 0.55),
      child: Row(
        children: <Widget>[
          Icon(Icons.adjust_rounded,
              color: Colors.white.withValues(alpha: 0.8), size: 16),
          const SizedBox(width: 6),
          Text('$detections objects', style: mono),
          const Spacer(),
          Text('infer ${inferMs.toStringAsFixed(1)}ms', style: mono),
          const SizedBox(width: 12),
          Text('total ${totalMs.toStringAsFixed(1)}ms', style: mono),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

/// Paints lane segments produced by the native HoughLaneDetector.
///
/// Coordinates come from the engine in ORIGINAL (unrotated) frame space —
/// we apply the same sensor→display rotation + scale that
/// [DetectionOverlayPainter] does for bboxes so lanes and detections
/// register pixel-perfectly in the same overlay.
class LaneOverlayPainter extends CustomPainter {
  LaneOverlayPainter({
    required this.batch,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.sensorOrientation,
    required this.mirror,
    this.leftColor = const Color(0xFF4ECDC4), // cyan
    this.rightColor = const Color(0xFFFFD93D), // yellow
    this.strokeWidth = 6,
  }) : super(repaint: null);

  final ZyraBatch? batch;
  final double sensorWidth;
  final double sensorHeight;
  final int sensorOrientation;
  final bool mirror;
  final Color leftColor;
  final Color rightColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null || b.lanes.isEmpty) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final ZyraLane lane in b.lanes) {
      final Color base = lane.isLeft ? leftColor : rightColor;
      // Fade near-unsupported lanes — don't hard-drop, the driver still
      // benefits from seeing "something". confidence is in [0, 1].
      final double alpha = 0.45 + 0.55 * lane.confidence.clamp(0.0, 1.0);
      paint.color = base.withValues(alpha: alpha);

      final Offset p1 = _mapPointToDisplay(Offset(lane.x1, lane.y1), size);
      final Offset p2 = _mapPointToDisplay(Offset(lane.x2, lane.y2), size);
      canvas.drawLine(p1, p2, paint);
    }
  }

  Offset _mapPointToDisplay(Offset p, Size size) {
    final double sw = sensorWidth;
    final double sh = sensorHeight;
    late double dw, dh;
    late Offset rotated;
    switch (sensorOrientation % 360) {
      case 0:
        dw = sw;
        dh = sh;
        rotated = p;
        break;
      case 90:
        dw = sh;
        dh = sw;
        rotated = Offset(sh - p.dy, p.dx);
        break;
      case 180:
        dw = sw;
        dh = sh;
        rotated = Offset(sw - p.dx, sh - p.dy);
        break;
      case 270:
        dw = sh;
        dh = sw;
        rotated = Offset(p.dy, sw - p.dx);
        break;
      default:
        dw = sw;
        dh = sh;
        rotated = p;
    }
    if (mirror) {
      rotated = Offset(dw - rotated.dx, rotated.dy);
    }
    return Offset(
      rotated.dx * size.width / dw,
      rotated.dy * size.height / dh,
    );
  }

  @override
  bool shouldRepaint(covariant LaneOverlayPainter old) {
    return batch?.frameId != old.batch?.frameId ||
        sensorWidth != old.sensorWidth ||
        sensorHeight != old.sensorHeight ||
        sensorOrientation != old.sensorOrientation ||
        mirror != old.mirror;
  }
}

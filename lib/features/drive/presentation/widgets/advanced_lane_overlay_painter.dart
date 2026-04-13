import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

/// Phase 7 — smooth polynomial lane overlay.
///
/// For each [ZyraLaneCurve] in the batch, evaluates x = a·y² + b·y + c
/// at N sample points across [y_top, y_bot], rotates the resulting points
/// from sensor space into display space (matching DetectionOverlayPainter's
/// transform), and draws a continuous Path. Center curve rendered as a
/// dashed white line; sides as solid cyan (left) / yellow (right) with
/// alpha keyed to confidence.
///
/// When [assist.state] is WARN, draws a translucent colored wedge between
/// the lane boundaries and the drift-side line to make the departure
/// visible at a glance. ALERT pulses that wedge red.
class AdvancedLaneOverlayPainter extends CustomPainter {
  AdvancedLaneOverlayPainter({
    required this.batch,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.sensorOrientation,
    required this.mirror,
    this.samplesPerCurve = 24,
    this.leftColor = const Color(0xFF4ECDC4),
    this.rightColor = const Color(0xFFFFD93D),
    this.centerColor = const Color(0xFFFFFFFF),
    this.warnColor = const Color(0xFFFF8C42),
    this.alertColor = const Color(0xFFFF3B30),
  }) : super(repaint: null);

  final ZyraBatch? batch;
  final double sensorWidth;
  final double sensorHeight;
  final int sensorOrientation;
  final bool mirror;
  final int samplesPerCurve;
  final Color leftColor;
  final Color rightColor;
  final Color centerColor;
  final Color warnColor;
  final Color alertColor;

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null) return;

    // --- Fill wedge first so curve strokes draw on top. -------------------
    _paintDepartureWedge(canvas, size, b);

    // --- Draw each curve. -------------------------------------------------
    for (final ZyraLaneCurve curve in b.curves) {
      if (!curve.locked) continue;
      final Path path = _buildPath(curve, size);
      final double alpha = (0.35 + 0.65 * curve.confidence).clamp(0.0, 1.0);
      if (curve.isCenter) {
        _drawDashed(
          canvas,
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = centerColor.withValues(alpha: alpha),
          dashLen: 18,
          gapLen: 14,
        );
      } else {
        final Color base = curve.isLeft ? leftColor : rightColor;
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = base.withValues(alpha: alpha)
            ..isAntiAlias = true,
        );
      }
    }
  }

  Path _buildPath(ZyraLaneCurve curve, Size size) {
    final Path path = Path();
    final double yTop = curve.yTop;
    final double yBot = curve.yBot;
    if (yBot <= yTop) return path;
    final double step = (yBot - yTop) / (samplesPerCurve - 1);
    bool first = true;
    for (int i = 0; i < samplesPerCurve; i++) {
      final double y = yTop + step * i;
      final double x = curve.xAt(y);
      final Offset p = _mapPointToDisplay(Offset(x, y), size);
      if (first) {
        path.moveTo(p.dx, p.dy);
        first = false;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  void _paintDepartureWedge(Canvas canvas, Size size, ZyraBatch b) {
    final ZyraLaneAssist a = b.assist;
    if (a.state != ZyraLdwState.warn && a.state != ZyraLdwState.alert) {
      return;
    }
    // Need both a center curve AND a side curve on the drift side.
    ZyraLaneCurve? center;
    ZyraLaneCurve? side;
    for (final ZyraLaneCurve c in b.curves) {
      if (c.isCenter) center = c;
      if (a.driftSide == 0 && c.isLeft) side = c;
      if (a.driftSide == 1 && c.isRight) side = c;
    }
    if (center == null || side == null) return;

    final Path wedge = Path();
    final double yTop = center.yTop.clamp(side.yTop, double.infinity);
    final double yBot =
        center.yBot > side.yBot ? side.yBot : center.yBot;
    if (yBot <= yTop) return;
    final double step = (yBot - yTop) / (samplesPerCurve - 1);
    // Top edge along center curve.
    for (int i = 0; i < samplesPerCurve; i++) {
      final double y = yTop + step * i;
      final Offset p = _mapPointToDisplay(Offset(center.xAt(y), y), size);
      if (i == 0) {
        wedge.moveTo(p.dx, p.dy);
      } else {
        wedge.lineTo(p.dx, p.dy);
      }
    }
    // Back along side curve.
    for (int i = samplesPerCurve - 1; i >= 0; i--) {
      final double y = yTop + step * i;
      final Offset p = _mapPointToDisplay(Offset(side.xAt(y), y), size);
      wedge.lineTo(p.dx, p.dy);
    }
    wedge.close();
    final Color base = a.state == ZyraLdwState.alert ? alertColor : warnColor;
    canvas.drawPath(
      wedge,
      Paint()
        ..color = base.withValues(alpha: 0.28)
        ..isAntiAlias = true,
    );
  }

  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLen,
    required double gapLen,
  }) {
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double next = (distance + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLen;
      }
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
  bool shouldRepaint(covariant AdvancedLaneOverlayPainter old) {
    return batch?.frameId != old.batch?.frameId ||
        sensorWidth != old.sensorWidth ||
        sensorHeight != old.sensorHeight ||
        sensorOrientation != old.sensorOrientation ||
        mirror != old.mirror;
  }
}

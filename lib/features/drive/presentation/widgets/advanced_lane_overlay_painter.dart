import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

/// Phase 7 — smooth polynomial lane overlay (optimised).
///
/// Draws left/right curves as solid strokes, center as a simple dashed
/// line computed from the sample points directly (no `computeMetrics`).
/// Departure wedge drawn on WARN/ALERT.
class AdvancedLaneOverlayPainter extends CustomPainter {
  AdvancedLaneOverlayPainter({
    required this.batch,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.sensorOrientation,
    required this.mirror,
    this.samplesPerCurve = 20,
  }) : super(repaint: null);

  final ZyraBatch? batch;
  final double sensorWidth;
  final double sensorHeight;
  final int sensorOrientation;
  final bool mirror;
  final int samplesPerCurve;

  static const Color _leftColor = Color(0xFF4ECDC4);
  static const Color _rightColor = Color(0xFFFFD93D);
  static const Color _centerColor = Color(0xFFFFFFFF);
  static const Color _warnColor = Color(0xFFFF8C42);
  static const Color _alertColor = Color(0xFFFF3B30);

  // Reusable paint objects.
  static final Paint _sidePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  static final Paint _centerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  static final Paint _wedgePaint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null) return;

    _paintDepartureWedge(canvas, size, b);

    for (final ZyraLaneCurve curve in b.curves) {
      if (!curve.locked) continue;
      final double alpha = (0.35 + 0.65 * curve.confidence).clamp(0.0, 1.0);

      if (curve.isCenter) {
        // Dashed center line — draw alternating segments directly from
        // sample points. No expensive computeMetrics.
        _centerPaint.color = _centerColor.withValues(alpha: alpha);
        _drawDashedFromSamples(canvas, curve, size, _centerPaint);
      } else {
        final Color base = curve.isLeft ? _leftColor : _rightColor;
        _sidePaint.color = base.withValues(alpha: alpha);
        final Path path = _buildPath(curve, size);
        canvas.drawPath(path, _sidePaint);
      }
    }
  }

  /// Draw a dashed line by drawing every other segment between sample
  /// points. ~10 drawLine calls instead of computeMetrics + extractPath.
  void _drawDashedFromSamples(
      Canvas canvas, ZyraLaneCurve curve, Size size, Paint paint) {
    final double yTop = curve.yTop;
    final double yBot = curve.yBot;
    if (yBot <= yTop) return;
    final double step = (yBot - yTop) / (samplesPerCurve - 1);
    bool draw = true;
    Offset? prev;
    for (int i = 0; i < samplesPerCurve; i++) {
      final double y = yTop + step * i;
      final Offset p = _mapPoint(Offset(curve.xAt(y), y), size);
      if (prev != null && draw) {
        canvas.drawLine(prev, p, paint);
      }
      prev = p;
      draw = !draw;
    }
  }

  Path _buildPath(ZyraLaneCurve curve, Size size) {
    final Path path = Path();
    final double yTop = curve.yTop;
    final double yBot = curve.yBot;
    if (yBot <= yTop) return path;
    final double step = (yBot - yTop) / (samplesPerCurve - 1);
    for (int i = 0; i < samplesPerCurve; i++) {
      final double y = yTop + step * i;
      final Offset p = _mapPoint(Offset(curve.xAt(y), y), size);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  void _paintDepartureWedge(Canvas canvas, Size size, ZyraBatch b) {
    final ZyraLaneAssist a = b.assist;
    if (a.state != ZyraLdwState.warn && a.state != ZyraLdwState.alert) return;

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
    final double yBot = center.yBot > side.yBot ? side.yBot : center.yBot;
    if (yBot <= yTop) return;
    final double step = (yBot - yTop) / (samplesPerCurve - 1);

    for (int i = 0; i < samplesPerCurve; i++) {
      final double y = yTop + step * i;
      final Offset p = _mapPoint(Offset(center.xAt(y), y), size);
      if (i == 0) { wedge.moveTo(p.dx, p.dy); } else { wedge.lineTo(p.dx, p.dy); }
    }
    for (int i = samplesPerCurve - 1; i >= 0; i--) {
      final double y = yTop + step * i;
      final Offset p = _mapPoint(Offset(side.xAt(y), y), size);
      wedge.lineTo(p.dx, p.dy);
    }
    wedge.close();

    final Color base = a.state == ZyraLdwState.alert ? _alertColor : _warnColor;
    _wedgePaint.color = base.withValues(alpha: 0.28);
    canvas.drawPath(wedge, _wedgePaint);
  }

  Offset _mapPoint(Offset p, Size size) {
    final double sw = sensorWidth;
    final double sh = sensorHeight;
    late double dw, dh;
    late Offset rotated;
    switch (sensorOrientation % 360) {
      case 0:
        dw = sw; dh = sh; rotated = p;
      case 90:
        dw = sh; dh = sw; rotated = Offset(sh - p.dy, p.dx);
      case 180:
        dw = sw; dh = sh; rotated = Offset(sw - p.dx, sh - p.dy);
      case 270:
        dw = sh; dh = sw; rotated = Offset(p.dy, sw - p.dx);
      default:
        dw = sw; dh = sh; rotated = p;
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

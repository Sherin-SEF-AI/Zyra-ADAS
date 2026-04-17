import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

/// Renders the 80x60 depth map as a full-screen colormap overlay.
/// Uses a plasma-inspired LUT: dark blue (far) → cyan → yellow → red (near).
class DepthColormapPainter extends CustomPainter {
  DepthColormapPainter({
    required this.batch,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.sensorOrientation,
    this.mirror = false,
    this.opacity = 0.75,
  });

  final ZyraBatch? batch;
  final double sensorWidth;
  final double sensorHeight;
  final int sensorOrientation;
  final bool mirror;
  final double opacity;

  // Plasma-inspired colormap LUT (256 entries).
  static final List<Color> _lut = _buildPlasmaLut();

  static List<Color> _buildPlasmaLut() {
    // 5-stop gradient: dark blue → blue → cyan → yellow → red
    const List<Color> stops = <Color>[
      Color(0xFF0D0887), // 0   — deep purple/blue (far)
      Color(0xFF7E03A8), // 64  — purple
      Color(0xFFCC4778), // 128 — pink/magenta
      Color(0xFFF89441), // 192 — orange
      Color(0xFFF0F921), // 255 — bright yellow (near)
    ];
    final List<Color> lut = List<Color>.filled(256, Colors.black);
    for (int i = 0; i < 256; i++) {
      final double t = i / 255.0;
      final double segment = t * (stops.length - 1);
      final int idx = segment.floor().clamp(0, stops.length - 2);
      final double frac = segment - idx;
      lut[i] = Color.lerp(stops[idx], stops[idx + 1], frac)!;
    }
    return lut;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null || !b.hasDepth || b.depthMap == null) return;

    final int mapW = b.depthMapW;
    final int mapH = b.depthMapH;
    if (mapW <= 0 || mapH <= 0) return;

    _drawFromPixels(canvas, size, mapW, mapH);
  }

  void _drawFromPixels(Canvas canvas, Size size, int mapW, int mapH) {
    canvas.save();
    _applyTransform(canvas, size);

    final double cellW = size.width / mapW;
    final double cellH = size.height / mapH;

    final Paint paint = Paint()..style = PaintingStyle.fill;
    final int alpha = (opacity * 255).round().clamp(0, 255);

    final Uint8List map = batch!.depthMap!;
    for (int y = 0; y < mapH; y++) {
      for (int x = 0; x < mapW; x++) {
        final int val = map[y * mapW + x];
        if (val == 0) continue; // skip far/empty
        paint.color = _lut[val].withValues(alpha: alpha / 255.0);
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }

    canvas.restore();
  }

  void _applyTransform(Canvas canvas, Size size) {
    // Same rotation logic as other overlay painters for consistency.
    switch (sensorOrientation) {
      case 90:
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
        if (mirror) {
          canvas.translate(size.width, 0);
          canvas.scale(-1, 1);
        }
      case 180:
        canvas.translate(size.width, size.height);
        canvas.scale(-1, -1);
      case 270:
        canvas.translate(0, size.height);
        canvas.scale(1, -1);
      default:
        if (mirror) {
          canvas.translate(size.width, 0);
          canvas.scale(-1, 1);
        }
    }
  }

  @override
  bool shouldRepaint(covariant DepthColormapPainter oldDelegate) {
    return batch != oldDelegate.batch ||
        opacity != oldDelegate.opacity;
  }
}

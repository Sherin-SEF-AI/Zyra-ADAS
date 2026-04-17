import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

// Paints a filled green polygon representing the driveable road surface
// from the 80x45 binary mask produced by the TwinLiteNet segmentor.
//
// Rendering: scan each row of the mask to find leftmost and rightmost
// driveable columns, build a closed Path from left boundary (top-to-bottom)
// + right boundary (bottom-to-top), then fill with translucent green.
class DriveableAreaOverlayPainter extends CustomPainter {
  DriveableAreaOverlayPainter({
    required this.batch,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.sensorOrientation,
    required this.mirror,
  });

  final ZyraBatch? batch;
  final double sensorWidth;
  final double sensorHeight;
  final int sensorOrientation;
  final bool mirror;

  static final Paint _fill = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0x4000FF00);

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null || !b.hasDriveable || b.driveableMask == null) return;

    final Uint8List mask = b.driveableMask!;
    final int mw = b.driveableMaskW;
    final int mh = b.driveableMaskH;
    if (mask.length != mw * mh) return;

    // Scan rows to find left/right boundaries of driveable area.
    final List<double> leftX = <double>[];
    final List<double> leftY = <double>[];
    final List<double> rightX = <double>[];
    final List<double> rightY = <double>[];

    for (int row = 0; row < mh; row++) {
      final int rowOff = row * mw;
      int first = -1;
      int last = -1;
      for (int col = 0; col < mw; col++) {
        if (mask[rowOff + col] != 0) {
          if (first < 0) first = col;
          last = col;
        }
      }
      if (first >= 0) {
        // Map mask coords to original sensor image space.
        final double sx = first / mw * sensorWidth;
        final double ex = (last + 1) / mw * sensorWidth;
        final double y = (row + 0.5) / mh * sensorHeight;
        leftX.add(sx);
        leftY.add(y);
        rightX.add(ex);
        rightY.add(y);
      }
    }

    if (leftX.length < 2) return;

    // Build closed path in sensor space: left boundary top→bottom,
    // then right boundary bottom→top.
    final Path sensorPath = Path();
    sensorPath.moveTo(leftX[0], leftY[0]);
    for (int i = 1; i < leftX.length; i++) {
      sensorPath.lineTo(leftX[i], leftY[i]);
    }
    for (int i = rightX.length - 1; i >= 0; i--) {
      sensorPath.lineTo(rightX[i], rightY[i]);
    }
    sensorPath.close();

    // Transform sensor-space path to display space (same rotation logic
    // as DetectionOverlayPainter._mapRectToDisplay).
    final Path displayPath =
        _transformPath(sensorPath, size);
    canvas.drawPath(displayPath, _fill);
  }

  Path _transformPath(Path sensorPath, Size size) {
    final double sw = sensorWidth;
    final double sh = sensorHeight;
    late double dw, dh;
    final Matrix4 m = Matrix4.identity();

    switch (sensorOrientation % 360) {
      case 0:
        dw = sw;
        dh = sh;
      case 90:
        dw = sh;
        dh = sw;
        // (x,y) → (sh - y, x)
        m.setEntry(0, 0, 0);
        m.setEntry(0, 1, -1);
        m.setEntry(0, 3, sh);
        m.setEntry(1, 0, 1);
        m.setEntry(1, 1, 0);
      case 180:
        dw = sw;
        dh = sh;
        m.setEntry(0, 0, -1);
        m.setEntry(0, 3, sw);
        m.setEntry(1, 1, -1);
        m.setEntry(1, 3, sh);
      case 270:
        dw = sh;
        dh = sw;
        // (x,y) → (y, sw - x)
        m.setEntry(0, 0, 0);
        m.setEntry(0, 1, 1);
        m.setEntry(1, 0, -1);
        m.setEntry(1, 1, 0);
        m.setEntry(1, 3, sw);
      default:
        dw = sw;
        dh = sh;
    }

    if (mirror) {
      // Flip horizontally in rotated space.
      final Matrix4 flip = Matrix4.identity();
      flip.setEntry(0, 0, -1);
      flip.setEntry(0, 3, dw);
      m.multiply(flip);
    }

    // Scale from rotated-sensor coords to display (widget) coords.
    final double sx = size.width / dw;
    final double sy = size.height / dh;
    final Matrix4 scale = Matrix4.identity();
    scale.setEntry(0, 0, sx);
    scale.setEntry(1, 1, sy);

    final Matrix4 combined = scale.multiplied(m);
    return sensorPath.transform(combined.storage);
  }

  @override
  bool shouldRepaint(covariant DriveableAreaOverlayPainter old) {
    return batch?.frameId != old.batch?.frameId ||
        sensorWidth != old.sensorWidth ||
        sensorHeight != old.sensorHeight ||
        sensorOrientation != old.sensorOrientation ||
        mirror != old.mirror;
  }
}

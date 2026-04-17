import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

// Paints a filled green polygon representing the driveable road surface
// from the 80x45 binary mask produced by the TwinLiteNet segmentor.
//
// Rendering: scan each row of the mask to find leftmost and rightmost
// driveable columns, build a closed Path from left boundary (top-to-bottom)
// + right boundary (bottom-to-top), then fill with gradient green.
// Boundary edges are drawn with a subtle bright border for visibility.
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
    ..color = const Color(0x3500E676);

  static final Paint _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = const Color(0x9900E676);

  // Cached boundary lists to reduce per-frame allocation.
  static final List<double> _lx = <double>[];
  static final List<double> _ly = <double>[];
  static final List<double> _rx = <double>[];
  static final List<double> _ry = <double>[];

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null || !b.hasDriveable || b.driveableMask == null) return;

    final Uint8List mask = b.driveableMask!;
    final int mw = b.driveableMaskW;
    final int mh = b.driveableMaskH;
    if (mask.length != mw * mh) return;

    // Reuse static lists to avoid allocation.
    _lx.clear(); _ly.clear(); _rx.clear(); _ry.clear();

    // Scan rows to find left/right boundaries of driveable area.
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
        final double sx = first / mw * sensorWidth;
        final double ex = (last + 1) / mw * sensorWidth;
        final double y = (row + 0.5) / mh * sensorHeight;
        _lx.add(sx); _ly.add(y);
        _rx.add(ex); _ry.add(y);
      }
    }

    if (_lx.length < 2) return;

    // Build closed path in sensor space.
    final Path sensorPath = Path();
    sensorPath.moveTo(_lx[0], _ly[0]);
    for (int i = 1; i < _lx.length; i++) {
      sensorPath.lineTo(_lx[i], _ly[i]);
    }
    for (int i = _rx.length - 1; i >= 0; i--) {
      sensorPath.lineTo(_rx[i], _ry[i]);
    }
    sensorPath.close();

    final Path displayPath = _transformPath(sensorPath, size);

    // Draw filled area then edge border for visibility.
    canvas.drawPath(displayPath, _fill);
    canvas.drawPath(displayPath, _edge);
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
      final Matrix4 flip = Matrix4.identity();
      flip.setEntry(0, 0, -1);
      flip.setEntry(0, 3, dw);
      m.multiply(flip);
    }

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

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/constants.dart';
import '../../../../core/ffi/zyra_detection.dart';

/// Paints Zyra detections on top of [CameraPreview].
///
/// Optimised: reuses Paint objects across detections and frames. Labels use
/// a single pre-built TextStyle to avoid TextPainter heap churn.
class DetectionOverlayPainter extends CustomPainter {
  DetectionOverlayPainter({
    required this.batch,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.sensorOrientation,
    required this.adas,
    required this.mirror,
  }) : super(repaint: null);

  final ZyraBatch? batch;
  final double sensorWidth;
  final double sensorHeight;
  final int sensorOrientation;
  final AdasColors adas;
  final bool mirror;

  // Reusable paint objects — avoids allocation on every paint call.
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round;

  static final Paint _bgPaint = Paint();

  static const TextStyle _labelStyle = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );

  // Single TextPainter reused across all labels in a frame.
  static final TextPainter _tp = TextPainter(
    textDirection: TextDirection.ltr,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null || b.detections.isEmpty) return;

    for (final ZyraDetection d in b.detections) {
      final Color color = adas.forClass(_className(d.classId));
      _stroke.color = color;

      final Rect sensorRect = Rect.fromLTRB(d.x1, d.y1, d.x2, d.y2);
      final Rect r = _mapRectToDisplay(sensorRect, size);

      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        _stroke,
      );

      // Label
      final String text =
          '${_className(d.classId)} ${d.confidence.toStringAsFixed(2)}';
      _tp.text = TextSpan(text: text, style: _labelStyle);
      _tp.layout(maxWidth: r.width + 40);

      const double pad = 4;
      final double bgH = _tp.height + pad * 2;
      final double bgW = _tp.width + pad * 2;
      final Offset bgOrigin = Offset(r.left, r.top - bgH);

      _bgPaint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(bgOrigin.dx, bgOrigin.dy, bgW, bgH),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        _bgPaint,
      );
      _tp.paint(canvas, bgOrigin + const Offset(pad, pad));
    }
  }

  String _className(int id) =>
      (id >= 0 && id < kZyraClasses.length) ? kZyraClasses[id] : 'unknown';

  Rect _mapRectToDisplay(Rect r, Size size) {
    final double sw = sensorWidth;
    final double sh = sensorHeight;
    late double dw, dh;
    late Rect rotated;
    switch (sensorOrientation % 360) {
      case 0:
        dw = sw; dh = sh; rotated = r;
      case 90:
        dw = sh; dh = sw;
        rotated = Rect.fromLTRB(sh - r.bottom, r.left, sh - r.top, r.right);
      case 180:
        dw = sw; dh = sh;
        rotated = Rect.fromLTRB(sw - r.right, sh - r.bottom,
            sw - r.left, sh - r.top);
      case 270:
        dw = sh; dh = sw;
        rotated = Rect.fromLTRB(r.top, sw - r.right, r.bottom, sw - r.left);
      default:
        dw = sw; dh = sh; rotated = r;
    }
    if (mirror) {
      rotated = Rect.fromLTRB(dw - rotated.right, rotated.top,
          dw - rotated.left, rotated.bottom);
    }
    final double sx = size.width / dw;
    final double sy = size.height / dh;
    return Rect.fromLTRB(
      rotated.left * sx, rotated.top * sy,
      rotated.right * sx, rotated.bottom * sy,
    );
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter old) {
    return batch?.frameId != old.batch?.frameId ||
        sensorWidth != old.sensorWidth ||
        sensorHeight != old.sensorHeight ||
        sensorOrientation != old.sensorOrientation ||
        mirror != old.mirror;
  }
}

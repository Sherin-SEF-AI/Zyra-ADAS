import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/constants.dart';
import '../../../../core/ffi/zyra_detection.dart';

/// Paints Zyra detections on top of [CameraPreview].
///
/// The painter is handed bbox coordinates in the **sensor-native** frame
/// (the engine runs inference on the YUV buffer as it came off the camera,
/// without rotation). [CameraPreview] itself rotates the texture by
/// [sensorOrientation] — so we rotate the bbox coords the same amount before
/// scaling them into `size`.
class DetectionOverlayPainter extends CustomPainter {
  DetectionOverlayPainter({
    required this.batch,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.sensorOrientation,
    required this.adas,
    required this.mirror,
  }) : super(repaint: null);

  /// Latest decoded batch from the engine; null = no batch yet.
  final ZyraBatch? batch;

  /// Sensor (unrotated) frame dimensions — matches `controller.value.previewSize`
  /// which is always reported in landscape orientation.
  final double sensorWidth;
  final double sensorHeight;

  /// Clockwise rotation applied by [CameraPreview] to reach display upright.
  /// Typically 90° for back camera in portrait on Android.
  final int sensorOrientation;

  /// Per-class colors.
  final AdasColors adas;

  /// Horizontal mirror — set true for front camera (selfie-style preview).
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    final ZyraBatch? b = batch;
    if (b == null || b.detections.isEmpty) return;

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;

    for (final ZyraDetection d in b.detections) {
      final Color color = adas.forClass(_className(d.classId));
      stroke.color = color;

      // Sensor-space corners (landscape orientation coming off the camera).
      final Rect sensorRect = Rect.fromLTRB(d.x1, d.y1, d.x2, d.y2);
      final Rect r = _mapRectToDisplay(sensorRect, size);

      final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(4));
      canvas.drawRRect(rr, stroke);

      _paintLabel(
        canvas,
        offset: r.topLeft,
        rectWidth: r.width,
        text: '${_className(d.classId)} ${d.confidence.toStringAsFixed(2)}',
        color: color,
      );
    }
  }

  String _className(int id) =>
      (id >= 0 && id < kZyraClasses.length) ? kZyraClasses[id] : 'unknown';

  /// Map a sensor-native rect into display coordinates (the overlay canvas).
  /// Handles 0/90/180/270 sensor orientations and optional mirroring.
  Rect _mapRectToDisplay(Rect r, Size size) {
    // First, rotate sensor-space rect into display-orientation space.
    final double sw = sensorWidth;
    final double sh = sensorHeight;
    // Intermediate (possibly rotated) bounding box in *display-orientation*
    // coords (width, height already swapped if 90/270).
    late double dw, dh;
    late Rect rotated;
    switch (sensorOrientation % 360) {
      case 0:
        dw = sw;
        dh = sh;
        rotated = r;
        break;
      case 90:
        // (x, y) in sensor → (sh - y, x) in display-rotated (dw=sh, dh=sw).
        dw = sh;
        dh = sw;
        rotated = Rect.fromLTRB(sh - r.bottom, r.left, sh - r.top, r.right);
        break;
      case 180:
        dw = sw;
        dh = sh;
        rotated = Rect.fromLTRB(sw - r.right, sh - r.bottom,
            sw - r.left, sh - r.top);
        break;
      case 270:
        // (x, y) in sensor → (y, sw - x) in display-rotated (dw=sh, dh=sw).
        dw = sh;
        dh = sw;
        rotated = Rect.fromLTRB(r.top, sw - r.right, r.bottom, sw - r.left);
        break;
      default:
        dw = sw;
        dh = sh;
        rotated = r;
    }

    if (mirror) {
      rotated = Rect.fromLTRB(dw - rotated.right, rotated.top,
          dw - rotated.left, rotated.bottom);
    }

    // Now scale from display-rotated coord space (dw × dh) to the canvas
    // size. CameraPreview uses BoxFit.cover-like behavior in a parent sized
    // to its aspectRatio, so here we expect (dw / dh) == (size.width /
    // size.height) and scale uniformly.
    final double sx = size.width / dw;
    final double sy = size.height / dh;
    return Rect.fromLTRB(
      rotated.left * sx,
      rotated.top * sy,
      rotated.right * sx,
      rotated.bottom * sy,
    );
  }

  void _paintLabel(
    Canvas canvas, {
    required Offset offset,
    required double rectWidth,
    required String text,
    required Color color,
  }) {
    const double pad = 4;
    const TextStyle style = TextStyle(
      color: Colors.black,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.0,
    );
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rectWidth + 40);

    final double bgH = tp.height + pad * 2;
    final double bgW = tp.width + pad * 2;
    final Offset bgOrigin = Offset(offset.dx, offset.dy - bgH);
    final Rect bg = Rect.fromLTWH(bgOrigin.dx, bgOrigin.dy, bgW, bgH);

    final Paint bgPaint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        bg,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      ),
      bgPaint,
    );
    tp.paint(canvas, bgOrigin + const Offset(pad, pad));
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter old) {
    // Repaint when the batch identity changes. Same frame id → same boxes.
    return batch?.frameId != old.batch?.frameId ||
        sensorWidth != old.sensorWidth ||
        sensorHeight != old.sensorHeight ||
        sensorOrientation != old.sensorOrientation ||
        mirror != old.mirror;
  }
}

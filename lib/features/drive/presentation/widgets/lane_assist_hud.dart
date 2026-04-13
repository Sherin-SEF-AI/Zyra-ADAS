import 'package:flutter/material.dart';

import '../../../../core/ffi/zyra_detection.dart';

/// Phase 7 — Lane Assist HUD.
///
/// Small instrument cluster drawn on the right edge of the drive screen:
///   * Lateral position indicator (car icon slides inside a lane rail based
///     on `assist.lateralOffsetPx`).
///   * Tracking pill (TRACKING green / SEARCHING amber) driven by how many
///     curves are locked.
///   * Curvature readout (radius in metres if > 10 m, "STRAIGHT" otherwise).
///   * TTLC readout — only shown when WARN / ALERT.
///
/// Additionally, when `assist.state` is WARN or ALERT a full-width banner
/// appears at the top of the overlay with the side of the drift and a
/// suggested action.
class LaneAssistHud extends StatelessWidget {
  const LaneAssistHud({
    super.key,
    required this.batch,
    this.pxPerMetre = 400.0,
  });

  final ZyraBatch? batch;

  /// Rough conversion from image-pixel curvature to world metres. Without
  /// IPM this is heuristic — tuned to match a typical phone dash mount at
  /// 720p. Used only for display, never for safety logic.
  final double pxPerMetre;

  @override
  Widget build(BuildContext context) {
    final ZyraBatch? b = batch;
    if (b == null) return const SizedBox.shrink();
    final ZyraLaneAssist assist = b.assist;
    final int lockedCount = b.curves.where((ZyraLaneCurve c) => c.locked).length;
    final bool tracking = lockedCount >= 2;

    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          if (assist.isWarning || assist.isAlert)
            Positioned(
              top: 56,
              left: 16,
              right: 16,
              child: _LdwBanner(assist: assist),
            ),
          Positioned(
            top: 120,
            right: 12,
            child: _AssistCard(
              assist: assist,
              tracking: tracking,
              lockedCount: lockedCount,
              totalCurves: b.curves.length,
              pxPerMetre: pxPerMetre,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  LDW banner
// =============================================================================

class _LdwBanner extends StatelessWidget {
  const _LdwBanner({required this.assist});

  final ZyraLaneAssist assist;

  @override
  Widget build(BuildContext context) {
    final bool alert = assist.isAlert;
    final Color bg = alert
        ? const Color(0xFFFF3B30)
        : const Color(0xFFFF8C42);
    final String side = assist.driftSide == 0
        ? 'LEFT'
        : (assist.driftSide == 1 ? 'RIGHT' : '');
    final String label = alert ? 'LANE DEPARTURE' : 'LANE DRIFT';
    final String? ttlc = assist.ttlcS.isFinite && assist.ttlcS < 5
        ? '${assist.ttlcS.toStringAsFixed(1)}s'
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: bg.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(
            alert ? Icons.warning_amber_rounded : Icons.error_outline_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            '$label${side.isNotEmpty ? ' · $side' : ''}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          if (ttlc != null)
            Text(
              'TTLC $ttlc',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
//  Instrument card (right edge)
// =============================================================================

class _AssistCard extends StatelessWidget {
  const _AssistCard({
    required this.assist,
    required this.tracking,
    required this.lockedCount,
    required this.totalCurves,
    required this.pxPerMetre,
  });

  final ZyraLaneAssist assist;
  final bool tracking;
  final int lockedCount;
  final int totalCurves;
  final double pxPerMetre;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TrackingPill(
            tracking: tracking,
            lockedCount: lockedCount,
            totalCurves: totalCurves,
          ),
          const SizedBox(height: 10),
          _LateralBar(assist: assist),
          const SizedBox(height: 10),
          _CurvatureReadout(
            curvaturePx: assist.curvaturePx,
            pxPerMetre: pxPerMetre,
          ),
        ],
      ),
    );
  }
}

class _TrackingPill extends StatelessWidget {
  const _TrackingPill({
    required this.tracking,
    required this.lockedCount,
    required this.totalCurves,
  });

  final bool tracking;
  final int lockedCount;
  final int totalCurves;

  @override
  Widget build(BuildContext context) {
    final Color c = tracking
        ? const Color(0xFF2ECC71)
        : const Color(0xFFFFB84D);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.55), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            tracking ? 'TRACKING' : 'SEARCHING',
            style: TextStyle(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            '$lockedCount/$totalCurves',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LateralBar extends StatelessWidget {
  const _LateralBar({required this.assist});

  final ZyraLaneAssist assist;

  @override
  Widget build(BuildContext context) {
    // Clamp offset into [-1, 1]. Normalising by 120 px maps typical
    // mid-lane drift well for 720p — pure cosmetic.
    final double norm = (assist.lateralOffsetPx / 120.0).clamp(-1.0, 1.0);
    final Color fill = assist.isAlert
        ? const Color(0xFFFF3B30)
        : (assist.isWarning
            ? const Color(0xFFFF8C42)
            : const Color(0xFF4ECDC4));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'LATERAL',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 26,
          child: CustomPaint(
            painter: _LateralBarPainter(
              normalized: norm,
              fill: fill,
              armed: assist.armed,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${assist.lateralOffsetPx >= 0 ? '+' : ''}${assist.lateralOffsetPx.toStringAsFixed(0)}px',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LateralBarPainter extends CustomPainter {
  _LateralBarPainter({
    required this.normalized,
    required this.fill,
    required this.armed,
  });

  final double normalized;
  final Color fill;
  final bool armed;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double trackH = 6;
    final double trackY = (h - trackH) / 2;

    // Rail.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY, w, trackH),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );

    // Centre tick.
    canvas.drawRect(
      Rect.fromLTWH(w / 2 - 0.5, trackY - 3, 1, trackH + 6),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    // Indicator.
    final double cx = w / 2 + (normalized * (w / 2 - 6));
    final Paint dotPaint = Paint()..color = armed ? fill : fill.withValues(alpha: 0.35);
    canvas.drawCircle(Offset(cx, h / 2), 6, dotPaint);
    canvas.drawCircle(
      Offset(cx, h / 2),
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _LateralBarPainter old) {
    return old.normalized != normalized ||
        old.fill != fill ||
        old.armed != armed;
  }
}

class _CurvatureReadout extends StatelessWidget {
  const _CurvatureReadout({
    required this.curvaturePx,
    required this.pxPerMetre,
  });

  final double curvaturePx;
  final double pxPerMetre;

  @override
  Widget build(BuildContext context) {
    final bool straight = !curvaturePx.isFinite || curvaturePx.abs() > 10000;
    final String value;
    final IconData icon;
    if (straight) {
      value = 'STRAIGHT';
      icon = Icons.straight_rounded;
    } else {
      final double metres = curvaturePx.abs() / pxPerMetre;
      value = '${metres.toStringAsFixed(metres >= 100 ? 0 : 1)}m';
      icon = curvaturePx > 0
          ? Icons.turn_right_rounded
          : Icons.turn_left_rounded;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'RADIUS',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../state/radar_blips.dart';

class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.blips,
    required this.sweepAngle,
    required this.ringRadii,
  });

  final List<RadarBlip> blips;
  final double sweepAngle;
  final List<double> ringRadii; // fractions of canvas radius, one per band

  static const _ringColor = Color(0xFF1E4D3A);
  static const _blipColor = Color(0xFF4ADE80);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _ringColor;
    for (final r in ringRadii) {
      canvas.drawCircle(center, r * radius, ringPaint);
    }

    // Cosmetic sweep (FR-16): gradient wedge trailing the sweep angle.
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 0.8,
        endAngle: sweepAngle,
        colors: const [Color(0x004ADE80), Color(0x334ADE80)],
        transform: GradientRotation(sweepAngle - 0.8),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // Center dot = the user (FR-13).
    canvas.drawCircle(center, 5, Paint()..color = _blipColor);

    for (final blip in blips) {
      final pos = center +
          Offset.fromDirection(blip.angle, blip.radius * radius);
      final paint = Paint()
        ..color = _blipColor.withValues(alpha: blip.opacity);
      canvas.drawCircle(pos, 7, paint);
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _blipColor.withValues(alpha: blip.opacity * 0.4);
      canvas.drawCircle(pos, 11, halo);
    }
  }

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.blips != blips ||
      old.sweepAngle != sweepAngle ||
      old.ringRadii != ringRadii;
}

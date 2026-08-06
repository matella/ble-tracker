import 'package:ble_tracker/state/radar_blips.dart';
import 'package:ble_tracker/ui/radar_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget paint(List<RadarBlip> blips) => RepaintBoundary(
        child: Container(
          color: const Color(0xFF0A1410),
          width: 400,
          height: 400,
          child: CustomPaint(
            painter: RadarPainter(
              blips: blips,
              sweepAngle: 1.0, // fixed for determinism
              ringRadii: const [0.25, 0.5, 0.75, 1.0],
            ),
          ),
        ),
      );

  testWidgets('golden: one blip per band ring', (tester) async {
    await tester.pumpWidget(paint(const [
      RadarBlip(deviceId: 'a', name: 'a', angle: 0.3, radius: 0.15, opacity: 1),
      RadarBlip(deviceId: 'b', name: 'b', angle: 1.8, radius: 0.4, opacity: 1),
      RadarBlip(deviceId: 'c', name: 'c', angle: 3.5, radius: 0.65, opacity: 1),
      RadarBlip(deviceId: 'd', name: 'd', angle: 5.2, radius: 0.9, opacity: 1),
    ]));
    await expectLater(find.byType(RepaintBoundary),
        matchesGoldenFile('goldens/radar_four_bands.png'));
  });

  testWidgets('golden: fading blip at half opacity', (tester) async {
    await tester.pumpWidget(paint(const [
      RadarBlip(deviceId: 'a', name: 'a', angle: 0.3, radius: 0.5, opacity: 0.5),
    ]));
    await expectLater(find.byType(RepaintBoundary),
        matchesGoldenFile('goldens/radar_fading_blip.png'));
  });

  testWidgets('golden: empty radar', (tester) async {
    await tester.pumpWidget(paint(const []));
    await expectLater(find.byType(RepaintBoundary),
        matchesGoldenFile('goldens/radar_empty.png'));
  });
}

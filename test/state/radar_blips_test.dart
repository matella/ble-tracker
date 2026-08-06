import 'dart:math' as math;

import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/hash_radar_layout.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/state/radar_blips.dart';
import 'package:flutter_test/flutter_test.dart';

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: id, type: DeviceType.tag, trackingEnabled: tracking);

TrackedDeviceState state(
  String id, {
  DeviceVisibility visibility = DeviceVisibility.visible,
  double meters = 2,
  DateTime? lastSeen,
}) =>
    TrackedDeviceState(
      device: dev(id, tracking: visibility != DeviceVisibility.trackingOff),
      visibility: visibility,
      estimate: visibility == DeviceVisibility.visible
          ? DistanceEstimate(meters: meters, band: ProximityBand.near)
          : null,
      lastSeen: lastSeen,
    );

void main() {
  final config = ProximityConfig();
  final layout = HashRadarLayout(config);
  final t0 = DateTime.utc(2026, 1, 1);

  test('visible device → blip with layout angle/radius, opacity 1', () {
    final blips =
        radarBlipsFrom({'a': state('a', lastSeen: t0)}, t0, layout, config);
    final b = blips.single;
    expect(b.deviceId, 'a');
    expect(b.angle, layout.angleFor('a'));
    expect(b.opacity, 1.0);
  });

  test('trackingOff device → no blip', () {
    final blips = radarBlipsFrom(
        {'a': state('a', visibility: DeviceVisibility.trackingOff)},
        t0, layout, config);
    expect(blips, isEmpty);
  });

  test('notVisible fades over 2 s after going stale, then disappears', () {
    // Went stale at lastSeen + 10 s. Fade runs [10 s, 12 s].
    final staleAt = t0.add(config.staleAfter);
    final s = state('a', visibility: DeviceVisibility.notVisible, lastSeen: t0)
        ;
    double opacityAt(Duration afterStale) => radarBlipsFrom(
          {'a': s},
          staleAt.add(afterStale),
          layout,
          config,
        ).singleOrNull?.opacity ?? 0;

    expect(opacityAt(Duration.zero), 1.0);
    expect(opacityAt(const Duration(seconds: 1)), closeTo(0.5, 0.01));
    expect(opacityAt(const Duration(seconds: 2)), 0);
    expect(
        radarBlipsFrom({'a': s}, staleAt.add(const Duration(seconds: 3)),
            layout, config),
        isEmpty);
  });

  test('notVisible with no lastSeen (never seen) → no blip', () {
    final blips = radarBlipsFrom(
        {'a': state('a', visibility: DeviceVisibility.notVisible)},
        t0, layout, config);
    expect(blips, isEmpty);
  });

  test('hit test finds blip within 24 px, nearest wins, else null', () {
    const canvasRadius = 200.0;
    final blip = RadarBlip(
        deviceId: 'a', name: 'a', angle: 0, radius: 0.5, opacity: 1);
    // angle 0, radius 0.5 → center at (0.5*200, 0) = (100, 0) from radar center
    final x = 0.5 * canvasRadius * math.cos(0.0);
    final y = 0.5 * canvasRadius * math.sin(0.0);
    expect(hitTestBlips([blip], (dx: x + 10, dy: y - 10), canvasRadius), 'a');
    expect(hitTestBlips([blip], (dx: x + 100, dy: y), canvasRadius), isNull);

    final near = RadarBlip(
        deviceId: 'b', name: 'b', angle: 0, radius: 0.55, opacity: 1);
    expect(
        hitTestBlips([blip, near], (dx: 0.55 * canvasRadius, dy: 0),
            canvasRadius),
        'b');
  });

  test('fading blip uses lastKnownRadius when provided', () {
    final staleAt = t0.add(config.staleAfter);
    final s = state('a', visibility: DeviceVisibility.notVisible, lastSeen: t0);
    final blips = radarBlipsFrom(
      {'a': s},
      staleAt,
      layout,
      config,
      lastKnownRadius: {'a': 0.7},
    );
    final b = blips.single;
    expect(b.radius, 0.7);
    expect(b.opacity, 1.0);
  });
}

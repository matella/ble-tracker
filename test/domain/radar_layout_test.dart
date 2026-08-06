import 'dart:math' as math;

import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/hash_radar_layout.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final layout = HashRadarLayout(ProximityConfig());

  DistanceEstimate est(double m) =>
      DistanceEstimate(meters: m, band: ProximityBand.near);

  group('angleFor', () {
    test('deterministic across calls and instances', () {
      final again = HashRadarLayout(ProximityConfig());
      for (final id in ['aa:bb:cc', 'device-1', 'x']) {
        expect(layout.angleFor(id), layout.angleFor(id));
        expect(layout.angleFor(id), again.angleFor(id));
      }
    });

    test('range is [0, 2π)', () {
      for (var i = 0; i < 100; i++) {
        final a = layout.angleFor('device-$i');
        expect(a, greaterThanOrEqualTo(0));
        expect(a, lessThan(2 * math.pi));
      }
    });

    test('distribution sanity: sequential ids do not cluster', () {
      final buckets = List.filled(8, 0);
      for (var i = 0; i < 100; i++) {
        final a = layout.angleFor('device-$i');
        buckets[(a / (2 * math.pi) * 8).floor()]++;
      }
      expect(buckets.where((b) => b > 0).length, greaterThanOrEqualTo(6));
      expect(buckets.reduce(math.max), lessThanOrEqualTo(40));
    });
  });

  group('radiusFor', () {
    test('log-scaling is monotonic', () {
      final r1 = layout.radiusFor(est(0.5));
      final r2 = layout.radiusFor(est(3));
      final r3 = layout.radiusFor(est(10));
      expect(r1, lessThan(r2));
      expect(r2, lessThan(r3));
    });

    test('near-range differences are visually prominent (log > linear)', () {
      // From 0.5→3 m spans a larger radial fraction than the linear mapping would give.
      final span = layout.radiusFor(est(3)) - layout.radiusFor(est(0.5));
      const linearSpan = (3 - 0.5) / (20 - 0.1);
      expect(span, greaterThan(linearSpan));
    });

    test('clamps to [0, 1] outside configured range', () {
      expect(layout.radiusFor(est(0.01)), 0);
      expect(layout.radiusFor(est(500)), 1);
    });

    test('bounds: min→0, max→1', () {
      expect(layout.radiusFor(est(0.1)), closeTo(0, 1e-9));
      expect(layout.radiusFor(est(20)), closeTo(1, 1e-9));
    });
  });
}

import 'dart:math' as math;

import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/log_distance_estimator.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

double log10(double x) => math.log(x) / math.ln10;

void main() {
  final estimator = LogDistanceEstimator(ProximityConfig());

  test('table-driven: known RSSI/TxPower/n triples', () {
    // d = 10 ^ ((txPower - rssi) / (10 * n))
    final cases = <(double rssi, double tx, double n, double meters)>[
      (-59, -59, 2.0, 1.0),
      (-79, -59, 2.0, 10.0),
      (-69, -59, 2.0, 3.1623),
      (-59, -59, 2.7, 1.0),
      (-86, -59, 2.7, 10.0),
      (-49, -59, 2.5, 0.3981),
    ];
    for (final (rssi, tx, n, meters) in cases) {
      final e = estimator.estimate(
        smoothedRssi: rssi,
        txPower: tx,
        environmentFactor: n,
      );
      expect(e.meters, closeTo(meters, 0.001), reason: 'rssi=$rssi n=$n');
    }
  });

  test('band boundaries: exactly 0.5 / 3.0 / 10.0 m', () {
    expect(estimator.bandForMeters(0.49), ProximityBand.immediate);
    expect(estimator.bandForMeters(0.5), ProximityBand.near);
    expect(estimator.bandForMeters(2.99), ProximityBand.near);
    expect(estimator.bandForMeters(3.0), ProximityBand.mid);
    expect(estimator.bandForMeters(10.0), ProximityBand.mid);
    expect(estimator.bandForMeters(10.01), ProximityBand.far);
  });

  test('band thresholds come from config, not hard-coded', () {
    final custom = LogDistanceEstimator(ProximityConfig(
      immediateMaxMeters: 1.0,
      nearMaxMeters: 5.0,
      midMaxMeters: 20.0,
    ));
    final e = custom.estimate(
      smoothedRssi: -59, txPower: -59, environmentFactor: 2.0); // 1.0 m
    expect(e.band, ProximityBand.near); // 1.0 >= immediateMax(1.0) → near
  });

  test('missing TxPower falls back to config default', () {
    final config = ProximityConfig(defaultTxPower: -63);
    expect(resolveTxPower(null, config), -63);
    expect(resolveTxPower(-50, config), -50);
  });
}

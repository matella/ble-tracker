import 'dart:math';

import 'package:ble_tracker/domain/kalman_rssi_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

KalmanRssiSmoother defaultSmoother() =>
    KalmanRssiSmoother(processNoise: 0.065, measurementNoise: 1.4);

double variance(List<double> xs) {
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  return xs.map((x) => pow(x - mean, 2).toDouble()).reduce((a, b) => a + b) /
      xs.length;
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  test('converges on a constant signal from an off-target start', () {
    final s = defaultSmoother();
    s.next('d', -40, t0); // first sample seeds the estimate off-target
    var out = 0.0;
    for (var i = 1; i <= 50; i++) {
      out = s.next('d', -60, t0.add(Duration(milliseconds: 100 * i)));
    }
    expect(out, closeTo(-60, 0.1));
  });

  test('attenuates jitter (output variance well below input variance)', () {
    final s = defaultSmoother();
    final inputs = <double>[];
    final outputs = <double>[];
    final rng = Random(42);
    for (var i = 0; i < 200; i++) {
      final raw = -60 + (rng.nextDouble() - 0.5) * 12; // ±6 dB jitter
      inputs.add(raw);
      outputs.add(s.next('d', raw, t0.add(Duration(milliseconds: 100 * i))));
    }
    // Skip warm-up samples when comparing steady-state noise.
    expect(
      variance(outputs.sublist(50)),
      lessThan(variance(inputs.sublist(50)) * 0.3),
    );
  });

  test('step response lags: first output after a step is between old and new', () {
    final s = defaultSmoother();
    for (var i = 0; i < 30; i++) {
      s.next('d', -50, t0.add(Duration(milliseconds: 100 * i)));
    }
    final afterStep = s.next('d', -70, t0.add(const Duration(seconds: 4)));
    expect(afterStep, lessThan(-50));
    expect(afterStep, greaterThan(-70));
  });

  test('devices are isolated from each other', () {
    final s = defaultSmoother();
    for (var i = 0; i < 30; i++) {
      s.next('a', -40, t0.add(Duration(milliseconds: 100 * i)));
    }
    // First sample for a fresh device returns the raw value, uninfluenced by 'a'.
    expect(s.next('b', -80, t0), -80);
  });

  test('reset clears state for that device only', () {
    final s = defaultSmoother();
    for (var i = 0; i < 30; i++) {
      s.next('a', -40, t0.add(Duration(milliseconds: 100 * i)));
      s.next('b', -40, t0.add(Duration(milliseconds: 100 * i)));
    }
    s.reset('a');
    expect(s.next('a', -90, t0), -90); // fresh: returns raw
    expect(s.next('b', -90, t0), greaterThan(-90)); // still smoothed
  });

  test('parameters are injected: higher R smooths harder', () {
    final light = KalmanRssiSmoother(processNoise: 0.065, measurementNoise: 0.5);
    final heavy = KalmanRssiSmoother(processNoise: 0.065, measurementNoise: 10);
    for (var i = 0; i < 30; i++) {
      light.next('d', -50, t0);
      heavy.next('d', -50, t0);
    }
    final lightOut = light.next('d', -70, t0);
    final heavyOut = heavy.next('d', -70, t0);
    // Heavy smoothing trusts the new measurement less → stays closer to -50.
    expect(heavyOut, greaterThan(lightOut));
  });
}

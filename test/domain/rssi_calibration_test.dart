import 'package:ble_tracker/domain/rssi_calibration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  test('averages readings once the window has elapsed with enough samples', () {
    final s = RssiCalibrationSession();
    for (var i = 0; i <= 10; i++) {
      s.add(
        -50 + (i.isEven ? 1 : -1).toDouble(),
        t0.add(Duration(milliseconds: 500 * i)),
      );
    }
    // 11 readings spanning 5 s; the mean of the alternating ±1 around -50.
    expect(s.result, closeTo(-50 + (6 * 1 - 5 * 1) / 11, 1e-9));
  });

  test('no result before the window has elapsed', () {
    final s = RssiCalibrationSession();
    for (var i = 0; i < 20; i++) {
      s.add(-50, t0.add(Duration(milliseconds: 100 * i))); // 1.9 s span
    }
    expect(s.result, isNull);
  });

  test('no result with too few readings, even over the window', () {
    final s = RssiCalibrationSession();
    s.add(-50, t0);
    s.add(-50, t0.add(const Duration(seconds: 6)));
    expect(s.sampleCount, 2);
    expect(s.result, isNull);
  });

  test('no result before any reading', () {
    expect(RssiCalibrationSession().result, isNull);
  });

  test('plausible reference range is -100 to -20 dBm', () {
    expect(RssiCalibrationSession.isPlausibleReference(-59), isTrue);
    expect(RssiCalibrationSession.isPlausibleReference(-100), isTrue);
    expect(RssiCalibrationSession.isPlausibleReference(-20), isTrue);
    expect(RssiCalibrationSession.isPlausibleReference(-101), isFalse);
    expect(RssiCalibrationSession.isPlausibleReference(-19), isFalse);
  });
}

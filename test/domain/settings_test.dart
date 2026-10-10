import 'package:ble_tracker/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEnvironmentFactor', () {
    test('a valid stored value is used as-is', () {
      expect(parseEnvironmentFactor('3.5'), 3.5);
    });

    test('range endpoints are valid', () {
      expect(parseEnvironmentFactor('2.0'), 2.0);
      expect(parseEnvironmentFactor('4.0'), 4.0);
    });

    test('missing value falls back to the default', () {
      expect(parseEnvironmentFactor(null), defaultEnvironmentFactor);
    });

    test('unparseable value falls back to the default', () {
      expect(parseEnvironmentFactor('not a number'), defaultEnvironmentFactor);
    });

    test('non-finite value falls back to the default', () {
      expect(parseEnvironmentFactor('NaN'), defaultEnvironmentFactor);
      expect(parseEnvironmentFactor('Infinity'), defaultEnvironmentFactor);
    });

    test('out-of-range value falls back to the default', () {
      expect(parseEnvironmentFactor('1.9'), defaultEnvironmentFactor);
      expect(parseEnvironmentFactor('4.1'), defaultEnvironmentFactor);
    });
  });
}

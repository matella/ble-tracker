import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/unavailable_ble_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports unavailable and ignores start/stop', () async {
    final scanner = UnavailableBleScanner();
    expect(await scanner.status().first, ScannerStatus.unavailable);
    await scanner.start(ScanProfile.lowLatency); // no throw
    await scanner.stop(); // no throw
    expect(await scanner.observe().isEmpty, isTrue);
  });
}

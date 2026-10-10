import 'package:ble_tracker/domain/interfaces.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the no-op host accepts both states and does nothing', () async {
    final host = NoopBackgroundScanHost();
    await host.setActive(true);
    await host.setActive(false);
  });
}

import 'package:ble_tracker/platform/fake_ble_scanner.dart';

import 'ble_scanner_contract.dart';

void main() {
  runBleScannerContract('FakeBleScanner (reference)', () async {
    final scanner = FakeBleScanner();
    return ScannerHarness(
      scanner: scanner,
      emitObservation: scanner.emit,
      adapterOff: scanner.setAdapterOff,
      adapterOn: scanner.setAdapterOn,
      revokePermission: scanner.revokePermission,
    );
  });
}

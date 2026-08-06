import 'dart:async';

import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/platform/wear/wear_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

void main() {
  runBleScannerContract('WearScanner', () async {
    final inner = FakeBleScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);
    return ScannerHarness(
      scanner: scanner,
      emitObservation: inner.emit,
      adapterOff: inner.setAdapterOff,
      adapterOn: inner.setAdapterOn,
      revokePermission: inner.revokePermission,
    );
  });

  test('ambient mode restarts inner scan with balanced profile', () async {
    final inner = _ProfileRecordingScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);

    await scanner.start(ScanProfile.lowLatency);
    expect(inner.profiles, [ScanProfile.lowLatency]);
    expect(inner.stops, 0);

    ambient.add(true);
    await pumpEventQueue();
    expect(inner.profiles.last, ScanProfile.balanced);
    // The real FlutterBluePlusScanner treats start()-while-scanning as a
    // no-op, so the ambient downgrade only takes effect if WearScanner
    // stops the inner scanner before restarting it with the new profile.
    expect(inner.stops, 1);

    ambient.add(false);
    await pumpEventQueue();
    expect(inner.profiles.last, ScanProfile.lowLatency); // restore requested
    expect(inner.stops, 2);
    expect(inner.profiles, [
      ScanProfile.lowLatency,
      ScanProfile.balanced,
      ScanProfile.lowLatency,
    ]);
  });

  test('start while already ambient delegates balanced profile', () async {
    final inner = _ProfileRecordingScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);
    ambient.add(true); // ambient before start — _started guard skips inner call
    await pumpEventQueue();
    await scanner.start(ScanProfile.lowLatency);
    expect(inner.profiles, [ScanProfile.balanced]);
    ambient.add(false);
    await pumpEventQueue();
    expect(inner.profiles.last, ScanProfile.lowLatency); // restore on exit
  });
}

class _ProfileRecordingScanner implements BleScanner {
  final profiles = <ScanProfile>[];
  int stops = 0;
  @override
  Stream<ScanObservation> observe() => const Stream.empty();
  @override
  Stream<ScannerStatus> status() => const Stream.empty();
  @override
  Future<void> start(ScanProfile profile) async => profiles.add(profile);
  @override
  Future<void> stop() async => stops++;
}

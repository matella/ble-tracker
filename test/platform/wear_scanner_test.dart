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

    ambient.add(true);
    await pumpEventQueue();
    expect(inner.profiles.last, ScanProfile.balanced);

    ambient.add(false);
    await pumpEventQueue();
    expect(inner.profiles.last, ScanProfile.lowLatency); // restore requested
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
  @override
  Stream<ScanObservation> observe() => const Stream.empty();
  @override
  Stream<ScannerStatus> status() => const Stream.empty();
  @override
  Future<void> start(ScanProfile profile) async => profiles.add(profile);
  @override
  Future<void> stop() async {}
}

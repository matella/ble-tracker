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

  test('ambient change while inner is unavailable does not restart it',
      () async {
    final inner = _StatusScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);
    await scanner.start(ScanProfile.lowLatency);
    inner.statusCtrl.add(ScannerStatus.unavailable);
    await pumpEventQueue();

    ambient.add(true);
    await pumpEventQueue();
    expect(inner.stops, 0);
    expect(inner.profiles, [ScanProfile.lowLatency]);
  });

  test('rapid ambient toggles are applied in arrival order', () async {
    final inner = _ProfileRecordingScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);
    await scanner.start(ScanProfile.lowLatency);

    ambient.add(true);
    ambient.add(false);
    ambient.add(true);
    await pumpEventQueue();
    // Each transition restarts once; the last one leaves the scanner in the
    // ambient profile, with no interleaved restart from an earlier event.
    expect(inner.profiles.last, ScanProfile.balanced);
    expect(inner.stops, 3);
  });

  test('dispose cancels the ambient and status subscriptions', () async {
    final inner = _StatusScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);
    await scanner.start(ScanProfile.lowLatency);
    scanner.dispose();
    await pumpEventQueue();

    expect(ambient.hasListener, isFalse);
    expect(inner.statusCtrl.hasListener, isFalse);
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

/// Like [_ProfileRecordingScanner], but lets a test push inner status changes.
class _StatusScanner extends _ProfileRecordingScanner {
  final statusCtrl = StreamController<ScannerStatus>.broadcast();
  @override
  Stream<ScannerStatus> status() => statusCtrl.stream;
}

import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/bluez/bluez_api.dart';
import 'package:ble_tracker/platform/bluez/bluez_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

class FakeBlueZApi implements BlueZApi {
  final adapter = StreamController<bool>.broadcast();
  final results = StreamController<ScanObservation>.broadcast();
  bool discovering = false;
  int startCalls = 0;

  @override
  Stream<bool> adapterOn() => adapter.stream;
  @override
  Stream<ScanObservation> scanResults() => results.stream;
  @override
  Future<void> startDiscovery() async {
    startCalls++;
    discovering = true;
  }
  @override
  Future<void> stopDiscovery() async => discovering = false;
}

void main() {
  runBleScannerContract('BlueZScanner', () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);
    return ScannerHarness(
      scanner: scanner,
      emitObservation: api.results.add,
      adapterOff: () => api.adapter.add(false),
      adapterOn: () => api.adapter.add(true),
      revokePermission: scanner.onPermissionRevoked,
    );
  });

  test('adapter off stops discovery; on restarts it', () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);
    await scanner.start(ScanProfile.balanced);
    expect(api.discovering, isTrue);
    api.adapter.add(false);
    await pumpEventQueue();
    expect(api.discovering, isFalse);
    api.adapter.add(true);
    await pumpEventQueue();
    expect(api.discovering, isTrue);
  });

  test('start-while-unavailable no-throw + auto-resume', () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);

    // Start first scan
    await scanner.start(ScanProfile.balanced);
    await pumpEventQueue();
    expect(api.discovering, isTrue);

    // Adapter off → unavailable, discovery stops
    api.adapter.add(false);
    await pumpEventQueue();
    expect(api.discovering, isFalse);

    // Try to start while unavailable — should no-throw and queue the op
    await scanner.start(ScanProfile.balanced);
    await pumpEventQueue();
    // Still unavailable (no state change), so start() doesn't execute

    // Adapter back on → auto-resume
    api.adapter.add(true);
    await pumpEventQueue();
    expect(api.discovering, isTrue);
  });

  test('stop-while-unauthorized no-op', () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);

    await scanner.start(ScanProfile.balanced);
    await pumpEventQueue();

    // Revoke permission
    scanner.onPermissionRevoked();
    await pumpEventQueue();

    // Stop while unauthorized — should be a no-op (idempotent)
    await scanner.stop();
    await pumpEventQueue();
    // No exception thrown
  });

  test('rapid off-on-off settles unavailable with discovery stopped',
      () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);

    await scanner.start(ScanProfile.balanced);
    await pumpEventQueue();
    expect(api.discovering, isTrue);

    // Rapid off-on-off
    api.adapter.add(false);
    api.adapter.add(true);
    api.adapter.add(false);
    await pumpEventQueue();

    // Should settle to unavailable with discovery stopped
    expect(api.discovering, isFalse);
  });

  test('overlapping start calls invoke startDiscovery exactly once',
      () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);

    api.startCalls = 0;

    // Two overlapping starts (before first completes)
    final f1 = scanner.start(ScanProfile.balanced);
    final f2 = scanner.start(ScanProfile.balanced);

    await Future.wait([f1, f2]);
    await pumpEventQueue();

    // startDiscovery should have been called only once (first start goes
    // through; second start sees status != idle and returns early)
    expect(api.startCalls, 1);
  });

  test('dispose-during-in-flight-op no-throw (blocking fake)', () async {
    final api = _BlockingFakeBlueZApi();
    api.block();
    final scanner = BlueZScanner(api);

    // Start discovery (will block)
    final startFuture = scanner.start(ScanProfile.balanced);

    // Dispose while start is in flight
    final disposeFuture = Future<void>(() async {
      await Future<void>.delayed(Duration(milliseconds: 10));
      await scanner.dispose();
    });

    // Release the block
    await Future<void>.delayed(Duration(milliseconds: 50));
    api.unblock();

    // Wait for both to complete — neither should throw
    await Future.wait([startFuture, disposeFuture]);
  });
}

class _BlockingFakeBlueZApi implements BlueZApi {
  final adapter = StreamController<bool>.broadcast();
  final results = StreamController<ScanObservation>.broadcast();
  bool discovering = false;
  Completer<void>? _block;

  @override
  Stream<bool> adapterOn() => adapter.stream;
  @override
  Stream<ScanObservation> scanResults() => results.stream;

  @override
  Future<void> startDiscovery() async {
    if (_block != null) {
      await _block!.future;
    }
    discovering = true;
  }

  @override
  Future<void> stopDiscovery() async => discovering = false;

  void block() {
    _block = Completer<void>();
  }

  void unblock() {
    _block?.complete();
    _block = null;
  }
}

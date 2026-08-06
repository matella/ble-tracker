import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fbp/fbp_api.dart';
import 'package:ble_tracker/platform/fbp/flutter_blue_plus_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

class FakeFbpApi implements FbpApi {
  final adapter = StreamController<bool>.broadcast();
  final results = StreamController<ScanObservation>.broadcast();
  bool permissionGranted = true;
  bool scanning = false;
  bool? lastLowLatency;
  int startCalls = 0;

  @override
  Stream<bool> adapterOn() => adapter.stream;

  @override
  Stream<ScanObservation> scanResults() => results.stream;

  @override
  Future<void> startScan({required bool lowLatency}) async {
    startCalls++;
    if (!permissionGranted) throw FbpPermissionDenied();
    scanning = true;
    lastLowLatency = lowLatency;
  }

  @override
  Future<void> stopScan() async => scanning = false;
}

void main() {
  runBleScannerContract('FlutterBluePlusScanner', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    return ScannerHarness(
      scanner: scanner,
      emitObservation: api.results.add,
      adapterOff: () => api.adapter.add(false),
      adapterOn: () => api.adapter.add(true),
      revokePermission: () {
        api.permissionGranted = false;
        // Simulate the OS killing the scan: adapter callback surfaces it on
        // the next start attempt; scanner also polls via checkPermission —
        // here we surface it directly:
        scanner.onPermissionRevoked();
      },
    );
  });

  test('NFR-4: scan profile maps to plugin scan mode', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    await scanner.start(ScanProfile.lowLatency);
    expect(api.lastLowLatency, isTrue);
    await scanner.stop();
    await scanner.start(ScanProfile.balanced);
    expect(api.lastLowLatency, isFalse);
  });

  test('auto-resume restarts the plugin scan with the last profile', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    await scanner.start(ScanProfile.lowLatency);
    api.adapter.add(false);
    await pumpEventQueue();
    expect(api.scanning, isFalse);
    api.adapter.add(true);
    await pumpEventQueue();
    expect(api.scanning, isTrue);
    expect(api.lastLowLatency, isTrue);
  });

  test(
    'start while unavailable is a no-op that still updates resume profile',
    () async {
      final api = FakeFbpApi();
      final scanner = FlutterBluePlusScanner(api);
      await scanner.start(ScanProfile.balanced);
      api.adapter.add(false);
      await pumpEventQueue();
      await scanner.start(ScanProfile.lowLatency); // must not throw
      expect(api.scanning, isFalse);
      api.adapter.add(true);
      await pumpEventQueue();
      expect(api.scanning, isTrue);
      expect(api.lastLowLatency, isTrue); // resumed with the newest profile
    },
  );

  test('stop while unauthorized is a no-op', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    scanner.onPermissionRevoked();
    await pumpEventQueue();
    await scanner.stop(); // must not throw
  });

  test('rapid off-on-off settles unavailable with plugin stopped', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    final statuses = <ScannerStatus>[];
    scanner.status().listen(statuses.add);
    await scanner.start(ScanProfile.balanced);
    api.adapter.add(false);
    api.adapter.add(true);
    api.adapter.add(false);
    await pumpEventQueue();
    expect(statuses.last, ScannerStatus.unavailable);
    expect(api.scanning, isFalse);
  });

  test('overlapping start calls invoke the plugin exactly once', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    await Future.wait([
      scanner.start(ScanProfile.balanced),
      scanner.start(ScanProfile.balanced),
    ]);
    expect(api.startCalls, 1);
  });
}

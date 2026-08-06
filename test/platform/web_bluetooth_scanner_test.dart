import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/web/web_bluetooth_api.dart';
import 'package:ble_tracker/platform/web/web_bluetooth_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

class FakeWebApi implements WebBluetoothApi {
  final Map<String, double?> rssiById = {};
  final Map<String, String?> nameById = {};
  bool supported = true;
  String? nextRequestedDevice;

  @override
  bool get isSupported => supported;

  @override
  List<String> get pairedDeviceIds => rssiById.keys.toList();

  @override
  Future<String> requestDevice() async {
    final id = nextRequestedDevice!;
    rssiById[id] = -60;
    return id;
  }

  @override
  Future<double?> readRssi(String deviceId) async => rssiById[deviceId];

  @override
  Future<String?> deviceName(String deviceId) async => nameById[deviceId];
}

class _BlockingWebApi extends FakeWebApi {
  final rssiCompleter = Completer<double?>();
  @override
  Future<double?> readRssi(String deviceId) => rssiCompleter.future;
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  runBleScannerContract('WebBluetoothScanner', () async {
    final api = FakeWebApi();
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    var tickCount = 0;
    return ScannerHarness(
      scanner: scanner,
      // Web has no advertisement push; emulate by setting RSSI and ticking.
      emitObservation: (obs) {
        api.rssiById[obs.deviceId] = obs.rssi;
        api.nameById[obs.deviceId] = obs.advertisedName;
        scanner.overrideNextTimestamp(obs.timestamp);
        // txPower is never present on Web (no advertisement access):
        // the contract's field-mapping test tolerates null txPower via
        // the harness capability flag below.
        ticks.add(obs.timestamp.add(Duration(seconds: ++tickCount)));
      },
      adapterOff: () => scanner.onAdapterChanged(false),
      adapterOn: () => scanner.onAdapterChanged(true),
      revokePermission: scanner.onPermissionRevoked,
    );
  }, supportsTxPower: false);

  test('polls RSSI of paired devices on each tick while scanning', () async {
    final api = FakeWebApi();
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    api.rssiById['a'] = -55;
    final observations = <ScanObservation>[];
    scanner.observe().listen(observations.add);

    await scanner.start(ScanProfile.balanced);
    ticks.add(t0);
    await pumpEventQueue();
    expect(observations.single.deviceId, 'a');
    expect(observations.single.rssi, -55);

    await scanner.stop();
    ticks.add(t0.add(const Duration(seconds: 1)));
    await pumpEventQueue();
    expect(observations, hasLength(1)); // no polling when idle
  });

  test('pairNewDevice adds device via chooser and it gets polled', () async {
    final api = FakeWebApi()..nextRequestedDevice = 'new-dev';
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    final observations = <ScanObservation>[];
    scanner.observe().listen(observations.add);
    await scanner.start(ScanProfile.balanced);
    await scanner.pairNewDevice();
    ticks.add(t0);
    await pumpEventQueue();
    expect(observations.single.deviceId, 'new-dev');
  });

  test('dispose during in-flight tick does not throw or emit', () async {
    final api = _BlockingWebApi()..rssiById['a'] = -50;
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    final observations = <ScanObservation>[];
    scanner.observe().listen(observations.add);
    await scanner.start(ScanProfile.balanced);
    ticks.add(t0); // enters _onTick, parks on the blocked readRssi
    await pumpEventQueue();
    final disposing = scanner.dispose(); // must not throw
    api.rssiCompleter.complete(-50); // lets the parked tick resume
    await disposing;
    await pumpEventQueue();
    expect(observations, isEmpty); // resumed tick must not emit post-dispose
  });

  test('unsupported browser: start then stop does not throw', () async {
    final api = FakeWebApi()..supported = false;
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    final statuses = <ScannerStatus>[];
    scanner.status().listen(statuses.add);
    await scanner.start(ScanProfile.balanced);
    await scanner.stop(); // must not throw
    await pumpEventQueue();
    expect(statuses.last, ScannerStatus.unauthorized);
  });

  test('start while unavailable is a no-op, auto-resume still works', () async {
    final api = FakeWebApi();
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    final statuses = <ScannerStatus>[];
    scanner.status().listen(statuses.add);
    await scanner.start(ScanProfile.balanced);
    scanner.onAdapterChanged(false);
    await scanner.start(ScanProfile.balanced); // must not throw
    scanner.onAdapterChanged(true);
    await pumpEventQueue();
    expect(statuses.last, ScannerStatus.scanning);
  });

  test('pairNewDevice on unsupported browser is a no-op', () async {
    final api = FakeWebApi()..supported = false..nextRequestedDevice = 'x';
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    await scanner.pairNewDevice(); // must not throw
    expect(api.rssiById, isEmpty); // requestDevice never called
  });
}

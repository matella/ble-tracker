import 'dart:async';

import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/kalman_rssi_smoother.dart';
import 'package:ble_tracker/domain/log_distance_estimator.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/state/device_state_composer.dart';
import 'package:flutter_test/flutter_test.dart';

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: id, type: DeviceType.tag, trackingEnabled: tracking);

void main() {
  late StreamController<List<RegisteredDevice>> registry;
  late StreamController<ScanObservation> observations;
  late StreamController<DateTime> ticks;
  late DeviceStateComposer composer;
  late List<Map<String, TrackedDeviceState>> emitted;
  final config = ProximityConfig();
  final t0 = DateTime.utc(2026, 1, 1);

  setUp(() {
    registry = StreamController<List<RegisteredDevice>>.broadcast();
    observations = StreamController<ScanObservation>.broadcast();
    ticks = StreamController<DateTime>.broadcast();
    composer = DeviceStateComposer(
      registry: registry.stream,
      observations: observations.stream,
      ticks: ticks.stream,
      smoother: KalmanRssiSmoother(
          processNoise: config.processNoise,
          measurementNoise: config.measurementNoise),
      estimator: LogDistanceEstimator(config),
      config: config,
    );
    emitted = [];
    composer.states.listen(emitted.add);
  });

  tearDown(() {
    composer.dispose();
  });

  Future<void> pump() => pumpEventQueue();

  ScanObservation obs(String id, DateTime at, {double rssi = -59}) =>
      ScanObservation(deviceId: id, rssi: rssi, timestamp: at, txPower: -59);

  test('registered device starts notVisible', () async {
    registry.add([dev('a')]);
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.notVisible);
    expect(emitted.last['a']!.estimate, isNull);
  });

  test('observation makes device visible with estimate and lastSeen', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('a', t0));
    await pump();
    final s = emitted.last['a']!;
    expect(s.visibility, DeviceVisibility.visible);
    expect(s.estimate!.meters, closeTo(1.0, 0.01));
    expect(s.lastSeen, t0);
  });

  test('missing txPower falls back to config default', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(ScanObservation(deviceId: 'a', rssi: -59, timestamp: t0));
    await pump();
    // rssi == defaultTxPower (-59) → 1 m
    expect(emitted.last['a']!.estimate!.meters, closeTo(1.0, 0.01));
  });

  test('visible → notVisible at exactly T_stale; estimate cleared', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('a', t0));
    await pump();

    ticks.add(t0.add(const Duration(seconds: 9, milliseconds: 999)));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.visible);

    ticks.add(t0.add(const Duration(seconds: 10)));
    await pump();
    final s = emitted.last['a']!;
    expect(s.visibility, DeviceVisibility.notVisible);
    expect(s.estimate, isNull);
    expect(s.lastSeen, t0); // lastSeen preserved for fade-out rendering
  });

  test('re-acquisition resets the staleness timer', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('a', t0));
    await pump();
    ticks.add(t0.add(const Duration(seconds: 10)));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.notVisible);

    final t1 = t0.add(const Duration(seconds: 11));
    observations.add(obs('a', t1));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.visible);
    ticks.add(t1.add(const Duration(seconds: 9)));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.visible);
  });

  test('toggled-off device shows trackingOff and observations are ignored',
      () async {
    registry.add([dev('a', tracking: false)]);
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.trackingOff);
    observations.add(obs('a', t0));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.trackingOff);
    expect(emitted.last['a']!.estimate, isNull);
  });

  test('toggling off resets smoother state (fresh on re-enable)', () async {
    final resetIds = <String>[];
    final composer2 = DeviceStateComposer(
      registry: registry.stream,
      observations: observations.stream,
      ticks: ticks.stream,
      smoother: _SpySmoother(resetIds),
      estimator: LogDistanceEstimator(config),
      config: config,
    );
    composer2.states.listen((_) {});
    registry.add([dev('a')]);
    await pump();
    registry.add([dev('a', tracking: false)]);
    await pump();
    expect(resetIds, ['a']);
    composer2.dispose();
  });

  test('observations for unregistered devices are ignored', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('ghost', t0));
    await pump();
    expect(emitted.last.containsKey('ghost'), isFalse);
  });

  test('removed device disappears from state', () async {
    registry.add([dev('a'), dev('b')]);
    await pump();
    registry.add([dev('b')]);
    await pump();
    expect(emitted.last.keys, ['b']);
  });

  test('a registry stream error does not crash the composer — it keeps '
      'emitting once a normal update follows', () async {
    registry.addError(StateError('corrupt store'));
    await pump();
    expect(emitted, isEmpty); // nothing to emit yet, but no crash either

    registry.add([dev('a')]);
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.notVisible);

    observations.add(obs('a', t0));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.visible);
  });

  test('stale device is not resurrected by an unrelated registry emission',
      () async {
    registry.add([dev('a'), dev('b')]);
    await pump();
    observations.add(obs('a', t0));
    await pump();
    ticks.add(t0.add(const Duration(seconds: 10)));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.notVisible);

    registry.add([dev('a'), dev('b'), dev('c')]); // unrelated change
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.notVisible);
    expect(emitted.last['a']!.estimate, isNull);
  });
}

class _SpySmoother implements RssiSmoother {
  _SpySmoother(this.resetIds);
  final List<String> resetIds;
  @override
  double next(String deviceId, double rawRssi, DateTime at) => rawRssi;
  @override
  void reset(String deviceId) => resetIds.add(deviceId);
}

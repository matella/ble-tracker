import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProximityConfig defaults match spec', () {
    final c = ProximityConfig();
    expect(c.processNoise, 0.065);
    expect(c.measurementNoise, 1.4);
    expect(c.environmentFactor, 2.7);
    expect(c.defaultTxPower, -59.0);
    expect(c.immediateMaxMeters, 0.5);
    expect(c.nearMaxMeters, 3.0);
    expect(c.midMaxMeters, 10.0);
    expect(c.staleAfter, const Duration(seconds: 10));
    expect(c.blipFadeOut, const Duration(seconds: 2));
  });

  test('ProximityConfig rejects environment factor outside 2.0-4.0', () {
    expect(() => ProximityConfig(environmentFactor: 1.9), throwsArgumentError);
    expect(() => ProximityConfig(environmentFactor: 4.1), throwsArgumentError);
    expect(ProximityConfig(environmentFactor: 2.0).environmentFactor, 2.0);
    expect(ProximityConfig(environmentFactor: 4.0).environmentFactor, 4.0);
  });

  test('RegisteredDevice JSON roundtrip', () {
    const d = RegisteredDevice(
      id: 'aa:bb',
      name: 'Buds',
      type: DeviceType.headphones,
      trackingEnabled: false,
    );
    expect(RegisteredDevice.fromJson(d.toJson()), d);
  });

  test('value equality on core types', () {
    const est = DistanceEstimate(meters: 1.5, band: ProximityBand.near);
    const est2 = DistanceEstimate(meters: 1.5, band: ProximityBand.near);
    expect(est, est2);
    expect(est.hashCode, est2.hashCode);

    final t = DateTime.utc(2026);
    final obs = ScanObservation(
        deviceId: 'x', rssi: -60, txPower: -59, timestamp: t, advertisedName: 'n');
    final obs2 = ScanObservation(
        deviceId: 'x', rssi: -60, txPower: -59, timestamp: t, advertisedName: 'n');
    expect(obs, obs2);
    expect(obs.hashCode, obs2.hashCode);

    const device = RegisteredDevice(id: 'a', name: 'A', type: DeviceType.tag);
    const device2 = RegisteredDevice(id: 'a', name: 'A', type: DeviceType.tag);
    expect(device, device2);
    expect(device.hashCode, device2.hashCode);

    final state = TrackedDeviceState(
        device: device,
        visibility: DeviceVisibility.visible,
        estimate: est,
        lastSeen: t);
    final state2 = TrackedDeviceState(
        device: device2,
        visibility: DeviceVisibility.visible,
        estimate: est2,
        lastSeen: t);
    expect(state, state2);
    expect(state.hashCode, state2.hashCode);
    expect(
        state,
        isNot(TrackedDeviceState(
            device: device, visibility: DeviceVisibility.notVisible)));
  });
}

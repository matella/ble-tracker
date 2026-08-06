import 'dart:async';

import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRegistry implements DeviceRegistry {
  final controller = StreamController<List<RegisteredDevice>>.broadcast();
  @override
  Stream<List<RegisteredDevice>> watchAll() => controller.stream;
  @override
  Future<void> register(RegisteredDevice device) async {}
  @override
  Future<void> setTracking(String deviceId, bool enabled) async {}
  @override
  Future<void> rename(String deviceId, String name) async {}
  @override
  Future<void> remove(String deviceId) async {}
}

class _FakeScanner implements BleScanner {
  final observations = StreamController<ScanObservation>.broadcast();
  @override
  Stream<ScanObservation> observe() => observations.stream;
  @override
  Stream<ScannerStatus> status() => const Stream.empty();
  @override
  Future<void> start(ScanProfile profile) async {}
  @override
  Future<void> stop() async {}
}

void main() {
  test('deviceStatesProvider composes registry and observations', () async {
    final registry = _FakeRegistry();
    final scanner = _FakeScanner();
    final ticks = StreamController<DateTime>.broadcast();

    final container = ProviderContainer(overrides: [
      deviceRegistryProvider.overrideWithValue(registry),
      bleScannerProvider.overrideWithValue(scanner),
      tickerProvider.overrideWithValue(ticks.stream),
    ]);
    addTearDown(container.dispose);

    final states = <Map<String, TrackedDeviceState>>[];
    final sub = container.listen(deviceStatesProvider, (_, next) {
      next.whenData(states.add);
    });
    addTearDown(sub.close);

    registry.controller.add([
      const RegisteredDevice(id: 'a', name: 'a', type: DeviceType.tag),
    ]);
    await pumpEventQueue();
    scanner.observations.add(ScanObservation(
        deviceId: 'a', rssi: -59, txPower: -59, timestamp: DateTime.utc(2026)));
    await pumpEventQueue();

    expect(states.last['a']!.visibility, DeviceVisibility.visible);
  });

  test('platform-bound providers throw when not overridden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(bleScannerProvider), throwsA(anything));
    expect(() => container.read(deviceRegistryProvider), throwsA(anything));
  });
}

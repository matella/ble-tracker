import 'dart:async';

import 'package:ble_tracker/domain/key_value_store.dart';
import 'package:ble_tracker/domain/persistent_device_registry.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: 'name-$id', type: DeviceType.tag, trackingEnabled: tracking);

void main() {
  late FakeStore store;
  late PersistentDeviceRegistry registry;

  setUp(() {
    store = FakeStore();
    registry = PersistentDeviceRegistry(store);
  });

  test('watchAll emits current list to new subscribers', () async {
    await registry.register(dev('a'));
    expect(await registry.watchAll().first, [dev('a')]);
  });

  test('register persists and re-registering same id overwrites', () async {
    await registry.register(dev('a'));
    await registry.register(dev('a', tracking: false));
    final list = await registry.watchAll().first;
    expect(list.single.trackingEnabled, false);

    // A fresh registry over the same store sees persisted data.
    final reloaded = PersistentDeviceRegistry(store);
    expect(await reloaded.watchAll().first, list);
  });

  test('setTracking toggles and propagates on the stream', () async {
    await registry.register(dev('a'));
    final events = StreamController<List<RegisteredDevice>>();
    final sub = registry.watchAll().listen(events.add);
    await registry.setTracking('a', false);
    await pumpEventQueue();
    final last = (await events.stream.take(2).toList()).last;
    expect(last.single.trackingEnabled, false);
    await sub.cancel();
  });

  test('rename propagates', () async {
    await registry.register(dev('a'));
    await registry.rename('a', 'Left Earbud');
    expect((await registry.watchAll().first).single.name, 'Left Earbud');
  });

  test('remove deletes from registry and persistence', () async {
    await registry.register(dev('a'));
    await registry.remove('a');
    expect(await registry.watchAll().first, isEmpty);
    expect(await PersistentDeviceRegistry(store).watchAll().first, isEmpty);
  });

  test('mutating an unknown id throws ArgumentError', () async {
    expect(() => registry.setTracking('nope', true), throwsArgumentError);
    expect(() => registry.rename('nope', 'x'), throwsArgumentError);
    expect(() => registry.remove('nope'), throwsArgumentError);
  });

  test('no cap: 1000 devices register and round-trip', () async {
    for (var i = 0; i < 1000; i++) {
      await registry.register(dev('id-$i'));
    }
    expect((await registry.watchAll().first).length, 1000);
    expect(
        (await PersistentDeviceRegistry(store).watchAll().first).length, 1000);
  });
}

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

class _FailingStore implements KeyValueStore {
  bool failWrites = true;
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('disk full');
    data[key] = value;
  }
}

/// Every `read()` call gets its own [Completer], resolved manually by the
/// test — lets a test control exactly when a pending initial `_load()`
/// resolves relative to other concurrent operations.
class _SequencedReadStore implements KeyValueStore {
  final Map<String, String> data = {};
  final pending = <Completer<String?>>[];

  @override
  Future<String?> read(String key) {
    final completer = Completer<String?>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class _ThrowingReadStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('disk error');
  @override
  Future<void> write(String key, String value) async {}
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

  test('synchronous listen+cancel does not throw', () async {
    final sub = registry.watchAll().listen((_) {});
    await sub.cancel();
    await pumpEventQueue();
  });

  test('failed write leaves registry state unchanged', () async {
    final failing = _FailingStore();
    final r = PersistentDeviceRegistry(failing);
    await expectLater(r.register(dev('a')), throwsA(isA<StateError>()));
    failing.failWrites = false;
    expect(await r.watchAll().first, isEmpty);
  });

  test('an update that lands while the initial load is still pending is not '
      'dropped (delivered instead of a stale snapshot)', () async {
    final store = _SequencedReadStore();
    final r = PersistentDeviceRegistry(store);

    final events = <List<RegisteredDevice>>[];
    final sub = r.watchAll().listen(events.add);
    await pumpEventQueue();
    // onListen has subscribed to the internal broadcast controller and is
    // now awaiting the initial _load()'s read() — nothing delivered yet.
    expect(store.pending, hasLength(1));
    expect(events, isEmpty);

    // A concurrent register() races the same _load() gate (cache is still
    // unset) and gets its own read().
    final registerDone = r.register(dev('a'));
    await pumpEventQueue();
    expect(store.pending, hasLength(2));

    // Let register()'s load see no prior data, then its save completes —
    // this reaches _controller.add() while the initial load is still
    // pending, so it lands in the onListen buffer rather than `output`.
    store.pending[1].complete(null);
    await registerDone;
    expect(events, isEmpty); // still buffered, not yet delivered

    // Now let the original initial-load read resolve (also no prior data).
    store.pending[0].complete(null);
    await pumpEventQueue();

    // The buffered update wins over the (now stale) empty snapshot.
    expect(events.single, [dev('a')]);
    await sub.cancel();
  });

  test('corrupt store contents are treated as an empty registry, and '
      'register() recovers', () async {
    final corrupt = FakeStore();
    corrupt.data[PersistentDeviceRegistry.storageKey] = 'not json';
    final r = PersistentDeviceRegistry(corrupt);

    expect(await r.watchAll().first, isEmpty);

    await r.register(dev('a'));
    expect(await r.watchAll().first, [dev('a')]);
    // The next successful save overwrote the corrupt raw string.
    expect(await PersistentDeviceRegistry(corrupt).watchAll().first, [dev('a')]);
  });

  test('watchAll surfaces an error from the initial load to subscribers',
      () async {
    final r = PersistentDeviceRegistry(_ThrowingReadStore());
    final errors = <Object>[];
    final sub = r.watchAll().listen((_) {}, onError: errors.add);
    await pumpEventQueue();
    expect(errors.single, isA<StateError>());
    await sub.cancel();
  });
}

import 'package:ble_tracker/domain/key_value_store.dart';
import 'package:ble_tracker/domain/settings.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements KeyValueStore {
  _MemoryStore({this.failWrites = false});

  final bool failWrites;
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('disk full');
    data[key] = value;
  }
}

ProviderContainer _container({
  required KeyValueStore store,
  double initial = defaultEnvironmentFactor,
}) {
  final container = ProviderContainer(overrides: [
    settingsStoreProvider.overrideWithValue(store),
    initialEnvironmentFactorProvider.overrideWithValue(initial),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('starts from the value loaded at startup', () {
    final c = _container(store: _MemoryStore(), initial: 3.1);
    expect(c.read(environmentFactorProvider), 3.1);
    expect(c.read(proximityConfigProvider).environmentFactor, 3.1);
  });

  test('set persists the value and rebuilds the config', () async {
    final store = _MemoryStore();
    final c = _container(store: store);

    await c.read(environmentFactorProvider.notifier).set(3.5);

    expect(c.read(environmentFactorProvider), 3.5);
    expect(c.read(proximityConfigProvider).environmentFactor, 3.5);
    expect(store.data[environmentFactorStorageKey], '3.5');
  });

  test('without a stored value, starts at the default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
        container.read(environmentFactorProvider), defaultEnvironmentFactor);
  });

  test('a failed write still applies for this session', () async {
    final c = _container(store: _MemoryStore(failWrites: true));

    await c.read(environmentFactorProvider.notifier).set(2.2);

    expect(c.read(environmentFactorProvider), 2.2);
    expect(c.read(proximityConfigProvider).environmentFactor, 2.2);
  });
}

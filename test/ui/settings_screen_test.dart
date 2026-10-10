import 'package:ble_tracker/domain/key_value_store.dart';
import 'package:ble_tracker/domain/settings.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/device_list_screen.dart';
import 'package:ble_tracker/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry, overridesWith;

class _MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

void main() {
  Future<({ProviderContainer container, _MemoryStore store})> pumpSettings(
      WidgetTester tester) async {
    final store = _MemoryStore();
    final container = ProviderContainer(overrides: [
      settingsStoreProvider.overrideWithValue(store),
      initialEnvironmentFactorProvider.overrideWithValue(defaultEnvironmentFactor),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    return (container: container, store: store);
  }

  Slider slider(WidgetTester tester) =>
      tester.widget<Slider>(find.byKey(const Key('environment-factor-slider')));

  testWidgets('shows the current factor', (tester) async {
    await pumpSettings(tester);
    expect(find.text('n = 2.7'), findsOneWidget);
  });

  testWidgets('dragging updates the display but does not persist yet',
      (tester) async {
    final h = await pumpSettings(tester);

    slider(tester).onChanged!(3.0);
    await tester.pump();

    expect(find.text('n = 3.0'), findsOneWidget);
    expect(h.store.data, isEmpty);
    expect(h.container.read(environmentFactorProvider), defaultEnvironmentFactor);
  });

  testWidgets('releasing the thumb persists and applies the value',
      (tester) async {
    final h = await pumpSettings(tester);

    slider(tester).onChanged!(3.46);
    slider(tester).onChangeEnd!(3.46);
    await tester.pump();

    expect(find.text('n = 3.5'), findsOneWidget); // rounded to one decimal
    expect(h.store.data[environmentFactorStorageKey], '3.5');
    expect(h.container.read(proximityConfigProvider).environmentFactor, 3.5);
  });

  testWidgets('Devices app bar opens settings', (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: scanner),
      child: const MaterialApp(home: DeviceListScreen()),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}

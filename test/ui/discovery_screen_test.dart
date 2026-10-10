import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/discovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry;

/// Riverpod delivers stream events a microtask after the emit, so one pump
/// is not enough to see the rebuild; two are.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  Future<({FakeBleScanner scanner, RecordingRegistry registry, StreamController<DateTime> ticks})>
      pumpDiscovery(WidgetTester tester) async {
    final scanner = FakeBleScanner();
    final registry = RecordingRegistry([]);
    final ticks = StreamController<DateTime>.broadcast();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        deviceRegistryProvider.overrideWithValue(registry),
        bleScannerProvider.overrideWithValue(scanner),
        tickerProvider.overrideWithValue(ticks.stream),
      ],
      child: const MaterialApp(home: DiscoveryScreen()),
    ));
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    addTearDown(ticks.close);
    return (scanner: scanner, registry: registry, ticks: ticks);
  }

  testWidgets('Track registers the discovered device', (tester) async {
    final h = await pumpDiscovery(tester);
    h.scanner.emit(ScanObservation(
      deviceId: 'buds',
      rssi: -61,
      timestamp: t0,
      advertisedName: 'Buds',
    ));
    await settle(tester);

    await tester.tap(find.text('Track'));
    await tester.pump();

    expect(h.registry.calls, [
      (
        'register',
        RegisteredDevice(id: 'buds', name: 'Buds', type: DeviceType.other),
      ),
    ]);
  });

  testWidgets('a discovered device is dropped once it goes stale',
      (tester) async {
    final h = await pumpDiscovery(tester);
    h.scanner.emit(ScanObservation(
      deviceId: 'buds',
      rssi: -61,
      timestamp: t0,
      advertisedName: 'Buds',
    ));
    await settle(tester);
    expect(find.text('Buds'), findsOneWidget);

    // Still fresh just before the staleness window (ProximityConfig default).
    h.ticks.add(t0.add(const Duration(seconds: 9)));
    await settle(tester);
    expect(find.text('Buds'), findsOneWidget);

    // At the window: no longer advertising, so it leaves the list.
    h.ticks.add(t0.add(const Duration(seconds: 10)));
    await settle(tester);
    expect(find.text('Buds'), findsNothing);
  });
}

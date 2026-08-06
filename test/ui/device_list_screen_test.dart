import 'dart:async';

import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/default_platform_capabilities.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/device_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingRegistry implements DeviceRegistry {
  RecordingRegistry(this.devices);
  final List<RegisteredDevice> devices;
  final calls = <(String, Object?)>[];
  final _controller = StreamController<List<RegisteredDevice>>.broadcast();

  @override
  Stream<List<RegisteredDevice>> watchAll() async* {
    yield devices;
    yield* _controller.stream;
  }

  @override
  Future<void> register(RegisteredDevice device) async =>
      calls.add(('register', device));
  @override
  Future<void> setTracking(String deviceId, bool enabled) async =>
      calls.add(('setTracking', (deviceId, enabled)));
  @override
  Future<void> rename(String deviceId, String name) async =>
      calls.add(('rename', (deviceId, name)));
  @override
  Future<void> remove(String deviceId) async => calls.add(('remove', deviceId));
}

Widget app(List<Override> overrides) => ProviderScope(
    overrides: overrides, child: const MaterialApp(home: DeviceListScreen()));

List<Override> overridesWith({
  required RecordingRegistry registry,
  required FakeBleScanner scanner,
  CapabilityTier tier = CapabilityTier.tierA,
}) {
  final ticks = StreamController<DateTime>.broadcast();
  return [
    deviceRegistryProvider.overrideWithValue(registry),
    bleScannerProvider.overrideWithValue(scanner),
    tickerProvider.overrideWithValue(ticks.stream),
    platformCapabilitiesProvider.overrideWithValue(
      DefaultPlatformCapabilities(
        platform: TargetPlatform.android,
        isWeb: tier == CapabilityTier.tierC,
      ),
    ),
  ];
}

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: 'Device $id', type: DeviceType.tag,
    trackingEnabled: tracking);

void main() {
  testWidgets('renders all three visibility states', (tester) async {
    final registry = RecordingRegistry([dev('a'), dev('b'), dev('c', tracking: false)]);
    final scanner = FakeBleScanner();
    await tester.pumpWidget(app(overridesWith(registry: registry, scanner: scanner)));
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    scanner.emit(ScanObservation(
        deviceId: 'a', rssi: -59, txPower: -59, timestamp: DateTime.utc(2026)));
    await tester.pump();

    expect(find.textContaining('1.0 m'), findsOneWidget); // a: visible + distance
    expect(find.textContaining('near'), findsOneWidget); // FR-11 band shown
    expect(find.text('Not visible'), findsOneWidget); // b
    expect(find.text('Tracking off'), findsOneWidget); // c
  });

  testWidgets('toggle dispatches setTracking', (tester) async {
    final registry = RecordingRegistry([dev('a')]);
    await tester.pumpWidget(app(
        overridesWith(registry: registry, scanner: FakeBleScanner())));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tracking-toggle-a')));
    await tester.pump();
    expect(registry.calls, contains(('setTracking', ('a', false))));
  });

  testWidgets('Tier A shows auto-discovery note, no manual pair button',
      (tester) async {
    await tester.pumpWidget(app(overridesWith(
        registry: RecordingRegistry([]), scanner: FakeBleScanner())));
    await tester.pump();
    expect(find.byKey(const Key('auto-discover-note')), findsOneWidget);
    expect(find.byKey(const Key('manual-pair-button')), findsNothing);
  });

  testWidgets('Tier C hides auto-discovery, shows manual pair', (tester) async {
    await tester.pumpWidget(app(overridesWith(
        registry: RecordingRegistry([]),
        scanner: FakeBleScanner(),
        tier: CapabilityTier.tierC)));
    await tester.pump();
    expect(find.byKey(const Key('auto-discover-note')), findsNothing);
    expect(find.byKey(const Key('manual-pair-button')), findsOneWidget);
  });

  testWidgets('status banner surfaces unavailable and unauthorized states',
      (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(app(
        overridesWith(registry: RecordingRegistry([]), scanner: scanner)));
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    scanner.setAdapterOff();
    await tester.pump();
    expect(find.textContaining('Bluetooth is off'), findsOneWidget);
    scanner.setAdapterOn();
    await tester.pump();
    expect(find.textContaining('Bluetooth is off'), findsNothing);
    scanner.revokePermission();
    await tester.pump();
    expect(find.textContaining('permission'), findsOneWidget);
  });
}

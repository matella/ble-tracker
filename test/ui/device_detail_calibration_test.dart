import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/device_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry, dev;

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  Future<({FakeBleScanner scanner, RecordingRegistry registry})> pumpSheet(
    WidgetTester tester, {
    RegisteredDevice? device,
  }) async {
    final scanner = FakeBleScanner();
    final registry = RecordingRegistry([device ?? dev('a')]);
    final ticks = StreamController<DateTime>.broadcast();
    addTearDown(ticks.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceRegistryProvider.overrideWithValue(registry),
          bleScannerProvider.overrideWithValue(scanner),
          tickerProvider.overrideWithValue(ticks.stream),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DeviceDetailSheet(deviceId: 'a')),
        ),
      ),
    );
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    return (scanner: scanner, registry: registry);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  void emitAt(FakeBleScanner scanner, DateTime at, double rssi) =>
      scanner.emit(ScanObservation(deviceId: 'a', rssi: rssi, timestamp: at));

  testWidgets('calibrate: 1 m readings are averaged and saved', (tester) async {
    final h = await pumpSheet(tester);
    emitAt(h.scanner, t0, -58); // makes the device visible
    await settle(tester);

    await tester.tap(find.byKey(const Key('calibrate-button')));
    await settle(tester);
    // 12 steady readings spanning 5.5 s: enough samples and a full window.
    for (var i = 0; i < 12; i++) {
      emitAt(h.scanner, t0.add(Duration(milliseconds: 500 * i)), -58);
      await settle(tester);
    }

    expect(find.textContaining('Measured -58 dBm at 1 m'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-calibration')));
    await settle(tester);

    expect(h.registry.calls, contains(('setCalibration', ('a', -58.0))));
  });

  testWidgets('calibrate is disabled until the device is visible', (
    tester,
  ) async {
    await pumpSheet(tester);
    await settle(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('calibrate-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('an implausible reading is refused, not saved', (tester) async {
    final h = await pumpSheet(tester);
    emitAt(h.scanner, t0, -58);
    await settle(tester);
    await tester.tap(find.byKey(const Key('calibrate-button')));
    await settle(tester);
    for (var i = 0; i < 12; i++) {
      emitAt(h.scanner, t0.add(Duration(milliseconds: 500 * i)), -10);
      await settle(tester);
    }

    await tester.tap(find.byKey(const Key('save-calibration')));
    await settle(tester);

    expect(find.textContaining('looks wrong'), findsOneWidget);
    expect(h.registry.calls.where((c) => c.$1 == 'setCalibration'), isEmpty);
  });

  testWidgets('reset clears an existing calibration', (tester) async {
    final h = await pumpSheet(tester, device: dev('a').withCalibration(-58));
    await settle(tester);

    await tester.tap(find.byKey(const Key('reset-calibration')));
    await settle(tester);

    expect(h.registry.calls, contains(('setCalibration', ('a', null))));
  });
}

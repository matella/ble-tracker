import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/ui/device_detail_sheet.dart';
import 'package:ble_tracker/ui/radar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry, overridesWith, dev;

void main() {
  testWidgets('blip renders for visible device and tap opens detail sheet',
      (tester) async {
    final scanner = FakeBleScanner();
    final registry = RecordingRegistry([dev('a')]);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(registry: registry, scanner: scanner),
      child: const MaterialApp(home: RadarScreen()),
    ));
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    scanner.emit(ScanObservation(
        deviceId: 'a', rssi: -59, txPower: -59, timestamp: DateTime.utc(2026)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Tap at the blip's computed position.
    final radar = find.byKey(const Key('radar-canvas'));
    expect(radar, findsOneWidget);
    final state = tester.state<RadarScreenState>(find.byType(RadarScreen));
    final blip = state.currentBlips.single;
    final box = tester.renderObject<RenderBox>(radar);
    final center = box.size.center(Offset.zero);
    final canvasRadius = box.size.shortestSide / 2;
    final tapLocal = center +
        Offset.fromDirection(blip.angle, blip.radius * canvasRadius);
    await tester.tapAt(box.localToGlobal(tapLocal));
    // NOTE: pumpAndSettle() hangs here — RadarScreen's sweep
    // AnimationController repeats indefinitely (FR-16), so the tree never
    // goes idle even after the modal bottom sheet's own entrance animation
    // finishes. Step forward with bounded pumps instead: one to start the
    // route transition, then enough elapsed time to clear the default
    // ModalBottomSheetRoute transition duration (~250ms).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DeviceDetailSheet), findsOneWidget);
    expect(find.textContaining('Device a'), findsWidgets); // name
    expect(find.textContaining('-59'), findsOneWidget); // raw RSSI
    expect(find.textContaining('1.0 m'), findsOneWidget); // smoothed distance
    expect(find.textContaining('near'), findsOneWidget); // band
  });

  testWidgets('sweep animation advances between frames', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: FakeBleScanner()),
      child: const MaterialApp(home: RadarScreen()),
    ));
    await tester.pump();
    final state = tester.state<RadarScreenState>(find.byType(RadarScreen));
    final a1 = state.sweepAngle;
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.sweepAngle, isNot(a1));
  });
}

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry, overridesWith;

void main() {
  testWidgets(
      'NFR-4: radar tab starts lowLatency scan, devices tab switches to balanced',
      (tester) async {
    final scanner = _ProfileSpy();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: scanner.fake),
      child: const BleTrackerApp(),
    ));
    // NOTE: pumpAndSettle() hangs here — RadarScreen's sweep
    // AnimationController repeats indefinitely (FR-16) and IndexedStack
    // keeps every tab mounted, so the tree never goes idle even on the
    // Devices tab. Step forward with bounded pumps instead (matches
    // radar_screen_test.dart's convention).
    await tester.pump(); // build
    await tester.pump(); // flush the postFrameCallback that starts the scan

    expect(scanner.profiles.last, ScanProfile.lowLatency); // radar is home tab

    await tester.tap(find.text('Devices'));
    await tester.pump(); // rebuild on tab switch
    await tester.pump(); // flush stop().then(start(...))
    expect(scanner.profiles.last, ScanProfile.balanced);
  });

  testWidgets(
      'tab switch while unavailable preserves banner state and does not throw',
      (tester) async {
    final scanner = FakeBleScanner();
    final container = ProviderContainer(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: scanner),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const BleTrackerApp(),
    ));
    await tester.pump(); // build
    await tester.pump(); // flush the postFrameCallback that starts the scan
    expect(scanner.startedProfiles, [ScanProfile.lowLatency]);

    scanner.setAdapterOff();
    await tester.pump();
    expect(container.read(scannerStatusProvider).value,
        ScannerStatus.unavailable);

    // Switching tabs while unavailable must not attempt stop()+start() —
    // that would fight the recoverable-state banner — and must not throw.
    await tester.tap(find.text('Devices'));
    await tester.pump();
    await tester.pump();

    expect(scanner.startedProfiles, [ScanProfile.lowLatency]); // unchanged
    expect(container.read(scannerStatusProvider).value,
        ScannerStatus.unavailable); // banner state preserved
  });
}

class _ProfileSpy {
  final fake = FakeBleScanner();
  List<ScanProfile> get profiles => fake.startedProfiles;
}

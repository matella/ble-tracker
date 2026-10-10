import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry, overridesWith;

void main() {
  _addVisibilityTests();
  _addResumeNoticeTests();
  _addBackgroundServiceTests();

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

// The framework asserts valid transitions (resumed → inactive → hidden and
// back), so the helpers step through `inactive` like the platform does.
void _hide(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
}

void _show(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void _addVisibilityTests() {
  testWidgets('FR-19 Tier C: hiding the tab stops the scan, showing resumes it',
      (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]),
          scanner: scanner,
          tier: CapabilityTier.tierC),
      child: const BleTrackerApp(),
    ));
    await tester.pump();
    await tester.pump();
    expect(scanner.currentStatus, ScannerStatus.scanning);

    _hide(tester);
    await tester.pump();
    await tester.pump();
    expect(scanner.currentStatus, ScannerStatus.idle);

    _show(tester);
    await tester.pump();
    await tester.pump();
    expect(scanner.currentStatus, ScannerStatus.scanning);
    expect(scanner.startedProfiles.last, ScanProfile.lowLatency); // radar tab
  });

  testWidgets('tab visibility change does not pause a Tier A scan',
      (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: scanner),
      child: const BleTrackerApp(),
    ));
    await tester.pump();
    await tester.pump();

    _hide(tester);
    await tester.pump();
    await tester.pump();
    expect(scanner.currentStatus, ScannerStatus.scanning);
  });

  testWidgets('Tier C: showing the tab does not start a scan that was not running',
      (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]),
          scanner: scanner,
          tier: CapabilityTier.tierC),
      child: const BleTrackerApp(),
    ));
    await tester.pump();
    await tester.pump();
    scanner.setAdapterOff();
    await tester.pump();
    await tester.pump();

    _hide(tester);
    _show(tester);
    await tester.pump();
    await tester.pump();
    expect(scanner.startedProfiles, [ScanProfile.lowLatency]); // not restarted
  });
}

void _addResumeNoticeTests() {
  testWidgets(
      'FR-19 Tier B: returning from background shows the paused notice until the next observation',
      (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]),
          scanner: scanner,
          tier: CapabilityTier.tierB),
      child: const BleTrackerApp(),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('paused in the background'), findsNothing);

    _hide(tester);
    _show(tester);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('paused in the background'), findsWidgets);

    scanner.emit(ScanObservation(
        deviceId: 'x', rssi: -60, timestamp: DateTime.utc(2026)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('paused in the background'), findsNothing);
  });

  testWidgets('Tier A does not show the resume notice', (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: scanner),
      child: const BleTrackerApp(),
    ));
    await tester.pump();
    await tester.pump();

    _hide(tester);
    _show(tester);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('paused in the background'), findsNothing);
  });
}

void _addBackgroundServiceTests() {
  testWidgets('FR-19 Tier A: the background host follows the scan (on, then off)',
      (tester) async {
    final scanner = FakeBleScanner();
    final host = _RecordingHost();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overridesWith(registry: RecordingRegistry([]), scanner: scanner),
        backgroundScanHostProvider.overrideWithValue(host),
      ],
      child: const BleTrackerApp(),
    ));
    await tester.pump();
    await tester.pump();
    expect(host.calls, [true]);

    await scanner.stop();
    await tester.pump();
    await tester.pump();
    expect(host.calls, [true, false]);
  });

  testWidgets('FR-19 Tier B: the background host is never started',
      (tester) async {
    final scanner = FakeBleScanner();
    final host = _RecordingHost();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overridesWith(
            registry: RecordingRegistry([]),
            scanner: scanner,
            tier: CapabilityTier.tierB),
        backgroundScanHostProvider.overrideWithValue(host),
      ],
      child: const BleTrackerApp(),
    ));
    await tester.pump();
    await tester.pump();
    expect(scanner.currentStatus, ScannerStatus.scanning);
    expect(host.calls, isEmpty);
  });
}

class _RecordingHost implements BackgroundScanHost {
  final calls = <bool>[];
  @override
  Future<void> setActive(bool active) async => calls.add(active);
}

class _ProfileSpy {
  final fake = FakeBleScanner();
  List<ScanProfile> get profiles => fake.startedProfiles;
}

import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

class ScannerHarness {
  ScannerHarness({
    required this.scanner,
    required this.emitObservation,
    required this.adapterOff,
    required this.adapterOn,
    required this.revokePermission,
  });

  final BleScanner scanner;
  final void Function(ScanObservation) emitObservation;
  final void Function() adapterOff;
  final void Function() adapterOn;
  final void Function() revokePermission;
}

/// §7.3: every adapter runs this identical suite with its own fake backend.
///
/// [supportsTxPower] and [supportsAdvertisedName] let Tier C adapters (Web:
/// no advertisement access) opt out of asserting those fields round-trip —
/// default true preserves the original strict assertions for every other
/// adapter.
void runBleScannerContract(
  String name,
  Future<ScannerHarness> Function() createHarness, {
  bool supportsTxPower = true,
  bool supportsAdvertisedName = true,
}) {
  group('BleScanner contract: $name', () {
    late ScannerHarness h;
    late List<ScannerStatus> statuses;
    late List<ScanObservation> observations;

    setUp(() async {
      h = await createHarness();
      statuses = [];
      observations = [];
      h.scanner.status().listen(statuses.add);
      h.scanner.observe().listen(observations.add);
      await pumpEventQueue();
    });

    test('start emits scanning status', () async {
      await h.scanner.start(ScanProfile.balanced);
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.scanning);
    });

    test('observations map backend fields correctly', () async {
      await h.scanner.start(ScanProfile.balanced);
      final t = DateTime.utc(2026, 3, 1);
      h.emitObservation(ScanObservation(
        deviceId: 'id-1',
        rssi: -61,
        txPower: -59,
        timestamp: t,
        advertisedName: 'Buds',
      ));
      await pumpEventQueue();
      final o = observations.single;
      expect(o.deviceId, 'id-1');
      expect(o.rssi, -61);
      expect(o.txPower, supportsTxPower ? -59 : isNull);
      expect(o.timestamp, t);
      if (supportsAdvertisedName) expect(o.advertisedName, 'Buds');
    });

    test('adapter off mid-scan → unavailable; on → auto-resume scanning',
        () async {
      await h.scanner.start(ScanProfile.balanced);
      await pumpEventQueue();
      h.adapterOff();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.unavailable);
      h.adapterOn();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.scanning);
    });

    test('stop is idempotent', () async {
      await h.scanner.start(ScanProfile.balanced);
      await h.scanner.stop();
      await h.scanner.stop();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.idle);
    });

    test('permission revoked → unauthorized; observe() never errors',
        () async {
      await h.scanner.start(ScanProfile.balanced);
      await pumpEventQueue();
      h.revokePermission();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.unauthorized);
      // The observation stream must not have errored (listener above would throw).
    });
  });
}

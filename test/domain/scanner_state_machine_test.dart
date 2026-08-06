import 'package:ble_tracker/domain/scanner_state_machine.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

ScannerStateMachine machineAt(ScannerStatus s) {
  final m = ScannerStateMachine();
  switch (s) {
    case ScannerStatus.idle:
      break;
    case ScannerStatus.scanning:
      m.apply(ScannerEvent.start);
    case ScannerStatus.unavailable:
      m.apply(ScannerEvent.start);
      m.apply(ScannerEvent.adapterOff);
    case ScannerStatus.unauthorized:
      m.apply(ScannerEvent.permissionRevoked);
  }
  return m;
}

void main() {
  test('initial status is idle', () {
    expect(ScannerStateMachine().status, ScannerStatus.idle);
  });

  test('idle --start--> scanning', () {
    expect(machineAt(ScannerStatus.idle).apply(ScannerEvent.start),
        ScannerStatus.scanning);
  });

  test('scanning --stop--> idle', () {
    expect(machineAt(ScannerStatus.scanning).apply(ScannerEvent.stop),
        ScannerStatus.idle);
  });

  test('stop is idempotent from idle', () {
    expect(machineAt(ScannerStatus.idle).apply(ScannerEvent.stop),
        ScannerStatus.idle);
  });

  test('scanning --adapterOff--> unavailable', () {
    expect(machineAt(ScannerStatus.scanning).apply(ScannerEvent.adapterOff),
        ScannerStatus.unavailable);
  });

  test('unavailable --adapterOn--> scanning (auto-resume)', () {
    expect(machineAt(ScannerStatus.unavailable).apply(ScannerEvent.adapterOn),
        ScannerStatus.scanning);
  });

  test('any --permissionRevoked--> unauthorized', () {
    for (final s in ScannerStatus.values) {
      if (s == ScannerStatus.unauthorized) continue;
      expect(machineAt(s).apply(ScannerEvent.permissionRevoked),
          ScannerStatus.unauthorized, reason: 'from $s');
    }
  });

  test('unauthorized --permissionGranted--> idle, then start --> scanning', () {
    final m = machineAt(ScannerStatus.unauthorized);
    expect(m.apply(ScannerEvent.permissionGranted), ScannerStatus.idle);
    expect(m.apply(ScannerEvent.start), ScannerStatus.scanning);
  });

  test('unavailable --stop--> idle', () {
    expect(machineAt(ScannerStatus.unavailable).apply(ScannerEvent.stop),
        ScannerStatus.idle);
  });

  test('permissionRevoked from unauthorized stays unauthorized', () {
    expect(
        machineAt(ScannerStatus.unauthorized)
            .apply(ScannerEvent.permissionRevoked),
        ScannerStatus.unauthorized);
  });

  test('illegal transitions are rejected', () {
    expect(() => machineAt(ScannerStatus.idle).apply(ScannerEvent.adapterOn),
        throwsA(isA<IllegalTransitionError>()));
    expect(() => machineAt(ScannerStatus.scanning).apply(ScannerEvent.start),
        throwsA(isA<IllegalTransitionError>()));
    expect(
        () => machineAt(ScannerStatus.unauthorized).apply(ScannerEvent.start),
        throwsA(isA<IllegalTransitionError>()));
    expect(
        () => machineAt(ScannerStatus.unavailable).apply(ScannerEvent.start),
        throwsA(isA<IllegalTransitionError>()));
  });
}

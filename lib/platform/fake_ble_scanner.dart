import 'dart:async';

import '../domain/interfaces.dart';
import '../domain/scanner_state_machine.dart';
import '../domain/types.dart';

/// In-memory scanner: reference implementation for the contract suite and
/// the backend for widget tests.
class FakeBleScanner implements BleScanner {
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();

  ScannerStatus get currentStatus => _machine.status;

  void _apply(ScannerEvent event) {
    _statuses.add(_machine.apply(event));
  }

  void emit(ScanObservation observation) {
    if (_machine.status == ScannerStatus.scanning) {
      _observations.add(observation);
    }
  }

  void setAdapterOff() => _apply(ScannerEvent.adapterOff);
  void setAdapterOn() => _apply(ScannerEvent.adapterOn);
  void revokePermission() => _apply(ScannerEvent.permissionRevoked);
  void grantPermission() => _apply(ScannerEvent.permissionGranted);

  @override
  Stream<ScanObservation> observe() => _observations.stream;

  @override
  Stream<ScannerStatus> status() async* {
    yield _machine.status;
    yield* _statuses.stream;
  }

  @override
  Future<void> start(ScanProfile profile) async {
    if (_machine.status != ScannerStatus.scanning) {
      _apply(ScannerEvent.start);
    }
  }

  @override
  Future<void> stop() async {
    if (_machine.status != ScannerStatus.idle) {
      _apply(ScannerEvent.stop);
    }
  }
}

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

  /// Profiles from accepted `start()` calls (i.e. not idempotent no-ops),
  /// in order. Lets widget tests assert NFR-4 scan-profile-per-screen
  /// switching without needing a real platform scanner.
  final startedProfiles = <ScanProfile>[];

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
    // Matches the real adapters: start() only does anything from idle — a
    // no-op elsewhere (including unavailable/unauthorized), not an
    // IllegalTransitionError.
    if (_machine.status != ScannerStatus.idle) return;
    startedProfiles.add(profile);
    _apply(ScannerEvent.start);
  }

  @override
  Future<void> stop() async {
    switch (_machine.status) {
      case ScannerStatus.scanning:
      case ScannerStatus.unavailable:
        _apply(ScannerEvent.stop);
      case ScannerStatus.idle:
      case ScannerStatus.unauthorized:
        return; // no-op — no legal stop transition from these states
    }
  }
}

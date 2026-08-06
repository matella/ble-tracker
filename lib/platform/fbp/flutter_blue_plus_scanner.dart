import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/scanner_state_machine.dart';
import '../../domain/types.dart';
import 'fbp_api.dart';

class FlutterBluePlusScanner implements BleScanner {
  FlutterBluePlusScanner(this._api) {
    _adapterSub = _api.adapterOn().listen(_onAdapterChanged);
    _resultsSub = _api.scanResults().listen(_observations.add);
  }

  final FbpApi _api;
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();
  late final StreamSubscription<bool> _adapterSub;
  late final StreamSubscription<ScanObservation> _resultsSub;
  ScanProfile _lastProfile = ScanProfile.balanced;

  void _apply(ScannerEvent event) => _statuses.add(_machine.apply(event));

  Future<void> _onAdapterChanged(bool on) async {
    if (!on && _machine.status == ScannerStatus.scanning) {
      await _api.stopScan();
      _apply(ScannerEvent.adapterOff);
    } else if (on && _machine.status == ScannerStatus.unavailable) {
      await _api.startScan(
          lowLatency: _lastProfile == ScanProfile.lowLatency);
      _apply(ScannerEvent.adapterOn); // §5.4 auto-resume
    }
  }

  /// Called by the permission plumbing when BLE permission is revoked
  /// mid-session (NFR-6).
  void onPermissionRevoked() {
    if (_machine.status != ScannerStatus.unauthorized) {
      _apply(ScannerEvent.permissionRevoked);
    }
  }

  @override
  Stream<ScanObservation> observe() => _observations.stream;

  @override
  Stream<ScannerStatus> status() async* {
    yield _machine.status;
    yield* _statuses.stream;
  }

  @override
  Future<void> start(ScanProfile profile) async {
    if (_machine.status == ScannerStatus.scanning) return;
    _lastProfile = profile;
    try {
      await _api.startScan(lowLatency: profile == ScanProfile.lowLatency);
    } on FbpPermissionDenied {
      onPermissionRevoked();
      return;
    }
    _apply(ScannerEvent.start);
  }

  @override
  Future<void> stop() async {
    if (_machine.status == ScannerStatus.idle) return; // idempotent
    await _api.stopScan();
    _apply(ScannerEvent.stop);
  }

  /// Releases the underlying plugin stream subscriptions. Not part of
  /// [BleScanner] — call when this scanner instance is being torn down
  /// for good (e.g. app shutdown), not between scans.
  Future<void> dispose() async {
    await _adapterSub.cancel();
    await _resultsSub.cancel();
  }
}

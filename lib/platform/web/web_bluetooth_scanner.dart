import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/scanner_state_machine.dart';
import '../../domain/types.dart';
import 'web_bluetooth_api.dart';

/// Tier C: no advertisement scanning. Polls RSSI of manually-paired devices
/// on each injected tick (>= 1 Hz in production wiring, FR-18).
class WebBluetoothScanner implements BleScanner {
  WebBluetoothScanner({
    required WebBluetoothApi api,
    required Stream<DateTime> pollTicks,
  }) : _api = api {
    _tickSub = pollTicks.listen(_onTick);
  }

  final WebBluetoothApi _api;
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();
  late final StreamSubscription<DateTime> _tickSub;
  DateTime? _timestampOverride;
  bool _disposed = false;

  void _apply(ScannerEvent event) {
    final status = _machine.apply(event);
    if (!_disposed) {
      _statuses.add(status);
    }
  }

  /// Test-only injection: forces the timestamp of the next batch of polled
  /// observations instead of using the tick time. Production wiring always
  /// passes the tick time.
  void overrideNextTimestamp(DateTime t) => _timestampOverride = t;

  void onAdapterChanged(bool on) {
    if (!on && _machine.status == ScannerStatus.scanning) {
      _apply(ScannerEvent.adapterOff);
    } else if (on && _machine.status == ScannerStatus.unavailable) {
      _apply(ScannerEvent.adapterOn);
    }
  }

  /// Called by the permission plumbing when BLE permission is revoked
  /// mid-session (NFR-6).
  void onPermissionRevoked() {
    if (_machine.status != ScannerStatus.unauthorized) {
      _apply(ScannerEvent.permissionRevoked);
    }
  }

  /// Tier C manual-discovery entry point (FR-3): invokes the browser's
  /// device chooser. Must be called from a user gesture.
  Future<void> pairNewDevice() async {
    await _api.requestDevice();
  }

  Future<void> _onTick(DateTime now) async {
    if (_disposed || _machine.status != ScannerStatus.scanning) return;
    for (final id in _api.pairedDeviceIds) {
      final rssi = await _api.readRssi(id);
      if (_disposed) return;
      if (rssi == null) continue;
      final name = await _api.deviceName(id);
      if (_disposed) return;
      _observations.add(ScanObservation(
        deviceId: id,
        rssi: rssi,
        timestamp: _timestampOverride ?? now,
        advertisedName: name,
      ));
    }
    _timestampOverride = null;
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
    if (!_api.isSupported) {
      _apply(ScannerEvent.permissionRevoked); // surfaces unauthorized on Safari
      return;
    }
    _apply(ScannerEvent.start);
  }

  @override
  Future<void> stop() async {
    if (_machine.status == ScannerStatus.idle) return;
    _apply(ScannerEvent.stop);
  }

  /// Releases the tick subscription and closes the output streams. Not part
  /// of [BleScanner] — call when this scanner instance is being torn down
  /// for good (e.g. app shutdown), not between scans.
  Future<void> dispose() async {
    _disposed = true;
    await _tickSub.cancel();
    await _observations.close();
    await _statuses.close();
  }
}

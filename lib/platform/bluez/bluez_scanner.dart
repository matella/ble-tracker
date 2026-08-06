import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/scanner_state_machine.dart';
import '../../domain/types.dart';
import 'bluez_api.dart';

class BlueZScanner implements BleScanner {
  BlueZScanner(this._api) {
    _adapterSub = _api.adapterOn().listen(_onAdapterChanged);
    _resultsSub = _api.scanResults().listen(_observations.add);
  }

  final BlueZApi _api;
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();
  late final StreamSubscription<bool> _adapterSub;
  late final StreamSubscription<ScanObservation> _resultsSub;
  bool _disposed = false;

  // Serializes every state-mutating operation (start/stop/adapter
  // changes/permission revocation) so exactly one runs at a time and each
  // re-derives legality from fresh status once it's actually its turn. This
  // prevents overlapping async calls from racing past a status check that's
  // gone stale by the time their await resolves.
  Future<void> _serial = Future<void>.value();

  /// Serializes state-mutating operations. INVARIANT: a queued op must never
  /// call (and await) another _enqueue-wrapped method — that deadlocks the
  /// queue. Apply events inline instead (see start()'s permission handling).
  Future<void> _enqueue(Future<void> Function() op) {
    final next = _serial.then((_) => op());
    _serial = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  void _apply(ScannerEvent event) {
    final status = _machine.apply(event);
    if (!_disposed) {
      _statuses.add(status);
    }
  }

  Future<void> _onAdapterChanged(bool on) => _enqueue(() async {
    if (!on && _machine.status == ScannerStatus.scanning) {
      await _api.stopDiscovery();
      _apply(ScannerEvent.adapterOff);
    } else if (on && _machine.status == ScannerStatus.unavailable) {
      await _api.startDiscovery();
      _apply(ScannerEvent.adapterOn); // §5.4 auto-resume
    }
  });

  /// D-Bus policy denial maps here in the impl (NFR-6).
  void onPermissionRevoked() {
    _enqueue(() async {
      if (_machine.status != ScannerStatus.unauthorized) {
        _apply(ScannerEvent.permissionRevoked);
      }
    });
  }

  @override
  Stream<ScanObservation> observe() => _observations.stream;

  @override
  Stream<ScannerStatus> status() async* {
    yield _machine.status;
    yield* _statuses.stream;
  }

  @override
  Future<void> start(ScanProfile profile) => _enqueue(() async {
    if (_machine.status != ScannerStatus.idle) return;
    await _api.startDiscovery();
    _apply(ScannerEvent.start);
  });

  @override
  Future<void> stop() => _enqueue(() async {
    switch (_machine.status) {
      case ScannerStatus.scanning:
        await _api.stopDiscovery();
        _apply(ScannerEvent.stop);
      case ScannerStatus.unavailable:
        // BlueZ already stopped by adapter-off.
        _apply(ScannerEvent.stop);
      case ScannerStatus.idle:
      case ScannerStatus.unauthorized:
        return; // no-op
    }
  });

  /// Releases the underlying API stream subscriptions. Not part of
  /// [BleScanner] — call when this scanner instance is being torn down
  /// for good (e.g. app shutdown), not between scans.
  Future<void> dispose() async {
    _disposed = true;
    await _adapterSub.cancel();
    await _resultsSub.cancel();
    await _serial; // let any in-flight queued op finish first
    await _observations.close();
    await _statuses.close();
  }
}

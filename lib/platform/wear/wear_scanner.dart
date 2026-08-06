import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/types.dart';

/// Tier B wrapper: full delegate, but ambient (watch-face-visible) mode
/// downgrades to balanced scanning; leaving ambient restores the
/// requested profile (FR-19 / NFR-4).
class WearScanner implements BleScanner {
  WearScanner({required BleScanner inner, required Stream<bool> isAmbient})
      : _inner = inner {
    _ambientSub = isAmbient.listen(_onAmbient);
  }

  final BleScanner _inner;
  late final StreamSubscription<bool> _ambientSub;
  ScanProfile _requestedProfile = ScanProfile.balanced;
  bool _started = false;
  bool _ambient = false;

  Future<void> _onAmbient(bool ambient) async {
    _ambient = ambient;
    if (!_started) return;
    // The real inner scanner (FlutterBluePlusScanner) treats start() while
    // already scanning as a no-op that just records the requested profile —
    // it never re-issues the platform scan call. A stop()-then-start() is
    // required to actually apply the ambient-downgraded (or restored)
    // profile.
    await _inner.stop();
    await _inner.start(ambient ? ScanProfile.balanced : _requestedProfile);
  }

  @override
  Stream<ScanObservation> observe() => _inner.observe();

  @override
  Stream<ScannerStatus> status() => _inner.status();

  @override
  Future<void> start(ScanProfile profile) async {
    _requestedProfile = profile;
    _started = true;
    await _inner.start(_ambient ? ScanProfile.balanced : profile);
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _inner.stop();
  }

  /// Cancels the ambient subscription. The inner scanner has its own lifecycle
  /// — do NOT dispose it here.
  void dispose() {
    _ambientSub.cancel();
  }
}

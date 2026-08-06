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

  Future<void> _onAmbient(bool ambient) async {
    if (!_started) return;
    await _inner.start(
        ambient ? ScanProfile.balanced : _requestedProfile);
  }

  @override
  Stream<ScanObservation> observe() => _inner.observe();

  @override
  Stream<ScannerStatus> status() => _inner.status();

  @override
  Future<void> start(ScanProfile profile) async {
    _requestedProfile = profile;
    _started = true;
    await _inner.start(profile);
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

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/interfaces.dart';
import '../../domain/types.dart';

/// Tier B wrapper: full delegate, but ambient (watch-face-visible) mode
/// downgrades to balanced scanning; leaving ambient restores the
/// requested profile (FR-19 / NFR-4).
class WearScanner implements BleScanner {
  WearScanner({required BleScanner inner, required Stream<bool> isAmbient})
      : _inner = inner {
    _ambientSub = isAmbient.listen(_onAmbientEvent);
    _statusSub = _inner.status().listen((s) => _innerStatus = s);
  }

  final BleScanner _inner;
  late final StreamSubscription<bool> _ambientSub;
  late final StreamSubscription<ScannerStatus> _statusSub;
  ScannerStatus? _innerStatus;
  ScanProfile _requestedProfile = ScanProfile.balanced;
  bool _started = false;
  bool _ambient = false;
  // Ambient transitions can arrive while a previous stop()/start() pair is
  // still in flight. Chaining them keeps each pair atomic and in arrival
  // order, so a later transition cannot interleave with an earlier one.
  Future<void> _ambientChain = Future<void>.value();

  void _onAmbientEvent(bool ambient) {
    // Recorded immediately so a start() that lands during the chain still
    // picks up the latest ambient state.
    _ambient = ambient;
    _ambientChain = _ambientChain
        .then((_) => _applyAmbient())
        .catchError((Object error) => debugPrint('WearScanner: ambient: $error'));
  }

  Future<void> _applyAmbient() async {
    if (!_started) return;
    // Restarting an inner scanner that is unavailable or unauthorized is a
    // no-op at best; skip it and let the banner / recovery path handle it.
    final status = _innerStatus;
    if (status == ScannerStatus.unavailable ||
        status == ScannerStatus.unauthorized) {
      return;
    }
    // The real inner scanner (FlutterBluePlusScanner) treats start() while
    // already scanning as a no-op that just records the requested profile —
    // it never re-issues the platform scan call. A stop()-then-start() is
    // required to actually apply the ambient-downgraded (or restored)
    // profile.
    await _inner.stop();
    await _inner.start(_ambient ? ScanProfile.balanced : _requestedProfile);
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
    _statusSub.cancel();
  }
}

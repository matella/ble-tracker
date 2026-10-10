import 'package:flutter/services.dart';

import '../../domain/interfaces.dart';

/// Android foreground service for background scanning (FR-19, Tier A). Thin
/// and untested, like the other platform wrappers: the start/stop rules are
/// covered by the app shell's tests, and the service by the manual checklist.
class AndroidBackgroundScanHost implements BackgroundScanHost {
  static const _channel = MethodChannel('ble_tracker/background');

  @override
  Future<void> setActive(bool active) =>
      _channel.invokeMethod<void>(active ? 'start' : 'stop');
}

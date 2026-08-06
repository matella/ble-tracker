import 'types.dart';

enum ScannerEvent {
  start,
  stop,
  adapterOff,
  adapterOn,
  permissionRevoked,
  permissionGranted,
}

class IllegalTransitionError extends StateError {
  IllegalTransitionError(ScannerStatus from, ScannerEvent event)
      : super('Illegal scanner transition: $from + $event');
}

/// §5.4 transitions, exactly. Everything not in the table throws.
class ScannerStateMachine {
  ScannerStatus _status = ScannerStatus.idle;

  ScannerStatus get status => _status;

  ScannerStatus apply(ScannerEvent event) {
    _status = switch ((_status, event)) {
      (_, ScannerEvent.permissionRevoked) => ScannerStatus.unauthorized,
      (ScannerStatus.idle, ScannerEvent.start) => ScannerStatus.scanning,
      (ScannerStatus.idle, ScannerEvent.stop) => ScannerStatus.idle,
      (ScannerStatus.scanning, ScannerEvent.stop) => ScannerStatus.idle,
      (ScannerStatus.scanning, ScannerEvent.adapterOff) =>
        ScannerStatus.unavailable,
      (ScannerStatus.unavailable, ScannerEvent.adapterOn) =>
        ScannerStatus.scanning,
      (ScannerStatus.unavailable, ScannerEvent.stop) => ScannerStatus.idle,
      (ScannerStatus.unauthorized, ScannerEvent.permissionGranted) =>
        ScannerStatus.idle,
      _ => throw IllegalTransitionError(_status, event),
    };
    return _status;
  }
}

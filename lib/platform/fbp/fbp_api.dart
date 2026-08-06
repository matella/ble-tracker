import '../../domain/types.dart';

/// Everything FlutterBluePlusScanner needs from flutter_blue_plus,
/// as plain Dart so tests can fake it.
abstract interface class FbpApi {
  /// Adapter state: true = on, false = off.
  Stream<bool> adapterOn();

  /// Raw advertisement results already mapped to ScanObservation.
  Stream<ScanObservation> scanResults();

  /// Throws [FbpPermissionDenied] if BLE permissions are missing/revoked.
  Future<void> startScan({required bool lowLatency});

  Future<void> stopScan();
}

class FbpPermissionDenied implements Exception {}

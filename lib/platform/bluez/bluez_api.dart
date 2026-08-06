import '../../domain/types.dart';

/// Everything BlueZScanner needs from the bluez D-Bus interface,
/// as plain Dart so tests can fake it.
abstract interface class BlueZApi {
  /// Adapter state: true = on, false = off.
  Stream<bool> adapterOn();

  /// Raw advertisement results already mapped to ScanObservation.
  Stream<ScanObservation> scanResults();

  Future<void> startDiscovery();

  Future<void> stopDiscovery();
}

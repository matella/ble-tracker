import '../domain/interfaces.dart';
import '../domain/types.dart';

/// Degraded-mode scanner used when the real platform scanner fails to
/// initialize (e.g. BlueZ/D-Bus unreachable on Linux). Surfaces a permanent
/// `unavailable` status so the UI shows its recoverable banner (NFR-6)
/// instead of the app crashing at bootstrap.
class UnavailableBleScanner implements BleScanner {
  @override
  Stream<ScanObservation> observe() => const Stream.empty();

  @override
  Stream<ScannerStatus> status() =>
      Stream.value(ScannerStatus.unavailable);

  @override
  Future<void> start(ScanProfile profile) async {}

  @override
  Future<void> stop() async {}
}

import 'types.dart';

/// Emits raw scan observations. Implemented per platform tier.
abstract interface class BleScanner {
  Stream<ScanObservation> observe(); // never errors; state via ScannerStatus
  Stream<ScannerStatus> status(); // idle / scanning / unavailable / unauthorized
  Future<void> start(ScanProfile profile); // profile: lowLatency | balanced
  Future<void> stop();
}

/// Pure function boundary — fully unit-testable, no I/O.
abstract interface class RssiSmoother {
  double next(String deviceId, double rawRssi, DateTime at);
  void reset(String deviceId);
}

abstract interface class DistanceEstimator {
  DistanceEstimate estimate({
    required double smoothedRssi,
    required double txPower,
    required double environmentFactor,
  });
}

abstract interface class DeviceRegistry {
  Stream<List<RegisteredDevice>> watchAll();
  Future<void> register(RegisteredDevice device);
  Future<void> setTracking(String deviceId, bool enabled);
  Future<void> rename(String deviceId, String name);
  Future<void> remove(String deviceId);
}

abstract interface class RadarLayout {
  /// Deterministic: same id → same angle, always.
  double angleFor(String deviceId);

  /// Log-scaled radial position in [0, 1] from distance + band config.
  double radiusFor(DistanceEstimate estimate);
}

abstract interface class PlatformCapabilities {
  CapabilityTier get tier; // tierA | tierB | tierC
  bool get supportsAutoDiscovery;
  bool get supportsBackgroundScan;
}

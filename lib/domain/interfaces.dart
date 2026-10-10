import 'types.dart';

/// Emits raw scan observations. Implemented per platform tier.
abstract interface class BleScanner {
  Stream<ScanObservation> observe(); // never errors; state via ScannerStatus
  Stream<ScannerStatus>
  status(); // idle / scanning / unavailable / unauthorized
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

  /// Sets the device's reference RSSI at 1 m, or clears it with null (OQ-3).
  Future<void> setCalibration(String deviceId, double? rssiAt1m);
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

/// Keeps scanning alive while the app is in the background (FR-19, Tier A).
/// Only Android has a real implementation (a foreground service); elsewhere
/// the no-op applies, because desktop keeps scanning when minimised.
abstract interface class BackgroundScanHost {
  Future<void> setActive(bool active);
}

class NoopBackgroundScanHost implements BackgroundScanHost {
  const NoopBackgroundScanHost();

  @override
  Future<void> setActive(bool active) async {}
}

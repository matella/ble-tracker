/// All tunable constants (FR-9, FR-10, FR-11, FR-12). Injected everywhere —
/// never hard-code these values at use sites.
class ProximityConfig {
  ProximityConfig({
    this.processNoise = 0.065,
    this.measurementNoise = 1.4,
    this.environmentFactor = 2.7,
    this.defaultTxPower = -59.0,
    this.immediateMaxMeters = 0.5,
    this.nearMaxMeters = 3.0,
    this.midMaxMeters = 10.0,
    this.staleAfter = const Duration(seconds: 10),
    this.blipFadeOut = const Duration(seconds: 2),
    this.radarMinMeters = 0.1,
    this.radarMaxMeters = 20.0,
  }) {
    if (environmentFactor < 2.0 || environmentFactor > 4.0) {
      throw ArgumentError.value(
        environmentFactor, 'environmentFactor', 'must be in [2.0, 4.0]');
    }
  }

  final double processNoise;
  final double measurementNoise;
  final double environmentFactor;
  final double defaultTxPower;
  final double immediateMaxMeters;
  final double nearMaxMeters;
  final double midMaxMeters;
  final Duration staleAfter;
  final Duration blipFadeOut;
  final double radarMinMeters;
  final double radarMaxMeters;
}

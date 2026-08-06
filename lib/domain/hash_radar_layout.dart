import 'dart:math' as math;

import 'config.dart';
import 'interfaces.dart';
import 'types.dart';

/// FR-15: stable pseudo-angle from FNV-1a hash of the device id — no
/// directional meaning. FR-14: log-scaled radius in [0, 1].
class HashRadarLayout implements RadarLayout {
  HashRadarLayout(this._config);

  final ProximityConfig _config;

  @override
  double angleFor(String deviceId) {
    // FNV-1a 64-bit hash for better distribution across sequential ids.
    // offset basis: 0xcbf29ce484222325, prime: 0x100000001b3
    var hash = 0xcbf29ce484222325;
    for (final unit in deviceId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3).toUnsigned(64);
    }
    // Normalize 64-bit hash to [0, 2π) using 53-bit mask (safe integer range in double).
    // Mask to 53 bits and divide by 2^53 to get [0, 1).
    return (hash & 0x1FFFFFFFFFFFFF) / 0x20000000000000 * 2 * math.pi;
  }

  @override
  double radiusFor(DistanceEstimate estimate) {
    final min = _config.radarMinMeters;
    final max = _config.radarMaxMeters;
    final d = estimate.meters.clamp(min, max);
    return math.log(d / min) / math.log(max / min);
  }
}

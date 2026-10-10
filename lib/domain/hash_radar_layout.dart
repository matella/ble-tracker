import 'dart:math' as math;

import 'config.dart';
import 'interfaces.dart';
import 'types.dart';

/// FR-15: stable pseudo-angle from FNV-1a hash of the device id — no
/// directional meaning. FR-14: log-scaled radius in [0, 1].
class HashRadarLayout implements RadarLayout {
  HashRadarLayout(this._config);

  /// FNV-1a 32-bit offset basis and prime.
  ///
  /// 32-bit, not 64-bit: on web an `int` is a JS double, so 64-bit constants
  /// and products are not representable and would silently diverge from the
  /// native result. Every intermediate below stays under 2^53 and every
  /// bitwise operand stays inside 32 bits, which makes the hash — and so the
  /// radar layout — identical on every platform.
  static const _offsetBasis = 0x811c9dc5;
  static const _prime = 0x01000193;

  final ProximityConfig _config;

  @override
  double angleFor(String deviceId) {
    var hash = _offsetBasis;
    for (final unit in deviceId.codeUnits) {
      hash = _mul32(hash ^ unit, _prime);
    }
    // FNV-1a alone leaves the high bits of sequential ids clustered: the final
    // code unit only reaches them through a single multiply, so `device-0` and
    // `device-1` share an angular sector. Finalize with murmur3's fmix32 to
    // avalanche every bit before the top ones pick the angle.
    hash ^= hash >> 16;
    hash = _mul32(hash, 0x85ebca6b);
    hash ^= hash >> 13;
    hash = _mul32(hash, 0xc2b2ae35);
    hash ^= hash >> 16;
    // Normalize the 32-bit hash to [0, 2π).
    return hash / 0x100000000 * 2 * math.pi;
  }

  /// `a * b` modulo 2^32, with `a` split into 16-bit halves so no intermediate
  /// product exceeds 2^48 — a JS double holds integers exactly only to 2^53.
  static int _mul32(int a, int b) {
    final lo = (a % 0x10000) * b;
    final hi = (a ~/ 0x10000) * b;
    return (lo + (hi % 0x10000) * 0x10000) % 0x100000000;
  }

  @override
  double radiusFor(DistanceEstimate estimate) {
    final min = _config.radarMinMeters;
    final max = _config.radarMaxMeters;
    final d = estimate.meters.clamp(min, max);
    return math.log(d / min) / math.log(max / min);
  }
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'interfaces.dart';
import 'types.dart';

/// TxPower from advertisement when present, else per-config default (FR-9).
double resolveTxPower(double? advertised, ProximityConfig config) =>
    advertised ?? config.defaultTxPower;

/// Log-distance path loss model (FR-9): d = 10^((TxPower − RSSI) / (10·n)).
class LogDistanceEstimator implements DistanceEstimator {
  LogDistanceEstimator(this._config);

  final ProximityConfig _config;

  @override
  DistanceEstimate estimate({
    required double smoothedRssi,
    required double txPower,
    required double environmentFactor,
  }) {
    final meters = math
        .pow(10, (txPower - smoothedRssi) / (10 * environmentFactor))
        .toDouble();
    return DistanceEstimate(meters: meters, band: bandForMeters(meters));
  }

  @visibleForTesting
  ProximityBand bandForMeters(double meters) {
    if (meters < _config.immediateMaxMeters) return ProximityBand.immediate;
    if (meters < _config.nearMaxMeters) return ProximityBand.near;
    if (meters <= _config.midMaxMeters) return ProximityBand.mid;
    return ProximityBand.far;
  }
}

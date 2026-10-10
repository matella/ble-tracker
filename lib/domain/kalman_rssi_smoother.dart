import 'interfaces.dart';

class _KalmanState {
  _KalmanState({required this.estimate, required this.errorCovariance});
  double estimate;
  double errorCovariance;
}

/// 1-D Kalman filter per device (FR-10). Q and R are injected (never
/// hard-coded) so tests and settings control them.
class KalmanRssiSmoother implements RssiSmoother {
  KalmanRssiSmoother({
    required this.processNoise,
    required this.measurementNoise,
  }) {
    // Zero or negative variances make the gain degenerate (division by a
    // non-positive sum) and silently produce NaN estimates.
    if (processNoise <= 0) {
      throw ArgumentError.value(processNoise, 'processNoise', 'must be > 0');
    }
    if (measurementNoise <= 0) {
      throw ArgumentError.value(
          measurementNoise, 'measurementNoise', 'must be > 0');
    }
  }

  final double processNoise;
  final double measurementNoise;
  final Map<String, _KalmanState> _states = {};

  /// [at] is part of the [RssiSmoother] contract but unused here: process
  /// noise is applied per observation, not per second. Scaling it by the
  /// elapsed time was considered and not adopted, because the default
  /// [processNoise] was tuned per observation and would silently change
  /// every estimate.
  @override
  double next(String deviceId, double rawRssi, DateTime at) {
    final state = _states[deviceId];
    if (state == null) {
      _states[deviceId] =
          _KalmanState(estimate: rawRssi, errorCovariance: measurementNoise);
      return rawRssi;
    }
    final predicted = state.errorCovariance + processNoise;
    final gain = predicted / (predicted + measurementNoise);
    state.estimate = state.estimate + gain * (rawRssi - state.estimate);
    state.errorCovariance = (1 - gain) * predicted;
    return state.estimate;
  }

  @override
  void reset(String deviceId) => _states.remove(deviceId);
}

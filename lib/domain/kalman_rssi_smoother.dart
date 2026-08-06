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
  });

  final double processNoise;
  final double measurementNoise;
  final Map<String, _KalmanState> _states = {};

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

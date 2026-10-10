/// Turns a run of raw RSSI readings taken at a known 1 m distance into the
/// device's reference RSSI at 1 m (spec OQ-3). Time comes from the observation
/// timestamps, never the wall clock, so the logic is deterministic in tests.
///
/// A single reading cannot give the path-loss exponent (the log term is zero
/// at 1 m); the average is the device's reference power instead.
class RssiCalibrationSession {
  RssiCalibrationSession({
    this.window = const Duration(seconds: 5),
    this.minSamples = 10,
  });

  /// How long readings must span before the average is trusted.
  final Duration window;

  /// Fewer readings than this are too noisy to average.
  final int minSamples;

  DateTime? _first;
  DateTime? _last;
  final _samples = <double>[];

  int get sampleCount => _samples.length;

  /// Feeds one raw reading. [at] is the observation timestamp.
  void add(double rssi, DateTime at) {
    _first ??= at;
    _last = at;
    _samples.add(rssi);
  }

  /// The mean reference RSSI once the window has elapsed with enough samples,
  /// otherwise null.
  double? get result {
    final first = _first;
    final last = _last;
    if (first == null || last == null) return null;
    if (last.difference(first) < window) return null;
    if (_samples.length < minSamples) return null;
    return _samples.reduce((a, b) => a + b) / _samples.length;
  }

  /// Whether a reference RSSI at 1 m is physically plausible. Outside this
  /// range the reading is almost certainly a mis-stand, not a measurement.
  static bool isPlausibleReference(double rssiAt1m) =>
      rssiAt1m >= -100 && rssiAt1m <= -20;
}

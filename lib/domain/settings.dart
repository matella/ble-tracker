/// User-tunable settings (FR-9). Pure: no Flutter, no I/O. Persistence goes
/// through [KeyValueStore] at the state layer.
library;

/// Storage key for the environment factor `n`.
const environmentFactorStorageKey = 'settings.environmentFactor.v1';

/// Valid range for the path-loss exponent `n` (FR-9).
const environmentFactorMin = 2.0;
const environmentFactorMax = 4.0;

/// Default `n` (free space ≈ 2.0, typical indoor ≈ 2.7–3.0).
const defaultEnvironmentFactor = 2.7;

/// Parses a stored environment factor. A missing, unparseable, non-finite or
/// out-of-range value falls back to [defaultEnvironmentFactor], the same way
/// the registry treats a corrupt store: the app must still start.
double parseEnvironmentFactor(String? raw) {
  final value = double.tryParse(raw ?? '');
  if (value == null ||
      !value.isFinite ||
      value < environmentFactorMin ||
      value > environmentFactorMax) {
    return defaultEnvironmentFactor;
  }
  return value;
}

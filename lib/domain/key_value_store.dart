/// Persistence boundary (OQ-1: shared_preferences now; interface makes
/// swapping to drift trivial later).
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

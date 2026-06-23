/// A pluggable read-through cache for raw PocketBase record maps.
///
/// The repository layer (FED-2.6) writes successful reads here and falls back
/// to them when the network is unreachable, so previously-viewed data stays
/// readable offline. It is defined in the (Flutter-free) data package as an
/// interface; the app supplies a persistent implementation (shared_preferences)
/// and tests an in-memory one.
///
/// Records are stored as their raw JSON maps (`RecordModel.toJson()`) keyed by
/// collection + id, so they rehydrate through the same `fromRecord` mappers the
/// live path uses. List results are stored by an opaque query key.
abstract interface class RecordCache {
  /// Stores a single [record] under (`collection`, `id`).
  Future<void> putRecord(
    String collection,
    String id,
    Map<String, dynamic> record,
  );

  /// Reads the cached record for (`collection`, `id`), or `null`.
  Future<Map<String, dynamic>?> getRecord(String collection, String id);

  /// Stores a list result for [collection] under the opaque [queryKey].
  Future<void> putList(
    String collection,
    String queryKey,
    List<Map<String, dynamic>> records,
  );

  /// Reads a cached list result, or `null` if not cached.
  Future<List<Map<String, dynamic>>?> getList(
    String collection,
    String queryKey,
  );

  /// Removes a single cached record.
  Future<void> evictRecord(String collection, String id);

  /// Drops all cached list results for [collection] (e.g. after a write, so a
  /// later offline read never serves a list missing the change).
  Future<void> evictLists(String collection);

  /// Clears the entire cache (e.g. on sign-out / server switch).
  Future<void> clear();
}

/// A [RecordCache] that stores nothing — the default when caching is disabled.
class NoopRecordCache implements RecordCache {
  const NoopRecordCache();

  @override
  Future<void> putRecord(String c, String id, Map<String, dynamic> r) async {}

  @override
  Future<Map<String, dynamic>?> getRecord(String c, String id) async => null;

  @override
  Future<void> putList(
    String c,
    String k,
    List<Map<String, dynamic>> r,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>?> getList(String c, String k) async => null;

  @override
  Future<void> evictRecord(String c, String id) async {}

  @override
  Future<void> evictLists(String c) async {}

  @override
  Future<void> clear() async {}
}

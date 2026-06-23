import 'dart:convert';

import 'package:federfall_data/federfall_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A persistent [RecordCache] backed by `shared_preferences`.
///
/// The whole cache lives in a single JSON blob under one key, shaped as
/// `{records: {collection: {id: record}}, lists: {collection: {key: [..]}}}`.
/// To stay "light" (FED-2.6) it is bounded per collection: at most
/// [maxRecordsPerCollection] records (oldest dropped first) and
/// [maxListsPerCollection] list results. It is a best-effort cache — any
/// decode/encode error is swallowed so caching never breaks a real request.
class PrefsRecordCache implements RecordCache {
  PrefsRecordCache({
    this.maxRecordsPerCollection = 100,
    this.maxListsPerCollection = 20,
  });

  static const _key = 'federfall.cache.v1';

  /// Max single records retained per collection (insertion-ordered LRU).
  final int maxRecordsPerCollection;

  /// Max distinct list results retained per collection.
  final int maxListsPerCollection;

  @override
  Future<void> putRecord(
    String collection,
    String id,
    Map<String, dynamic> record,
  ) async {
    await _mutate((root) {
      final records = _bucket(root, 'records', collection)
        // Re-insert at the end so it counts as most-recently-used.
        ..remove(id);
      records[id] = record;
      _trim(records, maxRecordsPerCollection);
    });
  }

  @override
  Future<Map<String, dynamic>?> getRecord(String collection, String id) async {
    final root = await _read();
    final value = _bucket(root, 'records', collection)[id];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Future<void> putList(
    String collection,
    String queryKey,
    List<Map<String, dynamic>> records,
  ) async {
    await _mutate((root) {
      final lists = _bucket(root, 'lists', collection)..remove(queryKey);
      lists[queryKey] = records;
      _trim(lists, maxListsPerCollection);
    });
  }

  @override
  Future<List<Map<String, dynamic>>?> getList(
    String collection,
    String queryKey,
  ) async {
    final root = await _read();
    final value = _bucket(root, 'lists', collection)[queryKey];
    if (value is! List) return null;
    return value
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  Future<void> evictRecord(String collection, String id) async {
    await _mutate((root) => _bucket(root, 'records', collection).remove(id));
  }

  @override
  Future<void> evictLists(String collection) async {
    await _mutate((root) => (root['lists'] as Map?)?.remove(collection));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // ── internals ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _mutate(void Function(Map<String, dynamic> root) change) async {
    final prefs = await SharedPreferences.getInstance();
    final root = await _read();
    change(root);
    await prefs.setString(_key, jsonEncode(root));
  }

  /// Returns the `root[section][collection]` map, creating empties as needed.
  Map<String, dynamic> _bucket(
    Map<String, dynamic> root,
    String section,
    String collection,
  ) {
    final sec = (root[section] as Map?)?.cast<String, dynamic>() ?? {};
    root[section] = sec;
    final col = (sec[collection] as Map?)?.cast<String, dynamic>() ?? {};
    sec[collection] = col;
    return col;
  }

  /// Drops oldest entries (insertion order) until [map] fits [max].
  void _trim(Map<String, dynamic> map, int max) {
    while (map.length > max) {
      map.remove(map.keys.first);
    }
  }
}

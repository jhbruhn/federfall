import 'dart:async';

import 'package:federfall_data/src/record_cache.dart';
import 'package:federfall_data/src/repository_exception.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// Read/write contract every collection repository exposes. Generic over the
/// mapped domain model [T]. Concrete query helpers live on the typed
/// subclasses; this is the shared surface the offline cache (FED-2.6) and tests
/// depend on.
abstract interface class Repository<T> {
  /// Fetches a single record by id, optionally expanding relations.
  Future<T> getOne(String id, {String? expand});

  /// Fetches all matching records (auto-paginated).
  Future<List<T>> list({String? filter, String? sort, String? expand});

  /// Creates a record from a field [body] and returns the mapped result.
  Future<T> create(Map<String, dynamic> body);

  /// Updates a record by id and returns the mapped result.
  Future<T> update(String id, Map<String, dynamic> body);

  /// Deletes a record by id.
  Future<void> delete(String id);
}

/// PocketBase-backed [Repository] base. Wraps a single collection's CRUD,
/// maps every [RecordModel] through [fromRecord], and funnels SDK errors
/// through [RepositoryException].
///
/// Reads are cached through the injected [RecordCache] (FED-2.6): every
/// successful [getOne] / [list] is written to the cache, and when a read fails
/// with a *network* error the cached copy is served instead of throwing — so
/// any previously-seen data stays readable offline. Writes always go to the
/// server (they require connectivity) and refresh/evict the relevant cache
/// entries. The default [NoopRecordCache] makes caching opt-in per repository.
abstract class PbRepository<T> implements Repository<T> {
  PbRepository({
    required this.pb,
    required this.collection,
    required this.fromRecord,
    this.cache = const NoopRecordCache(),
    this.networkTimeout = const Duration(seconds: 5),
    this.isOffline,
  });

  /// The PocketBase client.
  final PocketBase pb;

  /// The collection name this repository owns.
  final String collection;

  /// Maps a raw record to the domain model.
  final T Function(RecordModel) fromRecord;

  /// The read-through cache backing offline reads (FED-2.6).
  final RecordCache cache;

  /// How long a single request may run before it is treated as a connectivity
  /// failure. Without this, a reachable network but unreachable server hangs on
  /// the OS TCP timeout (minutes) instead of falling back to the cache.
  final Duration networkTimeout;

  /// Optional snapshot of whether the app already knows it is offline. When it
  /// returns true, reads skip the network and serve the cache immediately, and
  /// writes fail fast — so a known-down server never makes the UI wait.
  final bool Function()? isOffline;

  bool get _knownOffline => isOffline?.call() ?? false;

  RepositoryException get _offlineException => const RepositoryException(
    'Could not reach the server',
    kind: RepositoryErrorKind.network,
  );

  RecordService get service => pb.collection(collection);

  /// Builds a safe filter expression with bound [params]
  /// (e.g. `filterExpr('case = {:c}', {'c': id})`).
  String filterExpr(String expr, [Map<String, dynamic> params = const {}]) =>
      pb.filter(expr, params);

  @override
  Future<T> getOne(String id, {String? expand}) async {
    if (_knownOffline) return _cachedRecord(id);
    try {
      final record = await service
          .getOne(id, expand: expand)
          .timeout(networkTimeout);
      await cache.putRecord(collection, id, record.toJson());
      return fromRecord(record);
    } on TimeoutException {
      return _cachedRecord(id);
    } on ClientException catch (e) {
      final failure = RepositoryException.fromClient(e);
      if (failure.isNetwork) {
        final cached = await cache.getRecord(collection, id);
        if (cached != null) return fromRecord(RecordModel(cached));
      }
      throw failure;
    }
  }

  @override
  Future<List<T>> list({String? filter, String? sort, String? expand}) async {
    final key = _listKey(filter, sort, expand);
    if (_knownOffline) return _cachedList(key);
    try {
      final items = await service
          .getFullList(filter: filter, sort: sort, expand: expand)
          .timeout(networkTimeout);
      await cache.putList(
        collection,
        key,
        items.map((r) => r.toJson()).toList(),
      );
      return items.map(fromRecord).toList();
    } on TimeoutException {
      return _cachedList(key);
    } on ClientException catch (e) {
      final failure = RepositoryException.fromClient(e);
      if (failure.isNetwork) {
        final cached = await cache.getList(collection, key);
        if (cached != null) {
          return cached.map((m) => fromRecord(RecordModel(m))).toList();
        }
      }
      throw failure;
    }
  }

  /// Serves a single cached record, or throws an offline error on a miss.
  Future<T> _cachedRecord(String id) async {
    final cached = await cache.getRecord(collection, id);
    if (cached != null) return fromRecord(RecordModel(cached));
    throw _offlineException;
  }

  /// Serves a cached list result, or throws an offline error on a miss.
  Future<List<T>> _cachedList(String key) async {
    final cached = await cache.getList(collection, key);
    if (cached != null) {
      return cached.map((m) => fromRecord(RecordModel(m))).toList();
    }
    throw _offlineException;
  }

  /// Returns the first record matching [filter], or `null` if none.
  Future<T?> firstWhere(String filter, {String? expand}) {
    return _guard(() async {
      try {
        final r = await service.getFirstListItem(filter, expand: expand);
        return fromRecord(r);
      } on ClientException catch (e) {
        if (e.statusCode == 404) return null;
        rethrow;
      }
    });
  }

  @override
  Future<T> create(Map<String, dynamic> body) {
    return _guard(() async {
      final record = await service.create(body: body);
      await cache.putRecord(collection, record.id, record.toJson());
      await cache.evictLists(collection);
      return fromRecord(record);
    });
  }

  /// Creates a record from [body] with multipart [files] attached to its file
  /// field(s). Each [http.MultipartFile.field] names the target file field
  /// (e.g. `attachments`); repeat the field name to upload several files to a
  /// multi-file field. Like [create], the new record is cached and the
  /// collection's cached lists are evicted.
  Future<T> createWithFiles(
    Map<String, dynamic> body,
    List<http.MultipartFile> files,
  ) {
    return _guard(() async {
      final record = await service.create(body: body, files: files);
      await cache.putRecord(collection, record.id, record.toJson());
      await cache.evictLists(collection);
      return fromRecord(record);
    });
  }

  /// Updates record [id] from [body] with new multipart [files] appended to its
  /// file field(s). To keep only some of the existing files, set the field to
  /// the surviving filenames in [body] (e.g. `{'attachments': ['a.jpg']}`);
  /// PocketBase then appends the uploads on top of that list.
  Future<T> updateWithFiles(
    String id,
    Map<String, dynamic> body,
    List<http.MultipartFile> files,
  ) {
    return _guard(() async {
      final record = await service.update(id, body: body, files: files);
      await cache.putRecord(collection, id, record.toJson());
      await cache.evictLists(collection);
      return fromRecord(record);
    });
  }

  /// Absolute URL for a [filename] stored on record [recordId]'s file field.
  /// Pass [thumb] (e.g. `100x100`) for a server-generated thumbnail. The file
  /// field is unprotected, so the URL is usable without an auth token.
  Uri fileUrl(String recordId, String filename, {String? thumb}) => pb.buildURL(
    '/api/files/$collection/$recordId/$filename',
    thumb == null ? const {} : {'thumb': thumb},
  );

  @override
  Future<T> update(String id, Map<String, dynamic> body) {
    return _guard(() async {
      final record = await service.update(id, body: body);
      await cache.putRecord(collection, id, record.toJson());
      await cache.evictLists(collection);
      return fromRecord(record);
    });
  }

  @override
  Future<void> delete(String id) {
    return _guard(() async {
      await service.delete(id);
      await cache.evictRecord(collection, id);
      await cache.evictLists(collection);
    });
  }

  /// Opaque cache key for a list query (collection-scoped).
  String _listKey(String? filter, String? sort, String? expand) =>
      '${filter ?? ''}|${sort ?? ''}|${expand ?? ''}';

  /// Runs a network [op] (writes, `firstWhere`), translating failures to
  /// [RepositoryException]. Fails fast when the app already knows it is
  /// offline, and caps the op at [networkTimeout] so a dead server never hangs.
  Future<R> _guard<R>(Future<R> Function() op) async {
    if (_knownOffline) throw _offlineException;
    try {
      return await op().timeout(networkTimeout);
    } on TimeoutException {
      throw _offlineException;
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }
}

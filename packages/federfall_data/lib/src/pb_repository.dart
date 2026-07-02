import 'dart:async';

import 'package:federfall_data/src/repository_exception.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// Read/write contract every collection repository exposes. Generic over the
/// mapped domain model [T]. Concrete query helpers live on the typed
/// subclasses; this is the shared surface screens and tests depend on.
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
/// This app is online-only: every read and write goes straight to the server,
/// there is no local cache. A [networkTimeout] caps each request so an
/// unreachable server fails fast with a network error instead of hanging.
abstract class PbRepository<T> implements Repository<T> {
  PbRepository({
    required this.pb,
    required this.collection,
    required this.fromRecord,
    this.networkTimeout = const Duration(seconds: 15),
  });

  /// The PocketBase client.
  final PocketBase pb;

  /// The collection name this repository owns.
  final String collection;

  /// Maps a raw record to the domain model.
  final T Function(RecordModel) fromRecord;

  /// Caps a single request so an unreachable server fails fast with a network
  /// error instead of hanging on the OS TCP timeout (minutes).
  final Duration networkTimeout;

  RecordService get service => pb.collection(collection);

  /// Builds a safe filter expression with bound [params]
  /// (e.g. `filterExpr('case = {:c}', {'c': id})`).
  String filterExpr(String expr, [Map<String, dynamic> params = const {}]) =>
      pb.filter(expr, params);

  @override
  Future<T> getOne(String id, {String? expand}) =>
      _guard(() async => fromRecord(await service.getOne(id, expand: expand)));

  @override
  Future<List<T>> list({String? filter, String? sort, String? expand}) {
    return _guard(() async {
      final items = await service.getFullList(
        filter: filter,
        sort: sort,
        expand: expand,
      );
      return items.map(fromRecord).toList();
    });
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
  Future<T> create(Map<String, dynamic> body) =>
      _guard(() async => fromRecord(await service.create(body: body)));

  /// Creates a record from [body] with multipart [files] attached to its file
  /// field(s). Each [http.MultipartFile.field] names the target file field
  /// (e.g. `attachments`); repeat the field name to upload several files to a
  /// multi-file field.
  Future<T> createWithFiles(
    Map<String, dynamic> body,
    List<http.MultipartFile> files,
  ) =>
      _guard(
        () async => fromRecord(await service.create(body: body, files: files)),
      );

  /// Updates record [id] from [body] with new multipart [files] appended to its
  /// file field(s). To keep only some of the existing files, set the field to
  /// the surviving filenames in [body] (e.g. `{'attachments': ['a.jpg']}`);
  /// PocketBase then appends the uploads on top of that list.
  Future<T> updateWithFiles(
    String id,
    Map<String, dynamic> body,
    List<http.MultipartFile> files,
  ) =>
      _guard(
        () async =>
            fromRecord(await service.update(id, body: body, files: files)),
      );

  /// Absolute URL for a [filename] stored on record [recordId]'s file field.
  /// Pass [thumb] (e.g. `100x100`) for a server-generated thumbnail.
  ///
  /// The clinical/finder-linked image fields are **Protected** (FED-8.1), so
  /// their URLs are only served with a short-lived file [token]
  /// (`pb.files.getToken()`, ~2min TTL) issued for an auth model that can read
  /// the owning record. Pass that token here for protected fields; omit it for
  /// genuinely public assets. This mirrors `pb.files.getURL(token:)` but builds
  /// the path from [recordId]/[filename] directly (we hold those, not a fetched
  /// [RecordModel]).
  Uri fileUrl(
    String recordId,
    String filename, {
    String? thumb,
    String? token,
  }) => pb.buildURL('/api/files/$collection/$recordId/$filename', {
    'thumb': ?thumb,
    'token': ?token,
  });

  @override
  Future<T> update(String id, Map<String, dynamic> body) =>
      _guard(() async => fromRecord(await service.update(id, body: body)));

  @override
  Future<void> delete(String id) =>
      _guard(() async => service.delete(id));

  /// Runs a server [op], capping it at [networkTimeout] and translating SDK
  /// failures into a stable [RepositoryException].
  Future<R> _guard<R>(Future<R> Function() op) async {
    try {
      return await op().timeout(networkTimeout);
    } on TimeoutException {
      throw const RepositoryException(
        'Could not reach the server',
        kind: RepositoryErrorKind.network,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    } on RepositoryException {
      rethrow;
    } on Object catch (e) {
      // Last resort: a mapper (fromRecord) choking on a malformed record must
      // still surface as the stable exception the UI error states depend on.
      throw RepositoryException('Unexpected repository failure: $e', cause: e);
    }
  }
}

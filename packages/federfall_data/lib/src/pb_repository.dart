import 'dart:async';

import 'package:federfall_data/src/repository_exception.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// Read-only contract of a collection repository. View-backed repositories
/// implement only this, so a create/update/delete against a PocketBase view
/// is a compile error instead of a runtime 400.
abstract interface class ReadOnlyRepository<T> {
  /// Fetches a single record by id, optionally expanding relations.
  Future<T> getOne(String id, {String? expand});

  /// Fetches all matching records (auto-paginated).
  Future<List<T>> list({PbFilter? filter, String? sort, String? expand});
}

/// Read/write contract every mutable collection repository exposes. Generic
/// over the mapped domain model [T]. Concrete query helpers live on the typed
/// subclasses; this is the shared surface screens and tests depend on.
abstract interface class Repository<T> implements ReadOnlyRepository<T> {
  /// Creates a record from a field [body] and returns the mapped result.
  Future<T> create(Map<String, dynamic> body);

  /// Updates a record by id and returns the mapped result.
  Future<T> update(String id, Map<String, dynamic> body);

  /// Deletes a record by id.
  Future<void> delete(String id);
}

/// A filter expression whose parameters have already been bound (escaped).
///
/// The query surface only accepts this type, and the only way to obtain one
/// is [PbReadOnlyRepository.filterExpr] — so interpolating user input into a
/// raw filter string (the classic filter injection) is a compile error, not
/// a latent hole.
class PbFilter {
  const PbFilter._(this.expression);

  /// The bound PocketBase filter expression.
  final String expression;

  @override
  String toString() => expression;
}

/// PocketBase-backed [ReadOnlyRepository] base. Wraps a single collection's
/// reads, maps every [RecordModel] through [fromRecord], and funnels SDK
/// errors through [RepositoryException]. Mutable collections use the
/// [PbRepository] subclass; PocketBase views stop here.
///
/// This app is online-only: every read and write goes straight to the server,
/// there is no local cache. A [networkTimeout] caps each request so an
/// unreachable server fails fast with a network error instead of hanging.
abstract class PbReadOnlyRepository<T> implements ReadOnlyRepository<T> {
  PbReadOnlyRepository({
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

  /// Page size for [list] — the PocketBase server-side maximum, so a small
  /// result set still needs only one round trip.
  static const int _listPageSize = 500;

  RecordService get service => pb.collection(collection);

  /// Builds a safe filter expression with bound [params]
  /// (e.g. `filterExpr('case = {:c}', {'c': id})`) — the only way to obtain
  /// a [PbFilter]. Never interpolate user input into [expr]; bind it via
  /// [params].
  PbFilter filterExpr(String expr, [Map<String, dynamic> params = const {}]) =>
      PbFilter._(pb.filter(expr, params));

  @override
  Future<T> getOne(String id, {String? expand}) =>
      _guard(() async => fromRecord(await service.getOne(id, expand: expand)));

  @override
  Future<List<T>> list({PbFilter? filter, String? sort, String? expand}) async {
    // Paged manually (not getFullList) so each round trip gets its own
    // [networkTimeout] budget: a large result on a slow link is many fast
    // requests instead of one long fetch that trips the shared timeout and
    // gets misreported as an unreachable server.
    final all = <T>[];
    var page = 1;
    while (true) {
      final items = await _guard(() async {
        final result = await service.getList(
          page: page,
          perPage: _listPageSize,
          skipTotal: true,
          filter: filter?.expression,
          sort: sort,
          expand: expand,
        );
        return result.items.map(fromRecord).toList();
      });
      all.addAll(items);
      if (items.length < _listPageSize) return all;
      page += 1;
    }
  }

  /// Returns the first record matching [filter], or `null` if none.
  Future<T?> firstWhere(PbFilter filter, {String? expand}) {
    return _guard(() async {
      try {
        final r = await service.getFirstListItem(
          filter.expression,
          expand: expand,
        );
        return fromRecord(r);
      } on ClientException catch (e) {
        if (e.statusCode == 404) return null;
        rethrow;
      }
    });
  }

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

  /// Runs a server [op], capping it at [networkTimeout] and translating SDK
  /// failures into a stable [RepositoryException].
  ///
  /// [write] flags ops that mutate server state: `Future.timeout` abandons the
  /// request client-side but cannot cancel it, so a slow (not dead) server may
  /// still commit the write after the timeout fires. Such timeouts surface as
  /// [RepositoryErrorKind.unknownOutcome] — not `network` — so the UI never
  /// tells the user "not reached, retry" when a retry could duplicate data.
  Future<R> _guard<R>(Future<R> Function() op, {bool write = false}) async {
    try {
      return await op().timeout(networkTimeout);
    } on TimeoutException {
      if (write) {
        throw const RepositoryException(
          'The server did not respond in time — the change may or may not '
          'have been saved',
          kind: RepositoryErrorKind.unknownOutcome,
        );
      }
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

/// PocketBase-backed [Repository] base: [PbReadOnlyRepository] plus the
/// mutating CRUD for regular (non-view) collections.
abstract class PbRepository<T> extends PbReadOnlyRepository<T>
    implements Repository<T> {
  PbRepository({
    required super.pb,
    required super.collection,
    required super.fromRecord,
    super.networkTimeout,
  });

  @override
  Future<T> create(Map<String, dynamic> body) => _guard(
    () async => fromRecord(await service.create(body: body)),
    write: true,
  );

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
        write: true,
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
        write: true,
      );

  @override
  Future<T> update(String id, Map<String, dynamic> body) => _guard(
    () async => fromRecord(await service.update(id, body: body)),
    write: true,
  );

  @override
  Future<void> delete(String id) =>
      _guard(() async => service.delete(id), write: true);
}

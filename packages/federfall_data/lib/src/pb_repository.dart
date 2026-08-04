import 'dart:async';

import 'package:federfall_data/src/repository_exception.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:pocketbase/pocketbase.dart';

/// Read-only contract of a collection repository. View-backed repositories
/// implement only this, so a create/update/delete against a PocketBase view
/// is a compile error instead of a runtime 400.
abstract interface class ReadOnlyRepository<T> {
  /// Fetches a single record by id, optionally expanding relations.
  Future<T> getOne(String id, {String? expand});

  /// Fetches all matching records (auto-paginated). [fields] restricts the
  /// response to a comma-separated subset of fields (PocketBase server-side
  /// projection) — use it when a caller only reads a couple of columns off a
  /// wide collection, so the unread ones never cross the wire.
  Future<List<T>> list({
    PbFilter? filter,
    String? sort,
    String? expand,
    String? fields,
  });
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

/// Where a keyset page left off: the sort key of the last row it returned.
///
/// `created` alone is not enough — PocketBase stores milliseconds, so two rows
/// written in the same millisecond would make one of them unreachable (or
/// repeat forever). The id breaks that tie.
@immutable
class PbCursor {
  const PbCursor({required this.created, required this.id});

  /// The raw PocketBase datetime string, passed back verbatim so no parse and
  /// re-format can shift it.
  final String created;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is PbCursor && other.created == created && other.id == id;

  @override
  int get hashCode => Object.hash(created, id);

  @override
  String toString() => 'PbCursor($created, $id)';
}

/// One page of a keyset-paged read, newest first.
class PbPage<T> {
  const PbPage({required this.items, this.cursor});

  final List<T> items;

  /// Pass to the next [PbReadOnlyRepository.page] call, or `null` when this
  /// was the last page.
  final PbCursor? cursor;

  bool get hasMore => cursor != null;
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
      guard(() async => fromRecord(await service.getOne(id, expand: expand)));

  @override
  Future<List<T>> list({
    PbFilter? filter,
    String? sort,
    String? expand,
    String? fields,
  }) async {
    // Paged manually (not getFullList) so each round trip gets its own
    // [networkTimeout] budget: a large result on a slow link is many fast
    // requests instead of one long fetch that trips the shared timeout and
    // gets misreported as an unreachable server.
    final all = <T>[];
    var page = 1;
    while (true) {
      final items = await guard(() async {
        final result = await service.getList(
          page: page,
          perPage: _listPageSize,
          skipTotal: true,
          filter: filter?.expression,
          sort: sort,
          expand: expand,
          fields: fields,
        );
        return result.items.map(fromRecord).toList();
      });
      all.addAll(items);
      if (items.length < _listPageSize) return all;
      page += 1;
    }
  }

  /// One page of newest-first records, resumed from [after].
  ///
  /// KEYSET paging, not offsets, and not because it is faster: an append-only
  /// feed grows at the end being read from. With `?page=2` every row written
  /// since the first request shifts the window, so the reader sees some rows
  /// twice and misses others entirely. Asking for "older than the last row I
  /// saw" cannot skip or repeat, however much arrives in between.
  ///
  /// The sort is therefore fixed to `-created,-id` and is not a parameter: it
  /// has to be the same key the cursor is built from, or paging silently
  /// returns nonsense. Callers who want a different order want [list].
  Future<PbPage<T>> page({
    PbFilter? filter,
    PbCursor? after,
    int perPage = 50,
    String? expand,
    String? fields,
  }) {
    return guard(() async {
      var expression = filter?.expression;
      if (after != null) {
        final keyset = pb.filter(
          '(created < {:c} || (created = {:c} && id < {:i}))',
          {'c': after.created, 'i': after.id},
        );
        expression = expression == null ? keyset : '($expression) && $keyset';
      }

      // A projection that omitted the sort key would leave every page with an
      // unbuildable cursor, so it is always requested back.
      final projection = fields == null
          ? null
          : {...fields.split(','), 'id', 'created'}.join(',');

      final result = await service.getList(
        page: 1,
        perPage: perPage,
        skipTotal: true,
        filter: expression,
        sort: '-created,-id',
        expand: expand,
        fields: projection,
      );

      // A short page means the end. A full one might be the end too; the next
      // call returning nothing settles it, which costs one request and never
      // stops early on a boundary.
      final last = result.items.isEmpty ? null : result.items.last;
      return PbPage(
        items: result.items.map(fromRecord).toList(),
        cursor: last == null || result.items.length < perPage
            ? null
            : PbCursor(
                created: '${last.data['created'] ?? ''}',
                id: last.id,
              ),
      );
    });
  }

  /// Counts the records matching [filter] **server-side** — one request that
  /// transfers a single row, not the whole result set.
  ///
  /// `list().length` would pull every matching record over the wire just to
  /// throw them away; this asks PocketBase for `totalItems` instead (hence
  /// `skipTotal: false`, unlike [list], which deliberately skips the count).
  /// Used where a number is the whole answer — e.g. "how many records still
  /// reference this code-list entry" before offering to delete it.
  Future<int> count({PbFilter? filter}) => guard(() async {
    final result = await service.getList(
      page: 1,
      perPage: 1,
      skipTotal: false,
      filter: filter?.expression,
      fields: 'id',
    );
    return result.totalItems;
  });

  /// Returns the first record matching [filter], or `null` if none.
  Future<T?> firstWhere(PbFilter filter, {String? expand}) {
    return guard(() async {
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
  ///
  /// Public so typed subclasses wrap their bespoke queries the same way.
  Future<R> guard<R>(Future<R> Function() op, {bool write = false}) async {
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
  Future<T> create(Map<String, dynamic> body) => guard(
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
  ) => guard(
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
  ) => guard(
    () async => fromRecord(await service.update(id, body: body, files: files)),
    write: true,
  );

  @override
  Future<T> update(String id, Map<String, dynamic> body) => guard(
    () async => fromRecord(await service.update(id, body: body)),
    write: true,
  );

  @override
  Future<void> delete(String id) =>
      guard(() async => service.delete(id), write: true);
}

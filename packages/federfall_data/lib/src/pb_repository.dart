import 'package:federfall_data/src/repository_exception.dart';
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
abstract class PbRepository<T> implements Repository<T> {
  PbRepository({
    required this.pb,
    required this.collection,
    required this.fromRecord,
  });

  /// The PocketBase client.
  final PocketBase pb;

  /// The collection name this repository owns.
  final String collection;

  /// Maps a raw record to the domain model.
  final T Function(RecordModel) fromRecord;

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

  @override
  Future<T> update(String id, Map<String, dynamic> body) =>
      _guard(() async => fromRecord(await service.update(id, body: body)));

  @override
  Future<void> delete(String id) => _guard(() => service.delete(id));

  /// Runs [op], translating PocketBase failures to [RepositoryException].
  Future<R> _guard<R>(Future<R> Function() op) async {
    try {
      return await op();
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }
}

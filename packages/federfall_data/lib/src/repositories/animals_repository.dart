import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_data/src/repository_exception.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `animals` collection (persistent animal identities).
class PbAnimalsRepository extends PbRepository<Animal> {
  PbAnimalsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'animals',
        fromRecord: Animal.fromRecord,
      );

  /// Animals whose name contains [query] (case-insensitive), name-sorted.
  Future<List<Animal>> searchByName(String query) => list(
    filter: filterExpr('name ~ {:q}', {'q': query}),
    sort: 'name',
  );

  /// Current residents of an aviary.
  Future<List<Animal>> residentsOf(String aviaryId) => list(
    filter: filterExpr('current_aviary = {:a}', {'a': aviaryId}),
    sort: 'name',
  );

  /// Animals currently housed in any aviary (`current_aviary` set) — the
  /// occupancy-count source for the aviary registry.
  Future<List<Animal>> housed() =>
      list(filter: filterExpr('current_aviary != ""'));

  /// Each `id = {:x}` clause adds ~30 chars to the GET query string; 100 ids
  /// per request stays a few kB — far below common 8 kB URL/proxy limits.
  static const int _byIdsChunkSize = 100;

  /// Animals by id, via `id = a || id = b …` filters. Large sets are split
  /// into chunks of [_byIdsChunkSize] fetched concurrently, so the filter can
  /// never overflow the URL length limit. Returns an empty list for no ids
  /// rather than fetching the whole collection; duplicate ids are fetched (and
  /// returned) once. Pass [fields] (always include `id`) when the caller only
  /// reads a couple of columns off the full record.
  Future<List<Animal>> byIds(Iterable<String> ids, {String? fields}) async {
    final wanted = ids.toSet().toList();
    if (wanted.isEmpty) return const [];
    final chunks = <Future<List<Animal>>>[];
    for (var start = 0; start < wanted.length; start += _byIdsChunkSize) {
      final end = start + _byIdsChunkSize;
      final chunk = wanted.sublist(
        start,
        end > wanted.length ? wanted.length : end,
      );
      final params = <String, Object?>{};
      final clauses = <String>[];
      for (var i = 0; i < chunk.length; i++) {
        clauses.add('id = {:id$i}');
        params['id$i'] = chunk[i];
      }
      chunks.add(
        list(filter: filterExpr(clauses.join(' || '), params), fields: fields),
      );
    }
    final results = await Future.wait(chunks);
    return [for (final r in results) ...r];
  }

  /// Atomic supervisor merge (federfall-eqy6) via
  /// `POST /api/federfall/merge-animals`: re-points every animal-scoped child
  /// record (cases, markings, weights, exams) from [duplicate] to [survivor],
  /// applies [fields] (each value `'survivor'`, `'duplicate'`, or — for
  /// `photo` only — `'none'`) on a conflict, re-derives the survivor's
  /// lifetime status from the merged case history, and deletes [duplicate] —
  /// all in one server-side transaction. Returns the survivor's id.
  Future<String> merge({
    required String survivor,
    required String duplicate,
    Map<String, String> fields = const {},
  }) => guard(() async {
    final res = await pb.send<Map<String, dynamic>>(
      '/api/federfall/merge-animals',
      method: 'POST',
      body: {
        'survivor': survivor,
        'duplicate': duplicate,
        'fields': fields,
      },
    );
    final id = res['id'];
    if (id is! String || id.isEmpty) {
      throw const RepositoryException(
        'Merge response is missing the surviving animal id',
        kind: RepositoryErrorKind.unknownOutcome,
      );
    }
    return id;
  }, write: true);
}

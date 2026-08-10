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

  /// The animals registry, name-sorted, one page at a time (federfall-trep).
  ///
  /// [text] matches the animal's name or the code of any marking it carries —
  /// the same two things the registry's search box always matched, now asked
  /// of the server instead of of a copy of the collection. As on the case
  /// browser, the marking clause is not restricted to active markings: two
  /// conditions on one back-relation are satisfied independently, so a
  /// combined `is_active = true && code ~ q` could pair one animal's active
  /// marking with a different, removed one.
  ///
  /// Ordered by name rather than by recency because a registry is browsed
  /// alphabetically. That order is now the server's — SQLite's BINARY
  /// collation — so unlike the old `toLowerCase()` compare it is
  /// case-sensitive; unnamed birds (empty name) still group at the top.
  Future<PbPage<Animal>> browse({
    String text = '',
    PbCursor? after,
    int perPage = 50,
  }) {
    final q = text.trim();
    return page(
      filter: q.isEmpty
          ? null
          : filterExpr(
              '(name ~ {:q} || markings_via_animal.code ~ {:q})',
              {'q': q},
            ),
      after: after,
      perPage: perPage,
      sortKey: const PbSortKey('name', descending: false),
    );
  }

  /// Current residents of an aviary.
  Future<List<Animal>> residentsOf(String aviaryId) => list(
    filter: filterExpr('current_aviary = {:a}', {'a': aviaryId}),
    sort: 'name',
  );

  /// Animals currently housed in any aviary (`current_aviary` set) — the
  /// occupancy-count source for the aviary registry.
  Future<List<Animal>> housed() =>
      list(filter: filterExpr('current_aviary != ""'));

  /// How many animals the caller may read live in an enclosure, counted
  /// server-side — one row over the wire, not the whole collection to be
  /// filtered on the device (federfall-s0wk).
  ///
  /// The same predicate as [housed], deliberately: this is the dashboard's
  /// aviary tile, which taps through to the aviary registry, and the two have
  /// to agree. It counted `lifetime_status = in_aviary` until federfall-8f1m
  /// made an open case win that field — a resident under treatment now reads
  /// `in_care` while still occupying its enclosure, so the label stopped being
  /// a census of who is in one.
  Future<int> countHoused() =>
      count(filter: filterExpr('current_aviary != ""'));

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

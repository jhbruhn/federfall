import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `animals` collection (persistent animal identities).
class PbAnimalsRepository extends PbRepository<Animal> {
  PbAnimalsRepository(PocketBase pb, {super.cache, super.isOffline})
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

  /// Animals by id, in one query (an `id = a || id = b …` filter). Returns an
  /// empty list for no ids rather than fetching the whole collection.
  Future<List<Animal>> byIds(Iterable<String> ids) {
    final wanted = ids.toList();
    if (wanted.isEmpty) return Future.value(const []);
    final params = <String, Object?>{};
    final clauses = <String>[];
    for (var i = 0; i < wanted.length; i++) {
      clauses.add('id = {:id$i}');
      params['id$i'] = wanted[i];
    }
    return list(filter: filterExpr(clauses.join(' || '), params));
  }
}

import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `markings` collection — drives re-identification of
/// returning animals from a scanned/entered code (FED-4.10).
class PbMarkingsRepository extends PbRepository<Marking> {
  PbMarkingsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'markings',
        fromRecord: Marking.fromRecord,
      );

  /// All markings ever recorded for an animal (lifetime), newest first.
  Future<List<Marking>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: '-applied_at',
  );

  /// Active markings whose code matches [code] — the re-identification lookup.
  Future<List<Marking>> activeByCode(String code) => list(
    filter: filterExpr('code = {:c} && is_active = true', {'c': code}),
  );

  static const int _byAnimalsChunkSize = 100;

  /// Active markings for a set of animals — the codes shown on the animals
  /// registry's rows, fetched for the page on screen rather than for the org
  /// (federfall-trep). Same chunked `animal = {:x} || …` shape as
  /// `PbAnimalsRepository.byIds`; empty input costs no request.
  Future<List<Marking>> activeByAnimals(Iterable<String> animalIds) async {
    final wanted = animalIds.toSet().toList();
    if (wanted.isEmpty) return const [];
    final chunks = <Future<List<Marking>>>[];
    for (var start = 0; start < wanted.length; start += _byAnimalsChunkSize) {
      final end = start + _byAnimalsChunkSize;
      final chunk = wanted.sublist(
        start,
        end > wanted.length ? wanted.length : end,
      );
      final params = <String, Object?>{};
      final clauses = <String>[];
      for (var i = 0; i < chunk.length; i++) {
        clauses.add('animal = {:a$i}');
        params['a$i'] = chunk[i];
      }
      chunks.add(
        list(
          filter: filterExpr(
            'is_active = true && (${clauses.join(' || ')})',
            params,
          ),
        ),
      );
    }
    final results = await Future.wait(chunks);
    return [for (final r in results) ...r];
  }

  /// How many markings still name the [typeId] code-list entry.
  ///
  /// Unlike the other code lists, `markings.type` is a **required** relation,
  /// so PocketBase refuses to delete a type any marking still uses ("Make sure
  /// that the record is not part of a required relation reference"). The
  /// code-list confirmation uses this count to say so up front instead of
  /// letting that error surface.
  Future<int> countForType(String typeId) =>
      count(filter: filterExpr('type = {:t}', {'t': typeId}));
}

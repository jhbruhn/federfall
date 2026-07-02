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

  /// Every currently-active marking the member may see (org-scoped) — the
  /// source for the code-by-animal lookup behind registry rows and search.
  Future<List<Marking>> allActive() =>
      list(filter: filterExpr('is_active = true'));
}

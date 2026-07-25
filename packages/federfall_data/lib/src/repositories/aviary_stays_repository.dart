import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `aviary_stays` collection (append-only residency
/// ledger, federfall-d5co.1). Read-only from the app: rows are maintained
/// server-side by a hook on `animals`, never written directly by a client.
class PbAviaryStaysRepository extends PbReadOnlyRepository<AviaryStay> {
  PbAviaryStaysRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'aviary_stays',
        fromRecord: AviaryStay.fromRecord,
      );

  /// Residency history for an aviary, newest stay first.
  Future<List<AviaryStay>> forAviary(String aviaryId) => list(
    filter: filterExpr('aviary = {:a}', {'a': aviaryId}),
    sort: '-started_at',
  );

  /// The stays of one animal that were open on [at] — normally zero (never
  /// housed then) or one. Used to answer "which enclosure was this bird in on
  /// that date", the reason no aviary is denormalised onto dated records.
  ///
  /// An unset `ended_at` means the stay is still open, so it covers any date at
  /// or after its start.
  Future<List<AviaryStay>> forAnimalAt(String animalId, DateTime at) {
    final when = at.toUtc().toIso8601String();
    return list(
      filter: filterExpr(
        'animal = {:a} && started_at <= {:t}'
        " && (ended_at = '' || ended_at >= {:t})",
        {'a': animalId, 't': when},
      ),
      sort: '-started_at',
    );
  }

  /// Every stay in an aviary that was open on [at] — the enclosure's roster for
  /// that day.
  Future<List<AviaryStay>> residentsAt(String aviaryId, DateTime at) {
    final when = at.toUtc().toIso8601String();
    return list(
      filter: filterExpr(
        'aviary = {:v} && started_at <= {:t}'
        " && (ended_at = '' || ended_at >= {:t})",
        {'v': aviaryId, 't': when},
      ),
      sort: 'started_at',
    );
  }
}

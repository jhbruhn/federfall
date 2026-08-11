import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `sponsorships` collection — Patenschaften on aviary
/// residents (federfall-5s5j).
///
/// Every read here is already narrowed by the server: the access rule resolves
/// through `animal.current_aviary.keeper`, so a keeper sees the patronages of
/// their own residents and a coordinator/supervisor sees the org's. Nothing in
/// this class filters by viewer, and nothing should — a client-side scope over
/// PII would be a second, weaker copy of the boundary.
class PbSponsorshipsRepository extends PbRepository<Sponsorship> {
  PbSponsorshipsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'sponsorships',
        fromRecord: Sponsorship.fromRecord,
      );

  /// Every patronage recorded for an animal, newest arrangement first.
  ///
  /// Sorted by `-started_at` with `-created` behind it, because `started_at`
  /// is optional: rows without one would otherwise land in an arbitrary order
  /// among themselves.
  Future<List<Sponsorship>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: '-started_at,-created',
  );

  /// How many patronages the animal carries.
  ///
  /// This is what the disposition sheet's transfer warning counts — a COUNT, so
  /// the sentence can say how much data is about to change hands without naming
  /// a single sponsor.
  Future<int> countForAnimal(String animalId) =>
      count(filter: filterExpr('animal = {:a}', {'a': animalId}));
}

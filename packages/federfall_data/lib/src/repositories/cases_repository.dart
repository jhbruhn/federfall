import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `cases` collection (admission episodes).
///
/// Carries a dedicated interface (beyond the generic [Repository]) so callers
/// can depend on the case-specific queries below.
abstract interface class CasesRepository implements Repository<Case> {
  /// Open cases (not yet disposed), newest first.
  Future<List<Case>> active();

  /// Every case for one animal (its admission history), newest first.
  Future<List<Case>> forAnimal(String animalId);

  /// Cases where [carerId] is the active carer ("my cases"), newest first.
  Future<List<Case>> forCarer(String carerId);

  /// The case with the given per-year number, or `null`.
  Future<Case?> byCaseNumber(String caseNumber);
}

class PbCasesRepository extends PbRepository<Case> implements CasesRepository {
  PbCasesRepository(PocketBase pb, {super.cache, super.isOffline})
    : super(
        pb: pb,
        collection: 'cases',
        fromRecord: Case.fromRecord,
      );

  @override
  Future<List<Case>> active() => list(
    filter: filterExpr('status != {:s}', {'s': 'disposed'}),
    sort: '-created',
  );

  @override
  Future<List<Case>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: '-created',
  );

  @override
  Future<List<Case>> forCarer(String carerId) => list(
    filter: filterExpr('active_carer = {:c}', {'c': carerId}),
    sort: '-created',
  );

  @override
  Future<Case?> byCaseNumber(String caseNumber) => firstWhere(
    filterExpr('case_number = {:n}', {'n': caseNumber}),
  );
}

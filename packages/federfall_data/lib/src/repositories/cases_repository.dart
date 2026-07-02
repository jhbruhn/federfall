import 'dart:async';

import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_data/src/repository_exception.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// Ids of the records created by one atomic intake call.
typedef IntakeResult = ({String caseId, String animalId});

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

  /// Atomic case intake via `POST /api/federfall/intake`: creates the animal
  /// (or reuses `payload['animal']`), the optional finder and the case — plus
  /// an intake weight and a quarantine override when given — in one
  /// server-side transaction, so a failure never strands partial records
  /// (federfall-zod). [photos] land on the case's `intake_photos` field.
  Future<IntakeResult> intake(
    Map<String, dynamic> payload, {
    List<http.MultipartFile> photos,
  });
}

class PbCasesRepository extends PbRepository<Case> implements CasesRepository {
  PbCasesRepository(
    PocketBase pb, {
    super.networkTimeout,
  }) : super(
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

  @override
  Future<IntakeResult> intake(
    Map<String, dynamic> payload, {
    List<http.MultipartFile> photos = const [],
  }) async {
    try {
      final res = await pb
          .send<Map<String, dynamic>>(
            '/api/federfall/intake',
            method: 'POST',
            body: payload,
            files: photos,
          )
          .timeout(networkTimeout);
      final caseId = res['id'];
      final animalId = res['animal'];
      if (caseId is! String ||
          caseId.isEmpty ||
          animalId is! String ||
          animalId.isEmpty) {
        // The transaction committed (2xx) but the response lacks the ids the
        // caller navigates with — surface that instead of empty-string ids
        // that route to a confusing 404. `unknownOutcome` because a retry
        // would create a second animal+case.
        throw const RepositoryException(
          'Intake response is missing the created record ids',
          kind: RepositoryErrorKind.unknownOutcome,
        );
      }
      return (caseId: caseId, animalId: animalId);
    } on TimeoutException {
      // The request left the device; a slow server may still commit the
      // intake, so a retry can duplicate the animal+case.
      throw const RepositoryException(
        'The server did not respond in time — the intake may or may not '
        'have been saved',
        kind: RepositoryErrorKind.unknownOutcome,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }
}

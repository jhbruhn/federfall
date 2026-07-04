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

  /// Cases across many animals in one call — same chunked `animal = {:x} ||
  /// …` pattern as `PbAnimalsRepository.byIds` and
  /// `PbCaseConditionsRepository.byCases`, so a multi-animal rollup (the
  /// aviary flock health rollup, federfall-d5co.3) costs O(1) requests
  /// instead of one per animal. Empty input short-circuits to no request.
  Future<List<Case>> byAnimals(Iterable<String> animalIds);

  /// Cases where [carerId] is the active carer ("my cases"), newest first.
  Future<List<Case>> forCarer(String carerId);

  /// The case with the given per-year number, or `null`.
  Future<Case?> byCaseNumber(String caseNumber);

  /// The case detail's whole data set in ONE request (federfall-kh0u): the
  /// case plus its animal, finder and all twelve timeline collections via
  /// relation expand ([caseBundleExpand]). Expanded rows honor each
  /// collection's view rule, so this changes nothing about access control.
  Future<CaseBundle> bundle(String id);

  /// Atomic case intake via `POST /api/federfall/intake`: creates the animal
  /// (or reuses `payload['animal']`), the optional finder and the case — plus
  /// an intake weight and a quarantine override when given — in one
  /// server-side transaction, so a failure never strands partial records
  /// (federfall-zod). [photos] land on the case's `intake_photos` field.
  ///
  /// [idempotencyKey] (see `newIdempotencyKey`) makes retries safe
  /// (federfall-3ty3): the backend stores the response under the key, and a
  /// resubmission of the same key — e.g. after a timeout whose first request
  /// actually committed — returns the original result instead of creating a
  /// second animal+case. Callers must reuse ONE key across all retries of the
  /// same logical intake.
  Future<IntakeResult> intake(
    Map<String, dynamic> payload, {
    List<http.MultipartFile> photos,
    String? idempotencyKey,
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

  static const int _byAnimalsChunkSize = 100;

  @override
  Future<List<Case>> byAnimals(Iterable<String> animalIds) async {
    final wanted = animalIds.toSet().toList();
    if (wanted.isEmpty) return const [];
    final chunks = <Future<List<Case>>>[];
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
      chunks.add(list(filter: filterExpr(clauses.join(' || '), params)));
    }
    final results = await Future.wait(chunks);
    return [for (final r in results) ...r];
  }

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
  Future<CaseBundle> bundle(String id) => guard(
    () async => CaseBundle.fromRecord(
      await service.getOne(id, expand: caseBundleExpand),
    ),
  );

  @override
  Future<IntakeResult> intake(
    Map<String, dynamic> payload, {
    List<http.MultipartFile> photos = const [],
    String? idempotencyKey,
  }) async {
    try {
      final res = await pb
          .send<Map<String, dynamic>>(
            '/api/federfall/intake',
            method: 'POST',
            body: {
              ...payload,
              'idempotency_key': ?idempotencyKey,
            },
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
      // intake. With an idempotency key a resubmission converges on the
      // committed result (plain network error); without one a retry can
      // duplicate the animal+case.
      if (idempotencyKey != null) {
        throw const RepositoryException(
          'The server did not respond in time',
          kind: RepositoryErrorKind.network,
        );
      }
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

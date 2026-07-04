import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `conditions` code list (supervisor-managed diagnoses).
class PbConditionsRepository extends PbRepository<Condition> {
  PbConditionsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'conditions',
        fromRecord: Condition.fromRecord,
      );

  /// Active code-list entries, label-sorted, for diagnosis pickers.
  Future<List<Condition>> active() => list(
    filter: filterExpr('active = true'),
    sort: 'label',
  );
}

/// Repository over the `case_conditions` collection (diagnoses on a case).
class PbCaseConditionsRepository extends PbRepository<CaseCondition> {
  PbCaseConditionsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'case_conditions',
        fromRecord: CaseCondition.fromRecord,
      );

  /// Diagnoses recorded on a case, newest first.
  Future<List<CaseCondition>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-created',
  );

  /// Same chunking as `PbAnimalsRepository.byIds`: 100 `case = {:x}` clauses
  /// per request, fetched concurrently, so a large case set can never overflow
  /// the URL length limit. Diagnoses across many cases in one call (the
  /// aviary flock health rollup, federfall-d5co.3). Empty input short-circuits
  /// to no request.
  static const int _byCasesChunkSize = 100;

  Future<List<CaseCondition>> byCases(Iterable<String> caseIds) async {
    final wanted = caseIds.toSet().toList();
    if (wanted.isEmpty) return const [];
    final chunks = <Future<List<CaseCondition>>>[];
    for (var start = 0; start < wanted.length; start += _byCasesChunkSize) {
      final end = start + _byCasesChunkSize;
      final chunk = wanted.sublist(
        start,
        end > wanted.length ? wanted.length : end,
      );
      final params = <String, Object?>{};
      final clauses = <String>[];
      for (var i = 0; i < chunk.length; i++) {
        clauses.add('case = {:c$i}');
        params['c$i'] = chunk[i];
      }
      chunks.add(list(filter: filterExpr(clauses.join(' || '), params)));
    }
    final results = await Future.wait(chunks);
    return [for (final r in results) ...r];
  }
}

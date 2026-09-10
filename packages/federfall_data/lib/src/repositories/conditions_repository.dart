import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_data/src/repositories/codelist_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `conditions` code list (supervisor-managed diagnoses).
class PbConditionsRepository extends PbRepository<Condition>
    with CodelistRepository<Condition> {
  PbConditionsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'conditions',
        fromRecord: Condition.fromRecord,
      );

  @override
  String labelOf(Condition entry) => entry.label;
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

  /// How many recorded diagnoses still name the [conditionId] code-list entry.
  ///
  /// `condition` is an optional relation with `cascadeDelete: false`, so
  /// deleting the entry does not delete these rows — PocketBase silently
  /// **blanks** the field on each of them, leaving a diagnosis with no
  /// condition. The code-list delete confirmation states this number before
  /// offering that.
  Future<int> countForCondition(String conditionId) =>
      count(filter: filterExpr('condition = {:c}', {'c': conditionId}));

  /// Same chunking as `PbAnimalsRepository.byIds`: 100 `case = {:x}` clauses
  /// per request, fetched concurrently, so a large case set can never overflow
  /// the URL length limit. Diagnoses across many cases in one call (the
  /// aviary flock health rollup, federfall-d5co.3). Empty input short-circuits
  /// to no request. Pass `fields` (always include `id`) when the caller only
  /// reads a couple of columns off the full record.
  static const int _byCasesChunkSize = 100;

  /// [openOnly] narrows to the diagnoses still in force — `resolved_date`
  /// empty — server-side. The case browser's row subtitle wants exactly those
  /// and nothing else (federfall-78k6.5), and a long case accumulates resolved
  /// ones it would otherwise pull down a page at a time; federfall-trep's rule
  /// is that a list screen receives the rows it is about to draw. The flock
  /// rollup leaves it false: it dates each diagnosis against a residency
  /// window, so a resolved one is still evidence.
  Future<List<CaseCondition>> byCases(
    Iterable<String> caseIds, {
    String? fields,
    bool openOnly = false,
  }) async {
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
      // The case clauses are ORed, so the resolved-date test has to sit
      // OUTSIDE their parentheses or it would only apply to the last one.
      final cases = clauses.join(' || ');
      final filter = openOnly ? '($cases) && resolved_date = ""' : cases;
      chunks.add(
        list(filter: filterExpr(filter, params), fields: fields),
      );
    }
    final results = await Future.wait(chunks);
    return [for (final r in results) ...r];
  }
}

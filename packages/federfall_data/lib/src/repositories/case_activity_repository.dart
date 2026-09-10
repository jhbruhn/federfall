import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the org-wide `case_activity` view (cr3.5): the last time
/// anything happened on each case, used to surface "stale" cases on the carer
/// worklist without an N+1 scan of every child collection.
class PbCaseLastActivityRepository
    extends PbReadOnlyRepository<CaseLastActivity> {
  PbCaseLastActivityRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'case_activity',
        fromRecord: CaseLastActivity.fromRecord,
      );

  /// Activity for every case the signed-in member may see (org-scoped).
  Future<List<CaseLastActivity>> all() => list(sort: '-last_activity');

  /// Activity for the given cases only — the case browser's per-page read
  /// (federfall-78k6.4). The view's own id IS the case id, so these are the
  /// same ids the page was drawn from.
  ///
  /// Chunked like `PbCaseConditionsRepository.byCases`, so a page can never
  /// overflow the URL length limit. Empty input short-circuits to no request.
  Future<List<CaseLastActivity>> byCases(Iterable<String> caseIds) async {
    final wanted = caseIds.toSet().toList();
    if (wanted.isEmpty) return const [];
    final chunks = <Future<List<CaseLastActivity>>>[];
    for (var start = 0; start < wanted.length; start += _chunkSize) {
      final end = start + _chunkSize;
      final chunk = wanted.sublist(
        start,
        end > wanted.length ? wanted.length : end,
      );
      final params = <String, Object?>{};
      final clauses = <String>[];
      for (var i = 0; i < chunk.length; i++) {
        clauses.add('id = {:c$i}');
        params['c$i'] = chunk[i];
      }
      chunks.add(list(filter: filterExpr(clauses.join(' || '), params)));
    }
    final results = await Future.wait(chunks);
    return [for (final r in results) ...r];
  }

  static const int _chunkSize = 100;
}

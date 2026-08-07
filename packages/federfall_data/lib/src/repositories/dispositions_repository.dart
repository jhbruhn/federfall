import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `dispositions` collection (case outcomes).
class PbDispositionsRepository extends PbRepository<Disposition> {
  PbDispositionsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'dispositions',
        fromRecord: Disposition.fromRecord,
      );

  /// Disposition history for a case, newest first (usually one final row).
  Future<List<Disposition>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-disposed_at',
  );

  static const int _byCasesChunkSize = 100;

  /// Dispositions across many cases in one call — the same chunked
  /// `case = {:x} || …` pattern as `PbCaseConditionsRepository.byCases`, so
  /// resolving the terminal outcome of a browser page costs O(1) requests
  /// instead of one per case. Empty input short-circuits to no request.
  Future<List<Disposition>> byCases(Iterable<String> caseIds) async {
    final wanted = caseIds.toSet().toList();
    if (wanted.isEmpty) return const [];
    final chunks = <Future<List<Disposition>>>[];
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

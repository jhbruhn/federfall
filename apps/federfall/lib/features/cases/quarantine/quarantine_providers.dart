import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'quarantine_providers.g.dart';

/// Quarantine records on a case, newest first (federfall-uvm) — a timeline
/// source. The default 14-day intake row is created server-side on case create.
@riverpod
Future<List<Quarantine>> quarantineForCase(Ref ref, String caseId) async {
  final repo = await ref.watch(quarantineRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// The current quarantine end per case (case id → end date), read from the
/// `case_quarantine` view. Feeds the worklist and dashboard, which used to read
/// the dropped `cases.quarantine_until` field.
@riverpod
Future<Map<String, DateTime?>> caseQuarantineUntil(Ref ref) async {
  final repo = await ref.watch(caseQuarantineRepositoryProvider.future);
  final rows = await repo.all();
  return {for (final r in rows) r.id: r.until};
}

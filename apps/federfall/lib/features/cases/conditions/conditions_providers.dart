import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'conditions_providers.g.dart';

/// Diagnoses recorded on a case, newest first (FED-4.5).
@riverpod
Future<List<CaseCondition>> caseConditionsForCase(
  Ref ref,
  String caseId,
) async {
  final repo = await ref.watch(caseConditionsRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// The full condition code list, label-sorted. Used to populate the picker
/// (active entries only) and to resolve a stored condition id → its label and
/// notifiable flag on the timeline (so a now-inactive entry still resolves).
@riverpod
Future<List<Condition>> conditions(Ref ref) async {
  final repo = await ref.watch(conditionsRepositoryProvider.future);
  return repo.list(sort: 'label');
}

/// Code-list entries keyed by id, for label/notifiable lookup.
@riverpod
Future<Map<String, Condition>> conditionsById(Ref ref) async {
  final all = await ref.watch(conditionsProvider.future);
  return {for (final c in all) c.id: c};
}

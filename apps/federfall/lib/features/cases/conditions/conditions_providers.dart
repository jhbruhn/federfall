import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'conditions_providers.g.dart';

/// Diagnoses recorded on a case, newest first (FED-4.5).
@riverpod
Future<List<CaseCondition>> caseConditionsForCase(Ref ref, String caseId) =>
    caseBundleList(ref, caseId, (b) => b.caseConditions, () async {
      final repo = await ref.watch(caseConditionsRepositoryProvider.future);
      return repo.forCase(caseId);
    });

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

/// The diagnoses the org has actually recorded, most-used first
/// (`condition_labels` view, federfall-ye5e). Distinct from
/// [conditionsProvider]: that is the supervisor-curated vocabulary a new
/// diagnosis may be *picked from*, this is what is already *on* cases — so it
/// omits never-used entries and includes free text, which makes it the right
/// source for a filter and the wrong one for the entry sheet.
///
/// Auto-disposed on purpose, unlike the code list: this changes every time a
/// diagnosis is recorded anywhere in the org, so a filter sheet reopened later
/// must not offer a stale vocabulary. It is one small row set (the server has
/// already scoped it — a carer legitimately receives fewer rows than a
/// coordinator), so re-reading it is cheap.
@riverpod
Future<List<ConditionLabel>> recordedConditions(Ref ref) async {
  final repo = await ref.watch(conditionLabelsRepositoryProvider.future);
  return repo.all();
}

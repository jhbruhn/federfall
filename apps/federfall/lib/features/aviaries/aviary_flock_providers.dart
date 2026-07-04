import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'aviary_flock_providers.g.dart';

/// Aviary-scoped free-text journal entries (federfall-d5co.2), newest first.
@riverpod
Future<List<JournalEntry>> aviaryJournal(Ref ref, String aviaryId) async {
  final repo = await ref.watch(journalRepositoryProvider.future);
  return repo.forAviary(aviaryId);
}

/// One condition rolled up onto the flock timeline, paired with the resident
/// it was diagnosed on (for display) — null if that animal record is gone.
typedef AviaryConditionRollupEntry = ({
  CaseCondition condition,
  Animal? animal,
});

/// Every condition diagnosed while an animal was resident in this aviary,
/// across ALL of its cases (federfall-d5co.3) — computed HISTORICALLY so the
/// rollup stays accurate even after a resident has moved to a different
/// aviary (a live `current_aviary` filter would lose that once it moves).
///
/// Built client-side from the residency ledger:
///   aviary_stays (this aviary) -> resident animal ids + date windows
///   -> those animals' cases -> those cases' case_conditions
///   -> keep only conditions whose onset (or created) date falls inside the
///      residency window that made the animal a resident HERE.
@riverpod
Future<List<AviaryConditionRollupEntry>> aviaryHealthRollup(
  Ref ref,
  String aviaryId,
) async {
  final staysRepo = await ref.watch(aviaryStaysRepositoryProvider.future);
  final stays = await staysRepo.forAviary(aviaryId);
  if (stays.isEmpty) return const [];

  final animalIds = {for (final s in stays) s.animal};
  final animalsRepo = await ref.watch(animalsRepositoryProvider.future);
  final animalsById = {
    for (final a in await animalsRepo.byIds(animalIds)) a.id: a,
  };

  final casesRepo = await ref.watch(casesRepositoryProvider.future);
  final cases = await casesRepo.byAnimals(animalIds);
  if (cases.isEmpty) return const [];
  final animalIdByCaseId = {for (final c in cases) c.id: c.animal};

  final conditionsRepo = await ref.watch(
    caseConditionsRepositoryProvider.future,
  );
  final conditions = await conditionsRepo.byCases(
    cases.map((c) => c.id),
  );

  final windowsByAnimal = <String, List<AviaryStay>>{};
  for (final s in stays) {
    (windowsByAnimal[s.animal] ??= []).add(s);
  }

  bool withinAResidencyWindow(String animalId, DateTime at) {
    for (final w in windowsByAnimal[animalId] ?? const <AviaryStay>[]) {
      final start = w.startedAt ?? w.created;
      if (start == null) continue;
      final end = w.endedAt ?? DateTime.now();
      if (!at.isBefore(start) && !at.isAfter(end)) return true;
    }
    return false;
  }

  return [
    for (final condition in conditions)
      if (animalIdByCaseId[condition.caseId] case final animalId?)
        if (condition.onsetDate ?? condition.created case final at?)
          if (withinAResidencyWindow(animalId, at))
            (condition: condition, animal: animalsById[animalId]),
  ];
}

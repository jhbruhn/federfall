import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vaccinations_providers.g.dart';

/// This feature lives under `features/animals/` rather than beside the eggs in
/// `features/cases/`: a vaccination's primary surface is the animal detail, and
/// its case-timeline appearance is derived. The direction of the import is the
/// one this app already has (the animal detail imports the egg widgets), just
/// pointed the way the data actually flows.

/// Every shot recorded for an animal, oldest first — the lifetime ledger behind
/// the animal detail's vaccination card and its per-target roll-up.
@riverpod
Future<List<Vaccination>> vaccinationsForAnimal(
  Ref ref,
  String animalId,
) async {
  final repo = await ref.watch(vaccinationsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// The shots that fall inside a case's own window, newest first — the case
/// timeline source, served off the [caseBundle] so the case detail needs no
/// extra request.
///
/// Windowed like the eggs rather than shown whole like the markings: a ring is
/// a standing property of the bird, a shot is a dated event, and a lifetime of
/// them would swamp the chronology of one treatment episode. The whole history
/// is one tap away on the animal.
@riverpod
Future<List<Vaccination>> vaccinationsForCase(Ref ref, String caseId) async {
  final bundle = await ref.watch(caseBundleProvider(caseId).future);
  final shots = await caseBundleList(
    ref,
    caseId,
    (b) => b.vaccinations,
    () async {
      final repo = await ref.watch(vaccinationsRepositoryProvider.future);
      return repo.forAnimal(bundle.medicalCase.animal);
    },
  );
  return vaccinationsInCaseWindow(shots, bundle);
}

/// The (vaccine, target) pairs this org has already recorded, most recently
/// used first — the entry sheet's suggestions.
///
/// This is the vocabulary, and it is a VIEW rather than a code list
/// (1700000088): it builds itself out of use, so it offers nothing dead and
/// there is nothing for a supervisor to curate before anyone can record a shot.
@riverpod
Future<List<VaccineLabel>> vaccineLabels(Ref ref) async {
  final repo = await ref.watch(vaccineLabelsRepositoryProvider.future);
  return repo.all();
}

/// Narrows a lifetime of shots to the ones belonging to [bundle]'s case: from
/// its admission (unbounded before it if none is recorded) to its latest
/// disposition, or to now while the case is still open.
///
/// The same window `eggsInCaseWindow` applies, for the same reason — neither
/// record carries a case relation, so membership is computed here.
List<Vaccination> vaccinationsInCaseWindow(
  List<Vaccination> shots,
  CaseBundle bundle,
) {
  final from = bundle.medicalCase.admittedAt;
  // dispositions come newest-first out of the bundle.
  final closed = bundle.dispositions
      .map((d) => d.disposedAt ?? d.created)
      .nonNulls
      .firstOrNull;
  final until = closed ?? DateTime.now();
  return shots.where((v) {
    final at = v.at;
    if (at == null) return false;
    if (from != null && at.isBefore(from)) return false;
    return !at.isAfter(until);
  }).toList();
}

/// What a bird's vaccination ledger says about ONE thing it was vaccinated
/// against — the row the animal card renders.
///
/// Grouped on the recorded [target] string, because the schema keeps it free
/// text (1700000087). Two spellings are two rows, which is honest: converging
/// them is the suggestion list's job at the point of entry, not a rewrite of
/// what somebody recorded.
class VaccinationStatus {
  const VaccinationStatus({
    required this.target,
    required this.last,
    required this.count,
  });

  /// The recorded target, or null for shots logged without one — those group
  /// together under the product rather than being dropped.
  final String? target;

  /// The most recent shot against this target.
  final Vaccination last;

  /// How many shots this bird has had against it.
  final int count;

  /// When a booster is next due, if one was planned on the latest shot.
  DateTime? get nextDueAt => last.nextDueAt;

  /// Whether that booster is due now. A shot with no planned booster is never
  /// "due" — nothing was scheduled, which is not the same as overdue.
  bool isDue({DateTime? now}) => last.isDue(now: now);
}

/// The per-target roll-up of a bird's whole ledger, most recently vaccinated
/// first. Derived on every read rather than denormalised onto `animals`, so it
/// cannot drift when a row is edited or the bird is merged.
List<VaccinationStatus> vaccinationStatuses(List<Vaccination> shots) {
  final byTarget = <String?, List<Vaccination>>{};
  for (final shot in shots) {
    // Trimmed and case-folded for grouping only — the label shown is whatever
    // the latest shot recorded, never a normalised rewrite of it.
    final key = shot.target?.trim().toLowerCase();
    final group = (key == null || key.isEmpty) ? null : key;
    byTarget.putIfAbsent(group, () => []).add(shot);
  }

  final out = <VaccinationStatus>[];
  for (final entry in byTarget.entries) {
    final sorted = [...entry.value]
      ..sort((a, b) => (a.at ?? _epoch).compareTo(b.at ?? _epoch));
    final last = sorted.last;
    out.add(
      VaccinationStatus(
        target: last.target?.trim().isEmpty ?? true
            ? null
            : last.target?.trim(),
        last: last,
        count: sorted.length,
      ),
    );
  }
  out.sort((a, b) => (b.last.at ?? _epoch).compareTo(a.last.at ?? _epoch));
  return out;
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

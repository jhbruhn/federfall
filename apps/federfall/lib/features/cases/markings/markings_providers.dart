import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'markings_providers.g.dart';

/// All markings recorded for an animal across its lifetime, newest first
/// (FED-4.10) — the animal detail and re-identification source.
@riverpod
Future<List<Marking>> markingsForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(markingsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// The same lifetime markings viewed from a case (the timeline source),
/// served off the [caseBundle] so the case detail needs no extra request.
@riverpod
Future<List<Marking>> markingsForCase(Ref ref, String caseId) =>
    caseBundleList(ref, caseId, (b) => b.markings, () async {
      final bundle = await ref.watch(caseBundleProvider(caseId).future);
      final repo = await ref.watch(markingsRepositoryProvider.future);
      return repo.forAnimal(bundle.medicalCase.animal);
    });

/// A re-identification candidate: an existing animal plus its active markings.
class ReidMatch {
  const ReidMatch({required this.animal, required this.markings});

  final Animal animal;
  final List<Marking> markings;
}

/// Re-identification search (FED-4.10): finds existing animals by an active
/// marking code or by name, so an intake can be linked to a returning bird.
/// Returns at most a handful of de-duplicated matches.
@riverpod
Future<List<ReidMatch>> reidSearch(Ref ref, String query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];

  final animalsRepo = await ref.watch(animalsRepositoryProvider.future);
  final markingsRepo = await ref.watch(markingsRepositoryProvider.future);

  final byCode = await markingsRepo.activeByCode(q);
  final byName = await animalsRepo.searchByName(q);

  // Resolve the animals behind matched markings, de-duplicating with name
  // hits. The per-animal fetches here and below run concurrently — awaiting
  // them one by one made every code match cost an extra sequential round trip
  // in the middle of the intake wizard.
  final animalsById = {for (final a in byName) a.id: a};
  final missing = byCode.map((m) => m.animal).toSet()
    ..removeAll(animalsById.keys);
  for (final animal in await Future.wait(missing.map(animalsRepo.getOne))) {
    animalsById[animal.id] = animal;
  }

  return Future.wait([
    for (final animal in animalsById.values)
      markingsRepo
          .forAnimal(animal.id)
          .then(
            (markings) => ReidMatch(
              animal: animal,
              markings: markings.where((m) => m.isActive).toList(),
            ),
          ),
  ]);
}

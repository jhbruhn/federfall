import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'markings_providers.g.dart';

/// All markings recorded for an animal across its lifetime, newest first
/// (FED-4.10). Surfaced on the case timeline and in re-identification results.
@riverpod
Future<List<Marking>> markingsForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(markingsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// Active marking codes (ring / chip / band) keyed by animal id, in record
/// order. Shared lookup behind the animals-registry rows and the cases-browser
/// text search (federfall-78b).
@riverpod
Future<Map<String, List<String>>> activeMarkingCodesByAnimal(Ref ref) async {
  final repo = await ref.watch(markingsRepositoryProvider.future);
  final activeMarkings = await repo.list(filter: 'is_active = true');
  final codesByAnimal = <String, List<String>>{};
  for (final m in activeMarkings) {
    final code = m.code;
    if (code != null && code.isNotEmpty) {
      (codesByAnimal[m.animal] ??= []).add(code);
    }
  }
  return codesByAnimal;
}

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

  // Resolve the animals behind matched markings, de-duplicating with name hits.
  final animalsById = {for (final a in byName) a.id: a};
  for (final id in byCode.map((m) => m.animal).toSet()) {
    if (!animalsById.containsKey(id)) {
      animalsById[id] = await animalsRepo.getOne(id);
    }
  }

  final matches = <ReidMatch>[];
  for (final animal in animalsById.values) {
    final markings = await markingsRepo.forAnimal(animal.id);
    matches.add(
      ReidMatch(
        animal: animal,
        markings: markings.where((m) => m.isActive).toList(),
      ),
    );
  }
  return matches;
}

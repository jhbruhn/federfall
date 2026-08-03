import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'animals_providers.g.dart';

/// One row of the animals registry (FED-7.5): the persistent animal identity
/// plus the codes of its currently-active markings (ring / chip / band).
@immutable
class AnimalListItem {
  const AnimalListItem({required this.animal, required this.codes});

  final Animal animal;

  /// Active marking codes carried by the animal, in record order.
  final List<String> codes;
}

/// The org's animals with their active marking codes, name-sorted. Animals are
/// org-wide readable, so this is the whole registry; filtering/search happens
/// client-side via [filterAnimals].
@riverpod
Future<List<AnimalListItem>> animalsRegistry(Ref ref) async {
  final animalsRepo = await ref.watch(animalsRepositoryProvider.future);
  final animals = await animalsRepo.list();
  final codesByAnimal = await ref.watch(
    activeMarkingCodesByAnimalProvider.future,
  );

  final items =
      [
        for (final a in animals)
          AnimalListItem(animal: a, codes: codesByAnimal[a.id] ?? const []),
      ]..sort((a, b) {
        final byName = (a.animal.name ?? '').toLowerCase().compareTo(
          (b.animal.name ?? '').toLowerCase(),
        );
        return byName != 0
            ? byName
            : a.animal.species.toLowerCase().compareTo(
                b.animal.species.toLowerCase(),
              );
      });
  return items;
}

/// Pure search over the registry by animal name or active marking code. Empty
/// query returns everything. Kept out of the widget so it can be unit-tested.
List<AnimalListItem> filterAnimals(List<AnimalListItem> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items.where((item) {
    final name = item.animal.name?.toLowerCase() ?? '';
    if (name.contains(q)) return true;
    return item.codes.any((c) => c.toLowerCase().contains(q));
  }).toList();
}

/// Thumbnail URL for an animal's header avatar, or null for the placeholder.
@riverpod
Future<Uri?> animalAvatarUrl(Ref ref, String animalId) {
  return _avatarUrl(ref, animalId, thumb: '200x200');
}

/// Full-resolution URL for an animal's photo, or null for the placeholder —
/// used by the full-screen viewer, where the 200x200 avatar thumbnail would
/// look blurry blown up.
@riverpod
Future<Uri?> animalAvatarFullUrl(Ref ref, String animalId) {
  return _avatarUrl(ref, animalId, thumb: null);
}

/// The avatar is `animals.photo` and nothing else (federfall-v1yh): the intake
/// route promotes the first admission photo onto the animal server-side, so
/// there is no case-scoped fallback to resolve — which is the point, since a
/// fallback made the portrait visible only to people on that case.
Future<Uri?> _avatarUrl(
  Ref ref,
  String animalId, {
  required String? thumb,
}) async {
  final animal = await ref.watch(animalByIdProvider(animalId).future);
  final photo = animal.photo;
  if (photo == null || photo.isEmpty) return null;

  // animals.photo is a Protected file field (FED-8.1), but the token is
  // appended at download time by ProtectedFileCacheManager, so the URL itself
  // stays token-free.
  final repo = await ref.watch(animalsRepositoryProvider.future);
  return repo.fileUrl(animalId, photo, thumb: thumb);
}

/// Every case summary for one animal, newest first, read from the org-wide
/// `case_summaries` view (FED-7.6).
@riverpod
Future<List<CaseSummary>> caseSummariesForAnimal(
  Ref ref,
  String animalId,
) async {
  final repo = await ref.watch(caseSummariesRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// One animal's full lifetime record (FED-7.6): identity, every marking, and
/// every case (newest-first) with the set of cases the user may open in full.
@immutable
class AnimalLifetime {
  const AnimalLifetime({
    required this.animal,
    required this.markings,
    required this.cases,
    required this.accessibleCaseIds,
  });

  final Animal animal;

  /// All markings (active + historic), newest first.
  final List<Marking> markings;

  /// Every case for the animal (summaries), newest first.
  final List<CaseSummary> cases;

  /// Ids of the cases the signed-in user can open in full; the rest render as
  /// non-tappable stubs.
  final Set<String> accessibleCaseIds;
}

/// Assembles an [AnimalLifetime]: the org-wide identity, markings and case
/// summaries, plus the access-scoped full cases used to decide which summaries
/// are tappable.
@riverpod
Future<AnimalLifetime> animalLifetime(Ref ref, String animalId) async {
  final animal = await ref.watch(animalByIdProvider(animalId).future);
  final markings = await ref.watch(markingsForAnimalProvider(animalId).future);
  final summaries = await ref.watch(
    caseSummariesForAnimalProvider(animalId).future,
  );
  final accessible = await ref.watch(casesForAnimalProvider(animalId).future);
  return AnimalLifetime(
    animal: animal,
    markings: markings,
    cases: summaries,
    accessibleCaseIds: {for (final c in accessible) c.id},
  );
}

/// "Name · Species", falling back to the species alone for an unnamed bird —
/// the one-line identity every picker, candidate list and summary card shows.
String animalTitle(Animal a) {
  final name = a.name;
  return name == null || name.isEmpty ? a.species : '$name · ${a.species}';
}

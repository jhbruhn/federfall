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
  final markingsRepo = await ref.watch(markingsRepositoryProvider.future);

  final animals = await animalsRepo.list();
  final activeMarkings = await markingsRepo.list(filter: 'is_active = true');

  final codesByAnimal = <String, List<String>>{};
  for (final m in activeMarkings) {
    final code = m.code;
    if (code != null && code.isNotEmpty) {
      (codesByAnimal[m.animal] ??= []).add(code);
    }
  }

  final items = [
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

/// Which stored file backs an animal's header avatar (ctw.7): either the
/// animal's own photo or a fallback case intake photo.
enum AvatarCollection { animals, cases }

/// A resolved avatar source: the [collection], owning [recordId] and [filename]
/// to build a file URL from.
@immutable
class AvatarSource {
  const AvatarSource({
    required this.collection,
    required this.recordId,
    required this.filename,
  });

  final AvatarCollection collection;
  final String recordId;
  final String filename;
}

/// Picks the header avatar source (ctw.7): the animal's own photo when set,
/// else the first intake photo of the most recent case that has one.
/// [casesNewestFirst] must be ordered newest-first. Returns null → placeholder.
/// Pure, so the fallback order is unit-tested without PocketBase.
AvatarSource? pickAvatarSource(Animal animal, List<Case> casesNewestFirst) {
  final photo = animal.photo;
  if (photo != null && photo.isNotEmpty) {
    return AvatarSource(
      collection: AvatarCollection.animals,
      recordId: animal.id,
      filename: photo,
    );
  }
  for (final c in casesNewestFirst) {
    if (c.intakePhotos.isNotEmpty) {
      return AvatarSource(
        collection: AvatarCollection.cases,
        recordId: c.id,
        filename: c.intakePhotos.first,
      );
    }
  }
  return null;
}

/// Thumbnail URL for an animal's header avatar, or null for the placeholder.
/// Resolves [pickAvatarSource] over the animal and its accessible cases.
@riverpod
Future<Uri?> animalAvatarUrl(Ref ref, String animalId) async {
  final animal = await ref.watch(animalByIdProvider(animalId).future);
  final cases = await ref.watch(casesForAnimalProvider(animalId).future);
  final source = pickAvatarSource(animal, cases);
  if (source == null) return null;

  switch (source.collection) {
    case AvatarCollection.animals:
      final repo = await ref.watch(animalsRepositoryProvider.future);
      return repo.fileUrl(source.recordId, source.filename, thumb: '200x200');
    case AvatarCollection.cases:
      final repo = await ref.watch(casesRepositoryProvider.future);
      return repo.fileUrl(source.recordId, source.filename, thumb: '200x200');
  }
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

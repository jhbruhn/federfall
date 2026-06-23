import 'package:federfall/data/repository_providers.dart';
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

import 'package:federfall/data/repository_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'animal_species_providers.g.dart';

/// The distinct species (animal kinds) the org has already recorded,
/// alphabetically — the suggestion source for the intake species field. Kept
/// alive: a small, slowly-growing vocabulary worth caching across the wizard.
@Riverpod(keepAlive: true)
Future<List<String>> animalSpecies(Ref ref) async {
  final repo = await ref.watch(animalSpeciesRepositoryProvider.future);
  return repo.all();
}

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cases_providers.g.dart';

/// A single case by id (case detail).
@riverpod
Future<Case> caseById(Ref ref, String id) async {
  final repo = await ref.watch(casesRepositoryProvider.future);
  return repo.getOne(id);
}

/// The animal (name + species) behind a case.
@riverpod
Future<Animal> animalById(Ref ref, String id) async {
  final repo = await ref.watch(animalsRepositoryProvider.future);
  return repo.getOne(id);
}

/// Every case for one animal (its admission history), newest first — used to
/// show prior-case history when re-identifying a returning bird (FED-4.10).
@riverpod
Future<List<Case>> casesForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(casesRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// The external finder linked to a case, by id (case detail).
@riverpod
Future<Finder> finderById(Ref ref, String id) async {
  final repo = await ref.watch(findersRepositoryProvider.future);
  return repo.getOne(id);
}

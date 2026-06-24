import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'aviaries_providers.g.dart';

/// All aviaries in the org (active and inactive), name-sorted (FED-6.1).
@riverpod
Future<List<Aviary>> aviaries(Ref ref) async {
  final repo = await ref.watch(aviariesRepositoryProvider.future);
  return repo.list(sort: 'name');
}

/// Active aviaries only — the placement picker (FED-4.12), name-sorted.
@riverpod
Future<List<Aviary>> activeAviaries(Ref ref) async {
  final repo = await ref.watch(aviariesRepositoryProvider.future);
  return repo.list(filter: 'active = true', sort: 'name');
}

/// A single aviary by id (aviary detail, FED-6.2).
@riverpod
Future<Aviary> aviaryById(Ref ref, String id) async {
  final repo = await ref.watch(aviariesRepositoryProvider.future);
  return repo.getOne(id);
}

/// The animals currently resident in an aviary (FED-6.2), name-sorted.
@riverpod
Future<List<Animal>> aviaryResidents(Ref ref, String aviaryId) async {
  final repo = await ref.watch(animalsRepositoryProvider.future);
  return repo.residentsOf(aviaryId);
}

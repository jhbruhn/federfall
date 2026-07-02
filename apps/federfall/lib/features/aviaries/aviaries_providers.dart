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

/// Current resident count per aviary id, in one animals query — the registry
/// list shows occupancy next to capacity so a full aviary is visible before
/// it's picked (federfall-kml). Aviaries without residents are absent.
@riverpod
Future<Map<String, int>> aviaryOccupancyCounts(Ref ref) async {
  final repo = await ref.watch(animalsRepositoryProvider.future);
  final residents = await repo.list(filter: 'current_aviary != ""');
  final counts = <String, int>{};
  for (final animal in residents) {
    final aviaryId = animal.currentAviary;
    if (aviaryId == null || aviaryId.isEmpty) continue;
    counts[aviaryId] = (counts[aviaryId] ?? 0) + 1;
  }
  return counts;
}

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'medication_routes_providers.g.dart';

/// The full medication-route code list, label-sorted. Used to populate the
/// route picker (active entries only) and to resolve a stored route id → its
/// label on medication tiles / the worklist (so a now-inactive entry still
/// resolves). Kept alive: a small, rarely-changing vocabulary resolved on every
/// medication tile, so it should be cached rather than refetched per mount.
@Riverpod(keepAlive: true)
Future<List<MedicationRoute>> medicationRoutes(Ref ref) async {
  final repo = await ref.watch(medicationRoutesRepositoryProvider.future);
  return repo.list(sort: 'label');
}

/// Medication-route code-list entries keyed by id, for label lookup.
@Riverpod(keepAlive: true)
Future<Map<String, MedicationRoute>> medicationRoutesById(Ref ref) async {
  final all = await ref.watch(medicationRoutesProvider.future);
  return {for (final r in all) r.id: r};
}

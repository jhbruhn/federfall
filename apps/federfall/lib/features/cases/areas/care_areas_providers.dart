import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'care_areas_providers.g.dart';

/// Every care area in the org (federfall-r67n) — a handful of rooms per carer,
/// so one small row set read whole, like the other code lists.
@riverpod
Future<List<CareArea>> careAreas(Ref ref) async {
  final repo = await ref.watch(careAreasRepositoryProvider.future);
  return await repo.all();
}

/// [careAreasProvider] keyed by id, for naming a case's area.
@riverpod
Future<Map<String, CareArea>> careAreasById(Ref ref) async {
  final areas = await ref.watch(careAreasProvider.future);
  return {for (final a in areas) a.id: a};
}

/// The signed-in user's own areas, in their order — what the management sheet
/// edits and what "my cases" is grouped by.
@riverpod
Future<List<CareArea>> myCareAreas(Ref ref) async {
  final me = await ref.watch(currentUserProvider.selectAsync((u) => u?.id));
  if (me == null) return const [];
  return areasOwnedBy(await ref.watch(careAreasProvider.future), me);
}

/// The areas [owner] keeps, in their own order. The name breaks a tie, so two
/// areas created before any reordering still come back the same way each time.
List<CareArea> areasOwnedBy(List<CareArea> areas, String owner) =>
    areas.where((a) => a.owner == owner).toList()..sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.name.compareTo(b.name);
    });

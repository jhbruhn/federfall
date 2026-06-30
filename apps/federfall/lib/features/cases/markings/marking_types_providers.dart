import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'marking_types_providers.g.dart';

/// The full marking-type code list, label-sorted. Used to populate the marking
/// picker (active entries only) and to resolve a stored type id → its label on
/// marking tiles / details (so a now-inactive entry still resolves).
@riverpod
Future<List<MarkingType>> markingTypes(Ref ref) async {
  final repo = await ref.watch(markingTypesRepositoryProvider.future);
  return repo.list(sort: 'label');
}

/// Marking-type code-list entries keyed by id, for label lookup.
@riverpod
Future<Map<String, MarkingType>> markingTypesById(Ref ref) async {
  final all = await ref.watch(markingTypesProvider.future);
  return {for (final t in all) t.id: t};
}

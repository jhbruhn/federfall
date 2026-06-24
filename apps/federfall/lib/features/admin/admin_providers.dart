import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'admin_providers.g.dart';

/// The org's full team roster (active and not), for the supervisor admin area
/// (UX Phase A). Active members first, then name-sorted.
@riverpod
Future<List<AppUser>> orgMembers(Ref ref) async {
  final repo = await ref.watch(usersRepositoryProvider.future);
  return repo.members();
}

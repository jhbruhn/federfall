import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'placements_providers.g.dart';

/// Placement / handoff history for a case, newest move first (FED-4.9).
@riverpod
Future<List<Placement>> placementsForCase(Ref ref, String caseId) async {
  final repo = await ref.watch(placementsRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// Active staff members of the org, name-sorted — the carer/handoff pickers.
@riverpod
Future<List<AppUser>> orgMembers(Ref ref) async {
  final repo = await ref.watch(usersRepositoryProvider.future);
  return repo.activeMembers();
}

/// Org members keyed by id, for resolving carer/from/to names on the timeline.
@riverpod
Future<Map<String, AppUser>> orgMembersById(Ref ref) async {
  final members = await ref.watch(orgMembersProvider.future);
  return {for (final m in members) m.id: m};
}

/// A short display name for a user: their name, else the email's local part.
String memberLabel(AppUser user) {
  final name = user.name;
  if (name != null && name.isNotEmpty) return name;
  final email = user.email;
  final at = email.indexOf('@');
  return at <= 0 ? email : email.substring(0, at);
}

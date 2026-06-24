import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'follow_ups_providers.g.dart';

/// Follow-ups (rechecks) for a case, soonest due first (cr3.4).
@riverpod
Future<List<FollowUp>> followUpsForCase(Ref ref, String caseId) async {
  final repo = await ref.watch(followUpsRepositoryProvider.future);
  return repo.forCase(caseId);
}

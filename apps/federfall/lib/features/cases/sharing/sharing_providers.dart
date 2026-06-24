import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sharing_providers.g.dart';

/// The opt-in shares granted on a case (FED-5.1), for the sharing sheet.
@riverpod
Future<List<CaseShare>> caseShares(Ref ref, String caseId) async {
  final repo = await ref.watch(caseSharesRepositoryProvider.future);
  return repo.forCase(caseId);
}

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'disposition_providers.g.dart';

/// Disposition history for a case, newest first (FED-4.11). Usually one final
/// outcome row; re-admission opens a new case rather than reopening this one.
@riverpod
Future<List<Disposition>> dispositionsForCase(Ref ref, String caseId) =>
    caseBundleList(ref, caseId, (b) => b.dispositions, () async {
      final repo = await ref.watch(dispositionsRepositoryProvider.future);
      return repo.forCase(caseId);
    });

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'exams_providers.g.dart';

/// Structured exams for a case, newest first (FED-4.8) — a timeline source.
@riverpod
Future<List<Exam>> examsForCase(Ref ref, String caseId) async {
  final repo = await ref.watch(examsRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// Every exam recorded for an animal across its life, newest first — the
/// lifetime roll-up shown on the animal detail (blp.5).
@riverpod
Future<List<Exam>> examsForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(examsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// Every by-system finding across the case's exams, fetched in ONE query and
/// grouped by exam id for the tiles to render under each exam (FED-4.8).
@riverpod
Future<Map<String, List<ExamFinding>>> examFindingsForCase(
  Ref ref,
  String caseId,
) async {
  final repo = await ref.watch(examFindingsRepositoryProvider.future);
  final all = await repo.forCase(caseId);
  final byExam = <String, List<ExamFinding>>{};
  for (final f in all) {
    (byExam[f.exam] ??= <ExamFinding>[]).add(f);
  }
  return byExam;
}

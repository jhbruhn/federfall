import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'microscopy_providers.g.dart';

/// Microscopy samples on a case, newest first — a timeline source.
@riverpod
Future<List<MicroscopySample>> microscopyForCase(Ref ref, String caseId) =>
    caseBundleList(ref, caseId, (b) => b.microscopySamples, () async {
      final repo = await ref.watch(microscopySamplesRepositoryProvider.future);
      return repo.forCase(caseId);
    });

/// Every graded finding across the case's samples, grouped by sample id for
/// the tiles to render under each one — the `examFindingsForCase` shape.
@riverpod
Future<Map<String, List<MicroscopyFinding>>> microscopyFindingsForCase(
  Ref ref,
  String caseId,
) async {
  final all = await caseBundleList(
    ref,
    caseId,
    (b) => b.microscopyFindings,
    () async {
      final repo = await ref.watch(
        microscopyFindingsRepositoryProvider.future,
      );
      return repo.forCase(caseId);
    },
  );
  final bySample = <String, List<MicroscopyFinding>>{};
  for (final f in all) {
    (bySample[f.sample] ??= <MicroscopyFinding>[]).add(f);
  }
  return bySample;
}

/// The whole finding vocabulary, in picker order.
///
/// Deliberately not `active()`: the sheet's picker offers only the live
/// entries, but a tile still has to NAME a term that has since been
/// deactivated, and a finding recorded under one keeps pointing at it.
@riverpod
Future<List<MicroscopyFindingType>> microscopyFindingTypes(Ref ref) async {
  final repo = await ref.watch(microscopyFindingTypesRepositoryProvider.future);
  return repo.codelist();
}

/// Vocabulary entries keyed by id, for the label lookup on a tile.
@riverpod
Future<Map<String, MicroscopyFindingType>> microscopyFindingTypesById(
  Ref ref,
) async {
  final all = await ref.watch(microscopyFindingTypesProvider.future);
  return {for (final t in all) t.id: t};
}

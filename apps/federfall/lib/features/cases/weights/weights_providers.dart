import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/number_format.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'weights_providers.g.dart';

/// Weight measurements for a case in chronological order (FED-4.4). Ascending
/// by measurement date so the same list feeds both the trend chart and — once
/// re-sorted — the case chronology.
@riverpod
Future<List<Weight>> weightsForCase(Ref ref, String caseId) =>
    caseBundleList(ref, caseId, (b) => b.weights, () async {
      final repo = await ref.watch(weightsRepositoryProvider.future);
      return repo.forCase(caseId);
    });

/// Every weight for an animal across its whole life (5yg.5), oldest first —
/// the life-long trend, independent of any single case.
@riverpod
Future<List<Weight>> weightsForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(weightsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// The newest measurement in [weights], or null when there is none.
///
/// Compares by measurement date, falling back to the record's creation date
/// the way the timeline does — and never just takes `.last`, because a
/// bundle-expanded list carries no sort guarantee and a dose derived from the
/// wrong weight is the failure this whole path exists to avoid.
Weight? latestWeight(List<Weight> weights) {
  Weight? newest;
  for (final w in weights) {
    final at = w.measuredAt ?? w.created;
    if (at == null) continue;
    final best = newest?.measuredAt ?? newest?.created;
    if (best == null || at.isAfter(best)) newest = w;
  }
  return newest;
}

/// Formats a weight in grams without trailing noise: `248 g`, or `248,5 g`
/// when the measurement carries a fractional part. The number follows the
/// active locale (see [formatNumber]); scales read out at most one decimal.
String formatWeightG(AppLocalizations l10n, double grams) =>
    '${formatNumber(l10n, grams, maxFractionDigits: 1)} g';

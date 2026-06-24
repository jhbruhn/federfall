import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'weights_providers.g.dart';

/// Weight measurements for a case in chronological order (FED-4.4). Ascending
/// by measurement date so the same list feeds both the trend chart and — once
/// re-sorted — the case chronology.
@riverpod
Future<List<Weight>> weightsForCase(Ref ref, String caseId) async {
  final repo = await ref.watch(weightsRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// Every weight for an animal across its whole life (5yg.5), oldest first —
/// the life-long trend, independent of any single case.
@riverpod
Future<List<Weight>> weightsForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(weightsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// Formats a weight in grams without trailing noise: `248 g`, or `248.5 g`
/// when the measurement carries a fractional part.
String formatWeightG(double grams) {
  final whole = grams == grams.roundToDouble();
  return '${whole ? grams.toStringAsFixed(0) : grams.toStringAsFixed(1)} g';
}

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'medications_providers.g.dart';

/// Prescriptions (medication plans) for a case, most recently started first.
@riverpod
Future<List<Medication>> medicationsForCase(Ref ref, String caseId) async {
  final repo = await ref.watch(medicationsRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// Doses administered on a case, most recent first (FED-4.6).
@riverpod
Future<List<MedicationAdministration>> administrationsForCase(
  Ref ref,
  String caseId,
) async {
  final repo =
      await ref.watch(medicationAdministrationsRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// Formats a dose and unit compactly: `0.3 ml`, `1 Tablette`, or `''` when no
/// dose is recorded. Drops a trailing `.0` on whole numbers.
String formatDose(double? dose, String? unit) {
  if (dose == null) return '';
  final n = dose == dose.roundToDouble()
      ? dose.toStringAsFixed(0)
      : dose.toString();
  final u = (unit == null || unit.isEmpty) ? '' : ' $unit';
  return '$n$u';
}

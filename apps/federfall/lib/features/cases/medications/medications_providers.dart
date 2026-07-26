import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/number_format.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'medications_providers.g.dart';

/// Prescriptions (medication plans) for a case, most recently started first.
@riverpod
Future<List<Medication>> medicationsForCase(Ref ref, String caseId) =>
    caseBundleList(ref, caseId, (b) => b.medications, () async {
      final repo = await ref.watch(medicationsRepositoryProvider.future);
      return repo.forCase(caseId);
    });

/// Doses administered on a case, most recent first (FED-4.6).
@riverpod
Future<List<MedicationAdministration>> administrationsForCase(
  Ref ref,
  String caseId,
) => caseBundleList(ref, caseId, (b) => b.administrations, () async {
  final repo = await ref.watch(
    medicationAdministrationsRepositoryProvider.future,
  );
  return repo.forCase(caseId);
});

/// Formats a dose and unit compactly: `0,3 ml`, `1 Tablette`, or `''` when no
/// dose is recorded. The number follows the active locale (see [formatNumber]),
/// so it matches the separator the carer types.
String formatDose(AppLocalizations l10n, double? dose, String? unit) {
  if (dose == null) return '';
  final u = (unit == null || unit.isEmpty) ? '' : ' $unit';
  return '${formatNumber(l10n, dose)}$u';
}

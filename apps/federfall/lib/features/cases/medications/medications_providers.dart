import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/number_format.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
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

/// One case the signed-in carer could also put on a course, with the bird it
/// is about — everything the group picker draws in a row.
@immutable
class PrescribableCase {
  const PrescribableCase({required this.caseRecord, this.animal});

  final Case caseRecord;
  final Animal? animal;

  /// The bird's name if it has one, else its species — the same fallback the
  /// batch-vaccination roster uses.
  String get label {
    final name = animal?.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    return animal?.species ?? '';
  }
}

/// The carer's other active cases, for prescribing one course to a group
/// (federfall-hqhg). [exceptCaseId] is the case the sheet was opened from —
/// always part of the batch, never a row to tick.
///
/// Scope is deliberately `active_carer = me`, the same question the worklist
/// asks (`forCarer` + the disposed filter, not a device-side narrowing of every
/// case the caller may see — federfall-trep). That is also exactly the set the
/// route will accept without a share or a supervisor role, so the picker cannot
/// offer a row the server then refuses — and a refusal fails the WHOLE batch.
///
/// A supervisor sees the cases they carry, not the org's: prescribing across
/// another carer's caseload stays a per-case act.
@riverpod
Future<List<PrescribableCase>> prescribableCases(
  Ref ref,
  String exceptCaseId,
) async {
  final me = await ref.watch(currentUserProvider.selectAsync((u) => u?.id));
  if (me == null) return const [];

  final (casesRepo, animalsRepo) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
  ).waitUnwrapped;

  final mine = await casesRepo.forCarer(me);
  final others = [
    for (final c in mine)
      if (c.id != exceptCaseId && c.status != CaseStatus.disposed) c,
  ];
  if (others.isEmpty) return const [];

  // One request for every bird, not one per row.
  final animals = await animalsRepo.byIds({for (final c in others) c.animal});
  final byId = {for (final a in animals) a.id: a};
  return [
    for (final c in others)
      PrescribableCase(caseRecord: c, animal: byId[c.animal]),
  ];
}

/// Formats a dose and unit compactly: `0,3 ml`, `1 Tablette`, or `''` when no
/// dose is recorded. The number follows the active locale (see [formatNumber]),
/// so it matches the separator the carer types.
String formatDose(AppLocalizations l10n, double? dose, String? unit) {
  if (dose == null) return '';
  final u = (unit == null || unit.isEmpty) ? '' : ' $unit';
  return '${formatNumber(l10n, dose)}$u';
}

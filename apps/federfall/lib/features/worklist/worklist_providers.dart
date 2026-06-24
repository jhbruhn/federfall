import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'worklist_providers.g.dart';

/// The signed-in carer's derived worklist (UX Phase D, cr3.1): medications due
/// and quarantines ending on the cases they are responsible for.
///
/// Scope is the carer's own active cases (`active_carer == me`, not disposed).
/// Prescriptions and doses are fetched per case — N is small (a carer's open
/// caseload) — then folded into the pure [buildWorklist]. Returns an empty list
/// when signed out.
@riverpod
Future<List<WorklistItem>> worklist(Ref ref) async {
  final me = (await ref.watch(currentUserProvider.future))?.id;
  if (me == null) return const [];

  final casesRepo = await ref.watch(casesRepositoryProvider.future);
  final allCases = await casesRepo.list(sort: '-created');
  final myActive = allCases
      .where((c) => c.activeCarer == me && c.status != CaseStatus.disposed)
      .toList();
  if (myActive.isEmpty) return const [];

  final medsRepo = await ref.watch(medicationsRepositoryProvider.future);
  final adminRepo = await ref.watch(
    medicationAdministrationsRepositoryProvider.future,
  );
  final activityRepo = await ref.watch(caseActivityRepositoryProvider.future);

  final medsByCase = await Future.wait(
    myActive.map((c) => medsRepo.forCase(c.id)),
  );
  final dosesByCase = await Future.wait(
    myActive.map((c) => adminRepo.forCase(c.id)),
  );
  final activity = await activityRepo.all();

  return buildWorklist(
    cases: myActive,
    medications: medsByCase.expand((m) => m).toList(),
    administrations: dosesByCase.expand((a) => a).toList(),
    lastActivityByCase: {for (final a in activity) a.id: a.lastActivity},
    now: DateTime.now(),
  );
}

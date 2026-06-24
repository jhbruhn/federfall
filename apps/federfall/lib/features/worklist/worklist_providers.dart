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
///
/// The per-source fetches are independent, so they are issued concurrently and
/// awaited together: one round-trip phase rather than five in series, which is
/// what made the dashboard's Today card lag behind the rest.
@riverpod
Future<List<WorklistItem>> worklist(Ref ref) async {
  final me = (await ref.watch(currentUserProvider.future))?.id;
  if (me == null) return const [];

  // Repositories all share the resolved client; resolve them together.
  final (
    casesRepo,
    medsRepo,
    adminRepo,
    activityRepo,
    animalsRepo,
    followUpsRepo,
  ) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(medicationsRepositoryProvider.future),
    ref.watch(medicationAdministrationsRepositoryProvider.future),
    ref.watch(caseActivityRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
    ref.watch(followUpsRepositoryProvider.future),
  ).wait;

  final allCases = await casesRepo.list(sort: '-created');
  final myActive = allCases
      .where((c) => c.activeCarer == me && c.status != CaseStatus.disposed)
      .toList();
  if (myActive.isEmpty) return const [];

  final animalIds = {for (final c in myActive) c.animal};

  // Every remaining read is independent — fire them all at once and await the
  // whole batch, instead of one `await` per group in series.
  final (medsByCase, dosesByCase, followUpsByCase, activity, animals) = await (
    Future.wait(myActive.map((c) => medsRepo.forCase(c.id))),
    Future.wait(myActive.map((c) => adminRepo.forCase(c.id))),
    Future.wait(myActive.map((c) => followUpsRepo.forCase(c.id))),
    activityRepo.all(),
    Future.wait(animalIds.map(animalsRepo.getOne)),
  ).wait;

  return buildWorklist(
    cases: myActive,
    medications: medsByCase.expand((m) => m).toList(),
    administrations: dosesByCase.expand((a) => a).toList(),
    followUps: followUpsByCase.expand((f) => f).toList(),
    lastActivityByCase: {for (final a in activity) a.id: a.lastActivity},
    animalNameById: {for (final a in animals) a.id: a.name},
    now: DateTime.now(),
  );
}

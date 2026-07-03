import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/sharing/sharing_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cases_providers.g.dart';

/// The case detail's whole data set — case, animal, finder and all twelve
/// timeline sources — in ONE request (federfall-kh0u). Every per-case provider
/// derives from this, so opening a case costs a single round trip instead of
/// ~17, and a realtime event refetches once instead of per collection.
///
/// This is the ONLY provider to invalidate after a case-scoped write or
/// realtime event: invalidating a derived provider merely re-reads the cached
/// bundle.
@riverpod
Future<CaseBundle> caseBundle(Ref ref, String caseId) async {
  final repo = await ref.watch(casesRepositoryProvider.future);
  return repo.bundle(caseId);
}

/// A single case by id (case detail) — served from the [caseBundle], so the
/// header and the timeline share one fetch. Refresh by invalidating
/// [caseBundleProvider], not this.
@riverpod
Future<Case> caseById(Ref ref, String id) async {
  final bundle = await ref.watch(caseBundleProvider(id).future);
  return bundle.medicalCase;
}

/// Serves one timeline list off the [caseBundle]. PocketBase truncates each
/// expanded relation at [pbExpandListCap]; a list of exactly that length may
/// be incomplete, so only then does [fetchAll] re-run the paged
/// per-collection query. The per-case leaf providers are thin wrappers over
/// this, keeping the fallback rule in one place.
Future<List<T>> caseBundleList<T>(
  Ref ref,
  String caseId,
  List<T> Function(CaseBundle) pick,
  Future<List<T>> Function() fetchAll,
) async {
  final bundle = await ref.watch(caseBundleProvider(caseId).future);
  final items = pick(bundle);
  if (items.length < pbExpandListCap) return items;
  return fetchAll();
}

/// Whether the current user may write to case [caseId] (edit it and its
/// timeline) — the single source of truth for gating every case write control,
/// mirroring the server rules via [caseEditableBy]. Active carers and
/// supervisors resolve without fetching shares; only a non-carer non-supervisor
/// viewer pays for the share lookup that could still grant `edit` access.
@riverpod
Future<bool> canEditCase(Ref ref, String caseId) async {
  final me = await ref.watch(currentUserProvider.future);
  if (me == null) return false;
  if (me.role == UserRole.supervisor) return true;
  final medicalCase = await ref.watch(caseByIdProvider(caseId).future);
  if (medicalCase.activeCarer == me.id) return true;
  final shares = await ref.watch(caseSharesProvider(caseId).future);
  return caseEditableBy(medicalCase, me, shares);
}

/// The animal (name + species) behind a case.
@riverpod
Future<Animal> animalById(Ref ref, String id) async {
  final repo = await ref.watch(animalsRepositoryProvider.future);
  return repo.getOne(id);
}

/// Every case for one animal (its admission history), newest first — used to
/// show prior-case history when re-identifying a returning bird (FED-4.10).
@riverpod
Future<List<Case>> casesForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(casesRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// The external finder linked to a case, by id (case detail).
@riverpod
Future<Finder> finderById(Ref ref, String id) async {
  final repo = await ref.watch(findersRepositoryProvider.future);
  return repo.getOne(id);
}

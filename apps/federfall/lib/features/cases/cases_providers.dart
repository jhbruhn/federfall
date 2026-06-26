import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/sharing/sharing_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cases_providers.g.dart';

/// A single case by id (case detail).
@riverpod
Future<Case> caseById(Ref ref, String id) async {
  final repo = await ref.watch(casesRepositoryProvider.future);
  return repo.getOne(id);
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

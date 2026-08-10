/// Custody — who currently holds a bird — for the UI (federfall-q7ks.6).
///
/// Since 1700000077/78/79 the server refuses a write about a bird the caller
/// does not hold, so every affordance that writes one has to be gated on the
/// same predicate; the alternative is an edit button that 403s. The predicate
/// itself is [animalWritableBy] / [animalAdmissibleBy] in `core/auth/roles.dart`
/// (one mirror of the rules, unit-tested there); this file is only how the app
/// gets the four facts they need.
///
/// **Resolved per animal, never per row.** Custody needs the bird's open case
/// and its enclosure's keeper, which the animals registry and the aviary flock
/// list do not have — and both are cursor-paged feeds where a per-row lookup
/// would be exactly the N+1 federfall-trep forbids. That is not a problem to
/// solve, it is a reason those two screens must not ask: they are pure
/// navigation, with no write control on a row. So the gate lives on the screens
/// that show ONE bird, where the inputs are already loaded, and the two feeds
/// stay one request per page.
///
/// Cost for a carer viewing one bird: the animal and its case summaries are
/// already watched by `animalLifetime`, leaving the enclosure (only when
/// housed) and [myEditSharedCaseIds] (once per session, whatever the bird). A
/// coordinator or supervisor overrides every branch and so pays nothing at all.
library;

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'custody_providers.g.dart';

/// The cases the signed-in user holds an `edit` share on, as case ids.
///
/// One user-wide query rather than one per case: the share branch has to be
/// answerable for a bird whose cases the asker cannot read, and a lifetime
/// record holds arbitrarily many of them. Read shares are excluded — they grant
/// no custody, which is the distinction 1700000010's correlation note exists to
/// keep honest.
@riverpod
Future<Set<String>> myEditSharedCaseIds(Ref ref) async {
  final meId = await ref.watch(currentUserProvider.selectAsync((u) => u?.id));
  if (meId == null) return const {};
  final repo = await ref.watch(caseSharesRepositoryProvider.future);
  final shares = await repo.editSharedWith(meId);
  return {for (final share in shares) share.caseId};
}

/// What the signed-in user may do about one bird, given who holds it.
@immutable
class AnimalCustody {
  const AnimalCustody({required this.canWrite, required this.canOpenCase});

  /// Neither — the resolved answer for a signed-out user.
  static const none = AnimalCustody(canWrite: false, canOpenCase: false);

  /// May edit the identity and its animal-scoped rows ([animalWritableBy]).
  final bool canWrite;

  /// May admit the bird on a new case ([animalAdmissibleBy]).
  final bool canOpenCase;
}

/// Resolves custody of [animalId] for the signed-in user.
@riverpod
Future<AnimalCustody> animalCustody(Ref ref, String animalId) async {
  // The whole user, as `canEditCase` takes it and for the same reason: AppUser
  // is `freezed`, so the identical user a token refresh re-emits compares equal
  // and nothing recomputes (federfall-bpw6).
  final me = await ref.watch(currentUserProvider.selectAsync((u) => u));
  if (me == null) return AnimalCustody.none;
  // A blanket override, so these two roles resolve without a single request.
  if (me.role == UserRole.coordinator || me.role == UserRole.supervisor) {
    return const AnimalCustody(canWrite: true, canOpenCase: true);
  }

  final animal = await ref.watch(animalByIdProvider(animalId).future);
  final cases = await ref.watch(
    caseSummariesForAnimalProvider(animalId).future,
  );
  final shared = await ref.watch(myEditSharedCaseIdsProvider.future);
  final aviary = await _enclosureOf(ref, animal.currentAviary);

  return AnimalCustody(
    canWrite: animalWritableBy(
      animal,
      me,
      aviary: aviary,
      cases: cases,
      editSharedCaseIds: shared,
    ),
    canOpenCase: animalAdmissibleBy(
      animal,
      me,
      aviary: aviary,
      cases: cases,
      editSharedCaseIds: shared,
    ),
  );
}

/// Whether the signed-in user may write about [animalId] — the one line every
/// animal write control watches, mirroring `canEditCase`'s shape.
///
/// A control reads this as `.value ?? false`, so an unresolved or failed
/// custody state offers nothing rather than offering a 403.
@riverpod
Future<bool> canWriteAnimal(Ref ref, String animalId) async {
  final custody = await ref.watch(animalCustodyProvider(animalId).future);
  return custody.canWrite;
}

/// Whether the signed-in user may open a new case on [animalId].
@riverpod
Future<bool> canOpenCaseOnAnimal(Ref ref, String animalId) async {
  final custody = await ref.watch(animalCustodyProvider(animalId).future);
  return custody.canOpenCase;
}

/// The bird's enclosure, or null when it has none.
///
/// A read failure resolves to null rather than propagating: a dangling or
/// unreadable enclosure must not take the case branch of custody down with it,
/// which is the same tolerance `lib_custody.js`'s `holds()` has. It cannot make
/// a resident read as a bird at large either — [animalAdmissibleBy] takes
/// "housed" off the animal, not off this.
Future<Aviary?> _enclosureOf(Ref ref, String? aviaryId) async {
  if (aviaryId == null || aviaryId.isEmpty) return null;
  try {
    return await ref.watch(aviaryByIdProvider(aviaryId).future);
  } on Object catch (_) {
    return null;
  }
}

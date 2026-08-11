/// Patenschaften on aviary residents (federfall-5s5j) — the reads, and the one
/// predicate that decides whether they are shown at all.
///
/// The access boundary is the server's — 1700000085's rule resolves it live
/// through `animal.current_aviary.keeper` — so nothing here filters PII by
/// viewer. What [canReadSponsorships] gates is whether the app ASKS: a keeper
/// of another enclosure gets an empty list from the server either way, and
/// rendering an empty „Patenschaften" card at them would announce that the
/// bird has sponsors without showing any.
library;

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sponsorship_providers.g.dart';

/// Every patronage on [animalId], newest arrangement first.
@riverpod
Future<List<Sponsorship>> sponsorshipsForAnimal(
  Ref ref,
  String animalId,
) async {
  final repo = await ref.watch(sponsorshipsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// How many patronages [animalId] carries — a COUNT, never a name.
///
/// This is what the disposition sheet's transfer warning reads: it has to say
/// how much personal data is about to change hands, and it must be able to say
/// it without the mover reading a single sponsor's details. (They usually may:
/// moving a bird already requires custody. But the sentence has no business
/// depending on that.)
@riverpod
Future<int> sponsorshipCountForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(sponsorshipsRepositoryProvider.future);
  return repo.countForAnimal(animalId);
}

/// What the signed-in user may do about [animalId]'s patronages.
///
/// Both answers come from the bird's CURRENT enclosure, so they change on
/// their own when it moves — which is the whole design (there is no aviary
/// snapshot on the row to keep in step).
@riverpod
Future<SponsorshipAccess> sponsorshipAccess(Ref ref, String animalId) async {
  // The whole user rather than the role, as `animalCustody` takes it and for
  // the same reason: AppUser is freezed, so the identical user a token refresh
  // re-emits compares equal and nothing recomputes (federfall-bpw6).
  final me = await ref.watch(currentUserProvider.selectAsync((u) => u));
  if (me == null) return SponsorshipAccess.none;
  final animal = await ref.watch(animalByIdProvider(animalId).future);
  final aviary = await _enclosureOf(ref, animal.currentAviary);
  return SponsorshipAccess(
    canRead: sponsorshipsReadableBy(aviary, me),
    canWrite: sponsorshipWritableBy(aviary, me),
  );
}

/// Whether the signed-in user may see [animalId]'s patronages at all.
///
/// Read as `.value ?? false`, so an unresolved or failed state shows nothing
/// rather than briefly showing PII to whoever is looking.
@riverpod
Future<bool> canReadSponsorships(Ref ref, String animalId) async {
  final access = await ref.watch(sponsorshipAccessProvider(animalId).future);
  return access.canRead;
}

/// Ends [sponsorship] now: writes this instant as its `ended_at`.
///
/// The one-tap counterpart to the edit form's date field, which stays the way
/// to record an end that was NOT today (or to take one back — clearing the date
/// makes the patronage run again, which is why this needs no undo of its own).
///
/// Nothing else changes, and that is the point: an ended patronage is never
/// scrubbed (federfall-5s5j.4). A donation that produced a
/// Zuwendungsbestätigung falls under §147 AO / §257 HGB and the receipt is
/// worthless without the donor's name and address — so ending a patronage is a
/// date, never a deletion.
///
/// The instant rather than local midnight, matching what the form writes for a
/// patronage started today: midnight in CEST is the previous day in UTC, and
/// `formatLocalDate` would then print yesterday.
Future<void> endSponsorship(WidgetRef ref, Sponsorship sponsorship) async {
  final repo = await ref.read(sponsorshipsRepositoryProvider.future);
  await repo.update(sponsorship.id, {
    'ended_at': DateTime.now().toUtc().toIso8601String(),
  });
  // The animal-scoped reads only. The overview's own feed and totals are
  // refreshed by the screen that opened the sheet, which keeps this file clear
  // of an import back into the feature that imports it.
  final animalId = sponsorship.animal;
  if (animalId.isEmpty) return;
  ref
    ..invalidate(sponsorshipsForAnimalProvider(animalId))
    ..invalidate(sponsorshipCountForAnimalProvider(animalId));
}

/// Read and write access to one bird's patronages.
class SponsorshipAccess {
  const SponsorshipAccess({required this.canRead, required this.canWrite});

  /// Neither — the resolved answer for a signed-out user.
  static const none = SponsorshipAccess(canRead: false, canWrite: false);

  /// May see them ([sponsorshipsReadableBy]).
  final bool canRead;

  /// May record and edit them ([sponsorshipWritableBy]) — which additionally
  /// requires that the bird still lives in an enclosure.
  final bool canWrite;
}

/// The bird's enclosure, or null when it has none.
///
/// A read failure resolves to null rather than propagating, the same tolerance
/// `custody_providers.dart` has: an unreadable enclosure must leave the section
/// hidden, not turn the screen into an error state.
Future<Aviary?> _enclosureOf(Ref ref, String? aviaryId) async {
  if (aviaryId == null || aviaryId.isEmpty) return null;
  try {
    return await ref.watch(aviaryByIdProvider(aviaryId).future);
  } on Object catch (_) {
    return null;
  }
}

import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'animals_providers.g.dart';

/// One row of the animals registry (FED-7.5): the persistent animal identity
/// plus the codes of its currently-active markings (ring / chip / band).
@immutable
class AnimalListItem {
  const AnimalListItem({required this.animal, required this.codes});

  final Animal animal;

  /// Active marking codes carried by the animal, in record order.
  final List<String> codes;
}

/// What the registry currently shows for one search term.
///
/// Mirrors the case browser's `CaseBrowseState` and the audit feed's state,
/// down to why [pageError] lives here rather than being thrown: the only
/// caller is a scroll listener, which cannot await (federfall-ia9n).
@immutable
class AnimalRegistryState {
  const AnimalRegistryState({
    this.items = const [],
    this.cursor,
    this.hasMore = false,
    this.loadingMore = false,
    this.pageError,
  });

  final List<AnimalListItem> items;

  /// Where the next page resumes from — see [PbReadOnlyRepository.page].
  final PbCursor? cursor;
  final bool hasMore;

  /// A page is in flight. Separate from the provider's own AsyncLoading, which
  /// belongs to the FIRST page: appending must not blank the list on screen.
  final bool loadingMore;
  final Object? pageError;
}

/// The animals registry for [search], name-sorted, a page at a time
/// (federfall-trep).
///
/// The search matches the same two things it always did — the animal's name
/// and the codes of its markings — but the server does the matching, so the
/// device holds the rows it draws instead of the org's whole animal list plus
/// every active marking in it.
@riverpod
class AnimalRegistryFeed extends _$AnimalRegistryFeed {
  @override
  Future<AnimalRegistryState> build(String search) async {
    final (animalsRepo, markingsRepo) = await (
      ref.watch(animalsRepositoryProvider.future),
      ref.watch(markingsRepositoryProvider.future),
    ).waitUnwrapped;
    final page = await _load(animalsRepo, markingsRepo, after: null);
    return AnimalRegistryState(
      items: page.items,
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }

  /// Appends the next page. Safe to call repeatedly — a no-op while a page is
  /// in flight, once the registry is exhausted, or after a page failed.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.pageError != null) {
      return;
    }
    await _appendPage(current);
  }

  /// Tries the page that failed again, from the same cursor.
  Future<void> retryPage() async {
    final current = state.value;
    if (current == null || current.pageError == null) return;
    await _appendPage(current);
  }

  Future<void> _appendPage(AnimalRegistryState current) async {
    state = AsyncData(
      AnimalRegistryState(
        items: current.items,
        cursor: current.cursor,
        hasMore: current.hasMore,
        loadingMore: true,
      ),
    );
    try {
      final (animalsRepo, markingsRepo) = await (
        ref.read(animalsRepositoryProvider.future),
        ref.read(markingsRepositoryProvider.future),
      ).waitUnwrapped;
      final next = await _load(
        animalsRepo,
        markingsRepo,
        after: current.cursor,
      );
      state = AsyncData(
        AnimalRegistryState(
          items: [...current.items, ...next.items],
          cursor: next.cursor,
          hasMore: next.hasMore,
        ),
      );
    } on Object catch (error) {
      // Keep what is already on screen, and keep the cursor so the retry
      // resumes exactly where this attempt did — no gap, no duplicates.
      state = AsyncData(
        AnimalRegistryState(
          items: current.items,
          cursor: current.cursor,
          hasMore: current.hasMore,
          pageError: error,
        ),
      );
    }
  }

  /// One page of animals, then the active markings of just those animals.
  ///
  /// The page size is the repository's own default — comfortably more than one
  /// screenful, so the common case is a single round trip and the scroll
  /// listener never fires.
  Future<AnimalRegistryState> _load(
    PbAnimalsRepository animalsRepo,
    PbMarkingsRepository markingsRepo, {
    required PbCursor? after,
  }) async {
    final page = await animalsRepo.browse(text: search, after: after);
    final codes = <String, List<String>>{};
    for (final m in await markingsRepo.activeByAnimals(
      page.items.map((a) => a.id),
    )) {
      final code = m.code;
      if (code != null && code.isNotEmpty) (codes[m.animal] ??= []).add(code);
    }
    return AnimalRegistryState(
      items: [
        for (final a in page.items)
          AnimalListItem(animal: a, codes: codes[a.id] ?? const []),
      ],
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }
}

/// Thumbnail URL for an animal's header avatar, or null for the placeholder.
@riverpod
Future<Uri?> animalAvatarUrl(Ref ref, String animalId) {
  return _avatarUrl(ref, animalId, thumb: '200x200');
}

/// Full-resolution URL for an animal's photo, or null for the placeholder —
/// used by the full-screen viewer, where the 200x200 avatar thumbnail would
/// look blurry blown up.
@riverpod
Future<Uri?> animalAvatarFullUrl(Ref ref, String animalId) {
  return _avatarUrl(ref, animalId, thumb: null);
}

/// The avatar is `animals.photo` and nothing else (federfall-v1yh): the intake
/// route promotes the first admission photo onto the animal server-side, so
/// there is no case-scoped fallback to resolve — which is the point, since a
/// fallback made the portrait visible only to people on that case.
Future<Uri?> _avatarUrl(
  Ref ref,
  String animalId, {
  required String? thumb,
}) async {
  final animal = await ref.watch(animalByIdProvider(animalId).future);
  final photo = animal.photo;
  if (photo == null || photo.isEmpty) return null;

  // animals.photo is a Protected file field (FED-8.1), but the token is
  // appended at download time by ProtectedFileCacheManager, so the URL itself
  // stays token-free.
  final repo = await ref.watch(animalsRepositoryProvider.future);
  return repo.fileUrl(animalId, photo, thumb: thumb);
}

/// Every case summary for one animal, newest first, read from the org-wide
/// `case_summaries` view (FED-7.6).
@riverpod
Future<List<CaseSummary>> caseSummariesForAnimal(
  Ref ref,
  String animalId,
) async {
  final repo = await ref.watch(caseSummariesRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// One animal's full lifetime record (FED-7.6): identity, every marking, and
/// every case (newest-first) with the set of cases the user may open in full.
@immutable
class AnimalLifetime {
  const AnimalLifetime({
    required this.animal,
    required this.markings,
    required this.cases,
    required this.accessibleCaseIds,
  });

  final Animal animal;

  /// All markings (active + historic), newest first.
  final List<Marking> markings;

  /// Every case for the animal (summaries), newest first.
  final List<CaseSummary> cases;

  /// Ids of the cases the signed-in user can open in full; the rest render as
  /// non-tappable stubs.
  final Set<String> accessibleCaseIds;
}

/// Assembles an [AnimalLifetime]: the org-wide identity, markings and case
/// summaries, plus the access-scoped full cases used to decide which summaries
/// are tappable.
@riverpod
Future<AnimalLifetime> animalLifetime(Ref ref, String animalId) async {
  final animal = await ref.watch(animalByIdProvider(animalId).future);
  final markings = await ref.watch(markingsForAnimalProvider(animalId).future);
  final summaries = await ref.watch(
    caseSummariesForAnimalProvider(animalId).future,
  );
  final accessible = await ref.watch(casesForAnimalProvider(animalId).future);
  return AnimalLifetime(
    animal: animal,
    markings: markings,
    cases: summaries,
    accessibleCaseIds: {for (final c in accessible) c.id},
  );
}

/// "Name · Species", falling back to the species alone for an unnamed bird —
/// the one-line identity every picker, candidate list and summary card shows.
String animalTitle(Animal a) {
  final name = a.name;
  return name == null || name.isEmpty ? a.species : '$name · ${a.species}';
}

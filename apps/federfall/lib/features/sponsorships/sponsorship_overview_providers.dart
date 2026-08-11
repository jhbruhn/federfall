import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sponsorship_overview_providers.g.dart';

/// One row of the patronage overview: the arrangement, and the bird it is for.
@immutable
class SponsorshipRow {
  const SponsorshipRow({required this.sponsorship, this.animal});

  final Sponsorship sponsorship;

  /// The sponsored bird, or null when the row is an ORPHAN — its animal was
  /// deleted (`sponsorships.animal` deliberately does not cascade, 1700000085)
  /// or could not be read. Such rows are rendered with the bird slot empty
  /// rather than hidden: they are the ones most likely to need attention, and
  /// they are why this screen exists for coordination in the first place.
  final Animal? animal;
}

/// What the overview currently shows for one query.
///
/// The shape the audit feed and the animals registry use, down to why
/// [pageError] lives here rather than being thrown: the only caller is a scroll
/// listener, which cannot await (federfall-ia9n).
@immutable
class SponsorshipOverviewState {
  const SponsorshipOverviewState({
    this.rows = const [],
    this.cursor,
    this.hasMore = false,
    this.loadingMore = false,
    this.pageError,
  });

  final List<SponsorshipRow> rows;

  /// Where the next page resumes from — see [PbReadOnlyRepository.page].
  final PbCursor? cursor;
  final bool hasMore;

  /// A page is in flight. Separate from the provider's own AsyncLoading, which
  /// belongs to the FIRST page: appending must not blank the list on screen.
  final bool loadingMore;
  final Object? pageError;
}

/// The org's patronages for [query], a page at a time (federfall-ys7z).
///
/// Coordinators and supervisors only, by the server's own read rule
/// (1700000085's `COORD_SUP` branch): a keeper reaching this would get their
/// own residents' rows, which is not what a screen headed „alle
/// Patenschaften" promises — hence the route gate as well.
///
/// Server-side filtered and cursor-paged per federfall-trep. Nothing here
/// filters by viewer: the access boundary is the server's, and a client-side
/// scope over PII would be a second, weaker copy of it.
@riverpod
class SponsorshipOverviewFeed extends _$SponsorshipOverviewFeed {
  @override
  Future<SponsorshipOverviewState> build(SponsorshipQuery query) =>
      _load(after: null);

  /// Appends the next page. Safe to call repeatedly — a no-op while a page is
  /// in flight, once the list is exhausted, or after a page failed, so a scroll
  /// listener can fire it as often as it likes.
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

  Future<void> _appendPage(SponsorshipOverviewState current) async {
    state = AsyncData(
      SponsorshipOverviewState(
        rows: current.rows,
        cursor: current.cursor,
        hasMore: current.hasMore,
        loadingMore: true,
      ),
    );
    try {
      final next = await _load(after: current.cursor);
      state = AsyncData(
        SponsorshipOverviewState(
          rows: [...current.rows, ...next.rows],
          cursor: next.cursor,
          hasMore: next.hasMore,
        ),
      );
    } on Object catch (error) {
      // Keep what is already on screen, and keep the cursor so the retry
      // resumes exactly where this attempt did — no gap, no duplicates.
      state = AsyncData(
        SponsorshipOverviewState(
          rows: current.rows,
          cursor: current.cursor,
          hasMore: current.hasMore,
          pageError: error,
        ),
      );
    }
  }

  /// One page of patronages, then the birds of just those rows.
  ///
  /// Two requests rather than an `expand`, the shape the animals registry uses
  /// for its marking codes: the page is the authority on WHICH rows, and the
  /// second read is a plain by-ids lookup over the ids it returned. An id that
  /// comes back with no animal is an orphan and keeps its row.
  Future<SponsorshipOverviewState> _load({required PbCursor? after}) async {
    final repo = await ref.read(sponsorshipsRepositoryProvider.future);
    final page = await repo.browse(query: query, after: after);

    final animalIds = page.items
        .map((s) => s.animal)
        .where((id) => id.isNotEmpty)
        .toSet();
    final byId = <String, Animal>{};
    if (animalIds.isNotEmpty) {
      final animalsRepo = await ref.read(animalsRepositoryProvider.future);
      for (final a in await animalsRepo.byIds(animalIds)) {
        byId[a.id] = a;
      }
    }

    return SponsorshipOverviewState(
      rows: [
        for (final s in page.items)
          SponsorshipRow(sponsorship: s, animal: byId[s.animal]),
      ],
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }
}

/// What the org's patronages currently come to (federfall-ys7z).
///
/// Read off `GET /api/federfall/stats`, because the sum cannot be computed
/// here: federfall-trep forbids reading a collection to aggregate it on the
/// device, and federfall-nmwi moved every aggregate server-side. The block
/// it returns is a STANDING figure — the selected reporting period has no
/// bearing on what is being given right now.
///
/// It rides on the statistics request for the year in progress rather than
/// asking for its own: that route computes the whole payload from one read of
/// the org's rows whatever period is asked for, and the year in progress is the
/// statistics screen's own default — so a coordinator who opens the dashboard
/// and then the statistics screen pays for one request, not two.
@riverpod
Future<SponsorshipTotals> sponsorshipTotals(Ref ref) async {
  final stats = await ref.watch(
    statisticsProvider(year: DateTime.now().year).future,
  );
  return stats.sponsorships;
}

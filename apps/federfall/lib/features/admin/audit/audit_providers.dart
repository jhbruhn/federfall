import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'audit_providers.g.dart';

/// What the audit feed currently shows.
///
/// Constructed explicitly rather than through a `copyWith`: these fields are
/// not independently optional — a cursor belongs to the page it came from,
/// and a `copyWith` unable to express "no cursor" (`cursor ?? this.cursor`)
/// was a trap waiting for the first caller who needed to clear one.
@immutable
class AuditFeedState {
  const AuditFeedState({
    this.events = const [],
    this.cursor,
    this.hasMore = true,
    this.loadingMore = false,
    this.pageError,
  });

  final List<AuditEvent> events;

  /// Where the next page resumes from — see [PbReadOnlyRepository.page] on why
  /// this is a cursor and not a page number.
  final PbCursor? cursor;
  final bool hasMore;

  /// A page is in flight. Separate from the provider's own AsyncLoading, which
  /// belongs to the FIRST page: appending must not blank the list already on
  /// screen.
  final bool loadingMore;

  /// Why the last attempt to append a page failed, or null if none did.
  ///
  /// Kept in the state rather than thrown: the only caller is a scroll
  /// listener, which cannot await anything, so a thrown error became an
  /// unhandled zone error and the supervisor saw the spinner stop and nothing
  /// else (federfall-ia9n). The screen turns this into a retry row.
  final Object? pageError;
}

/// The audit feed for [query], loaded a page at a time.
///
/// Keyed on the query, so changing a filter builds a new feed from the top
/// rather than mixing pages that answered different questions.
@riverpod
class AuditFeed extends _$AuditFeed {
  @override
  Future<AuditFeedState> build(AuditQuery query) async {
    final repo = await ref.watch(auditEventsRepositoryProvider.future);
    final page = await repo.search(query: query);
    return AuditFeedState(
      events: page.items,
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }

  /// Appends the next page. Safe to call repeatedly — it is a no-op while a
  /// page is in flight, once the feed is exhausted, or after a page failed, so
  /// a scroll listener can fire it as often as it likes.
  ///
  /// A failure after [retryPage] would otherwise auto-retry against a server
  /// that is down for as long as the supervisor keeps the list at the bottom,
  /// so recovery is an explicit act.
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

  Future<void> _appendPage(AuditFeedState current) async {
    state = AsyncData(
      AuditFeedState(
        events: current.events,
        cursor: current.cursor,
        hasMore: current.hasMore,
        loadingMore: true,
      ),
    );
    try {
      final repo = await ref.read(auditEventsRepositoryProvider.future);
      final next = await repo.search(query: query, after: current.cursor);
      state = AsyncData(
        AuditFeedState(
          events: [...current.events, ...next.items],
          cursor: next.cursor,
          hasMore: next.hasMore,
        ),
      );
    } on Object catch (error) {
      // Keep what is already on screen: a failed page is not a reason to throw
      // away the rows the supervisor is reading. The cursor is kept too, so the
      // retry resumes exactly where this attempt did — no gap, no duplicates.
      state = AsyncData(
        AuditFeedState(
          events: current.events,
          cursor: current.cursor,
          hasMore: current.hasMore,
          pageError: error,
        ),
      );
    }
  }
}

/// Everything that happened on one case, for the activity section on the case
/// detail. A thin alias over [AuditFeed] so both surfaces page identically.
@riverpod
Future<List<AuditEvent>> caseActivityLog(Ref ref, String caseId) async {
  final repo = await ref.watch(auditEventsRepositoryProvider.future);
  final page = await repo.forCase(caseId, perPage: 25);
  return page.items;
}

/// The rest of what one action wrote — the sibling rows sharing a
/// `request_id`, which the detail sheet shows under the event being read.
///
/// One human act can produce several rows (an intake writes the animal, the
/// case and the first weight), and until this was read back the correlation id
/// the emitter has always recorded had nowhere to surface.
@riverpod
Future<List<AuditEvent>> auditRequestSiblings(
  Ref ref,
  String requestId,
) async {
  if (requestId.isEmpty) return const [];
  final repo = await ref.watch(auditEventsRepositoryProvider.future);
  return repo.forRequest(requestId);
}

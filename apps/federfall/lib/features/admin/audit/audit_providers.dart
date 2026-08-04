import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'audit_providers.g.dart';

/// What the audit feed currently shows.
@immutable
class AuditFeedState {
  const AuditFeedState({
    this.events = const [],
    this.cursor,
    this.hasMore = true,
    this.loadingMore = false,
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

  AuditFeedState copyWith({
    List<AuditEvent>? events,
    PbCursor? cursor,
    bool? hasMore,
    bool? loadingMore,
  }) => AuditFeedState(
    events: events ?? this.events,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
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
  /// page is in flight or once the feed is exhausted, so a scroll listener can
  /// fire it as often as it likes.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));
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
    } catch (error, stack) {
      // Keep what is already on screen: a failed page is not a reason to throw
      // away the rows the supervisor is reading. The error surfaces once, and
      // pulling to refresh or scrolling again retries.
      state = AsyncData(current.copyWith(loadingMore: false));
      Error.throwWithStackTrace(error, stack);
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

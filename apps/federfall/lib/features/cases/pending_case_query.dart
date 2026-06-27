import 'package:federfall/features/cases/cases_browser.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pending_case_query.g.dart';

/// A case filter handed from a dashboard KPI to the Cases tab.
///
/// The tab keeps its state across navigation (the shell is an indexed stack),
/// so a URL query can't re-seed an already-live `CasesScreen`. Instead a KPI
/// queues this before switching to the tab; the screen consumes it once — on
/// mount, or via a listener if it was already alive — and [clear]s it. This
/// makes a KPI tap *jump to the Cases tab* (keeping the bottom nav) rather than
/// push a full-screen browser over the shell. Null when nothing is pending.
@riverpod
class PendingCaseQuery extends _$PendingCaseQuery {
  @override
  CaseQuery? build() => null;

  /// Queue a filter to seed the Cases tab on its next build.
  void queue(CaseQuery query) {
    if (state == query) return;
    state = query;
  }

  /// Drop the pending filter once a screen has consumed it.
  void clear() => state = null;
}

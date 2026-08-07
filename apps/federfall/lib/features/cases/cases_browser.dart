import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cases_browser.g.dart';

DateTime _dispoDate(Disposition d) =>
    d.disposedAt ?? d.created ?? DateTime.fromMillisecondsSinceEpoch(0);

/// The latest (terminal) disposition per case id. Handles re-dispositions by
/// keeping the most recent — the same rule the `case_report_rows` view applies
/// in SQL for the statistics route and the annual report (1700000063), so the
/// browser's outcome facet agrees with the figures.
Map<String, Disposition> terminalDispositionByCase(
  List<Disposition> dispositions,
) {
  final terminal = <String, Disposition>{};
  for (final d in dispositions) {
    final cur = terminal[d.caseId];
    if (cur == null || _dispoDate(d).isAfter(_dispoDate(cur))) {
      terminal[d.caseId] = d;
    }
  }
  return terminal;
}

/// Active/closed split applied by the case browser. "Closed" means a disposed
/// case; "active" is everything else. (The intermediate lifecycle stages are
/// not reachable yet — see federfall-blp.1 — so a finer status filter is
/// deliberately omitted for now.)
enum CaseActivity { active, closed, all }

/// The current filter/search state of the all-cases browser (FED-7.4). Plain
/// value object held as widget state; [CaseBrowseFeed] resolves it against the
/// server.
@immutable
class CaseQuery {
  const CaseQuery({
    this.allScope = false,
    this.activity = CaseActivity.active,
    this.status,
    this.species,
    this.outcome,
    this.condition,
    this.carer,
    this.admittedRange,
    this.text = '',
  });

  /// Seeds a query from deep-link route parameters (dashboard tap-through,
  /// ctw.6): `scope=all`, `activity=active|closed|all`, `status=<wire>`,
  /// `species=<name>`, `outcome=<wire>`, `condition=<label>`, `carer=<userId>`,
  /// `year=<yyyy>`. Unknown/absent params fall back to defaults.
  factory CaseQuery.fromParams(Map<String, String> params) {
    final year = int.tryParse(params['year'] ?? '');
    return CaseQuery(
      allScope: params['scope'] == 'all',
      activity: switch (params['activity']) {
        'closed' => CaseActivity.closed,
        'all' => CaseActivity.all,
        _ => CaseActivity.active,
      },
      status: CaseStatus.fromWire(params['status']),
      species: params['species'],
      outcome: DispositionType.fromWire(params['outcome']),
      condition: params['condition'],
      carer: params['carer'],
      admittedRange: year == null
          ? null
          : DateTimeRange(
              start: DateTime(year),
              end: DateTime(year, 12, 31),
            ),
    );
  }

  /// `false` = only the signed-in user's own cases ("My cases"); `true` widens
  /// to everything they may access (the server rules already scope that).
  ///
  /// Ignored while [carer] is set — that names the caseload to show, so it
  /// supersedes the mine/all split rather than intersecting with it.
  final bool allScope;

  /// Active / closed / all split.
  final CaseActivity activity;

  /// Exact lifecycle status, or null for any (used by dashboard tap-through).
  final CaseStatus? status;

  /// Exact species match against the case's animal, or null for any.
  final String? species;

  /// The terminal outcome recorded on the case, or null for any. Dispositions
  /// are their own collection, not a field on the case, so this resolves
  /// through a back-relation on the server and a last narrowing pass in
  /// [CaseBrowseFeed] — see [CaseBrowseFeed._refineToTerminalOutcome].
  final DispositionType? outcome;

  /// A diagnosis recorded on the case, matched by its display *label*, or null
  /// for any.
  ///
  /// A `case_conditions` row is *either* a `conditions` reference *or* free
  /// text (1700000006), so the label is the only key that can name every
  /// diagnosis — matching by code-list id instead would silently drop every
  /// free-text one. The trade-off is that renaming a code-list entry orphans a
  /// filter naming the old label, which is the lesser problem. The
  /// `condition_labels` view the filter sheet reads groups the two halves the
  /// same way, so a free-text "Katzenbiss" and the code-list entry of that
  /// name are one option and one result set.
  final String? condition;

  /// The user id whose caseload to show — matched against `active_carer` — or
  /// null for any carer. Set by the dashboard's carer-workload card
  /// (federfall-9mit) and by the filter sheet's carer picker.
  ///
  /// This *replaces* the [allScope] scope rather than narrowing it: picking a
  /// carer while scoped to "mine" would otherwise intersect to nothing for
  /// every carer but the signed-in one. What the server lets through is
  /// unaffected — a carer who filters by a colleague sees only the cases that
  /// colleague shared with them, which is the honest answer.
  final String? carer;

  /// Admission-date window (inclusive), or null for any date.
  final DateTimeRange? admittedRange;

  /// Free text matched against case number, animal name, and the animal's
  /// marking codes (ring / chip / band).
  final String text;

  /// Whether anything narrows the default ("my active cases") view.
  bool get isNarrowed => activeFacetCount > 0 || text.trim().isNotEmpty;

  /// Count of non-default filter facets, excluding the (always-visible) search
  /// text. Drives the badge on the collapsed filter button.
  /// A set [carer] counts instead of [allScope], not on top of it — the scope
  /// toggle is inert while a carer is named, so counting both would badge a
  /// filter the user cannot see.
  int get activeFacetCount =>
      (carer != null
          ? 1
          : allScope
          ? 1
          : 0) +
      (activity != CaseActivity.active ? 1 : 0) +
      (status != null ? 1 : 0) +
      (species != null ? 1 : 0) +
      (outcome != null ? 1 : 0) +
      (condition != null ? 1 : 0) +
      (admittedRange != null ? 1 : 0);

  /// Whether the activity split and an exact [status] contradict each other,
  /// i.e. the query can match nothing at all — `?activity=closed` deep-linked
  /// with `?status=in_care` is reachable by hand. The two filters have always
  /// intersected rather than overridden one another, so an empty result is the
  /// right answer; [CaseBrowseFeed] just gives it without asking the server.
  bool get matchesNothing {
    final exact = status;
    return exact != null && !_statusesForActivity.contains(exact);
  }

  /// The lifecycle statuses this query admits, or an empty list for "any".
  List<CaseStatus> get statusFilter {
    final exact = status;
    if (exact != null) return matchesNothing ? const [] : [exact];
    return activity == CaseActivity.all ? const [] : _statusesForActivity;
  }

  List<CaseStatus> get _statusesForActivity => switch (activity) {
    CaseActivity.active => const [
      CaseStatus.inCare,
      CaseStatus.readyForRelease,
    ],
    CaseActivity.closed => const [CaseStatus.disposed],
    CaseActivity.all => CaseStatus.values,
  };

  /// This query as the server understands it (federfall-trep).
  ///
  /// Two decisions belong here rather than in the repository, because both are
  /// about what the person in front of the app meant:
  ///
  ///   • the mine / all / named-carer rule collapses to one `active_carer`
  ///     value (or none, leaving the scoping to the access rules);
  ///   • the picked date range is a pair of LOCAL days and `admitted_at` is
  ///     UTC (`pbDate` normalises every timestamp with `.toUtc()`), so the
  ///     bounds are built from local midnights and handed over half-open.
  ///     Comparing UTC days instead put a bird admitted at 00:30 on New Year's
  ///     Day in UTC+1 outside a range starting that day — and outside the list
  ///     the dashboard's "intakes this year" tile opens, whose count resolves
  ///     the same boundary locally (federfall-s0wk).
  CaseBrowseQuery toBrowseQuery(String myUserId) {
    final range = admittedRange;
    final to = range == null ? null : DateUtils.dateOnly(range.end);
    return CaseBrowseQuery(
      activeCarer: carer ?? (allScope ? null : myUserId),
      statuses: statusFilter,
      // Only "active" and "all" ever took an unset status; naming an exact one
      // must not match a case that has none.
      allowUnsetStatus: status == null && activity != CaseActivity.closed,
      species: species,
      outcome: outcome,
      conditionLabel: condition,
      admittedFrom: range == null ? null : DateUtils.dateOnly(range.start),
      admittedTo: to?.add(const Duration(days: 1)),
      text: text,
    );
  }

  CaseQuery copyWith({
    bool? allScope,
    CaseActivity? activity,
    CaseStatus? status,
    String? species,
    DispositionType? outcome,
    String? condition,
    String? carer,
    DateTimeRange? admittedRange,
    String? text,
    bool clearStatus = false,
    bool clearSpecies = false,
    bool clearOutcome = false,
    bool clearCondition = false,
    bool clearCarer = false,
    bool clearRange = false,
  }) => CaseQuery(
    allScope: allScope ?? this.allScope,
    activity: activity ?? this.activity,
    status: clearStatus ? null : (status ?? this.status),
    species: clearSpecies ? null : (species ?? this.species),
    outcome: clearOutcome ? null : (outcome ?? this.outcome),
    condition: clearCondition ? null : (condition ?? this.condition),
    carer: clearCarer ? null : (carer ?? this.carer),
    admittedRange: clearRange ? null : (admittedRange ?? this.admittedRange),
    text: text ?? this.text,
  );

  @override
  bool operator ==(Object other) =>
      other is CaseQuery &&
      other.allScope == allScope &&
      other.activity == activity &&
      other.status == status &&
      other.species == species &&
      other.outcome == outcome &&
      other.condition == condition &&
      other.carer == carer &&
      other.admittedRange == admittedRange &&
      other.text == text;

  @override
  int get hashCode => Object.hash(
    allScope,
    activity,
    status,
    species,
    outcome,
    condition,
    carer,
    admittedRange,
    text,
  );
}

/// What the browser currently shows: the matching cases loaded so far, plus
/// the animals they name (for the species/name line on each row).
///
/// Constructed explicitly rather than through a `copyWith` — the same reason
/// `AuditFeedState` is: a cursor belongs to the page it came from, and a
/// `copyWith` unable to express "no cursor" is a trap.
@immutable
class CaseBrowseState {
  const CaseBrowseState({
    required this.browse,
    this.cases = const [],
    this.animalsById = const {},
    this.cursor,
    this.hasMore = false,
    this.loadingMore = false,
    this.pageError,
  });

  /// The resolved server query behind these rows — kept so appending a page
  /// asks the same question the first one did.
  final CaseBrowseQuery browse;

  final List<Case> cases;

  /// Only the animals of the loaded cases, projected to what a row shows.
  final Map<String, Animal> animalsById;

  /// Where the next page resumes from — see [PbReadOnlyRepository.page] on why
  /// this is a cursor and not a page number.
  final PbCursor? cursor;
  final bool hasMore;

  /// A page is in flight. Separate from the provider's own AsyncLoading, which
  /// belongs to the FIRST page: appending must not blank the list on screen.
  final bool loadingMore;

  /// Why the last attempt to append a page failed, or null if none did. Kept
  /// in the state rather than thrown, for the reason the audit feed's own
  /// `pageError` documents (federfall-ia9n): the only caller is a scroll
  /// listener, which cannot await, so a thrown error became an unhandled zone
  /// error and the list simply stopped growing in silence.
  final Object? pageError;
}

/// One loaded page, before it is merged into a [CaseBrowseState].
typedef _CasePage = ({
  List<Case> cases,
  Map<String, Animal> animalsById,
  PbCursor? cursor,
  bool hasMore,
});

/// The case browser's result set for [query], a page at a time
/// (federfall-trep).
///
/// Every facet is resolved by the server; the device receives the rows it is
/// about to draw. Keyed on the query, so changing a filter builds a new list
/// from the top rather than mixing pages that answered different questions.
@riverpod
class CaseBrowseFeed extends _$CaseBrowseFeed {
  /// Rows per request. Comfortably more than one screenful, so the common case
  /// is a single round trip and the scroll listener never fires.
  static const int _pageSize = 50;

  @override
  Future<CaseBrowseState> build(CaseQuery query) async {
    // The id, not the user (federfall-bpw6): watching the whole user re-ran
    // this on every token refresh — i.e. every time a browser window regained
    // focus.
    final myUserId = await ref.watch(
      currentUserProvider.selectAsync((u) => u?.id),
    );
    final browse = query.toBrowseQuery(myUserId ?? '');

    if (query.matchesNothing) return CaseBrowseState(browse: browse);

    final (casesRepo, animalsRepo) = await (
      ref.watch(casesRepositoryProvider.future),
      ref.watch(animalsRepositoryProvider.future),
    ).waitUnwrapped;
    final loaded = await _load(casesRepo, animalsRepo, browse, after: null);
    return CaseBrowseState(
      browse: browse,
      cases: loaded.cases,
      animalsById: loaded.animalsById,
      cursor: loaded.cursor,
      hasMore: loaded.hasMore,
    );
  }

  /// Appends the next page. Safe to call repeatedly — it is a no-op while a
  /// page is in flight, once the list is exhausted, or after a page failed, so
  /// a scroll listener can fire it as often as it likes.
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

  Future<void> _appendPage(CaseBrowseState current) async {
    state = AsyncData(
      CaseBrowseState(
        browse: current.browse,
        cases: current.cases,
        animalsById: current.animalsById,
        cursor: current.cursor,
        hasMore: current.hasMore,
        loadingMore: true,
      ),
    );
    try {
      final (casesRepo, animalsRepo) = await (
        ref.read(casesRepositoryProvider.future),
        ref.read(animalsRepositoryProvider.future),
      ).waitUnwrapped;
      final next = await _load(
        casesRepo,
        animalsRepo,
        current.browse,
        after: current.cursor,
      );
      state = AsyncData(
        CaseBrowseState(
          browse: current.browse,
          cases: [...current.cases, ...next.cases],
          animalsById: {...current.animalsById, ...next.animalsById},
          cursor: next.cursor,
          hasMore: next.hasMore,
        ),
      );
    } on Object catch (error) {
      // Keep what is already on screen: a failed page is not a reason to throw
      // away the rows being read. The cursor is kept too, so the retry resumes
      // exactly where this attempt did — no gap, no duplicates.
      state = AsyncData(
        CaseBrowseState(
          browse: current.browse,
          cases: current.cases,
          animalsById: current.animalsById,
          cursor: current.cursor,
          hasMore: current.hasMore,
          pageError: error,
        ),
      );
    }
  }

  /// One page: the cases, then the animals they name.
  ///
  /// The animals are a second request rather than a relation expand because
  /// only two of their columns are ever drawn; `byIds` with a projection is
  /// the same shape the intake map uses.
  Future<_CasePage> _load(
    CasesRepository casesRepo,
    PbAnimalsRepository animalsRepo,
    CaseBrowseQuery browse, {
    required PbCursor? after,
  }) async {
    final page = await casesRepo.browse(
      query: browse,
      after: after,
      perPage: _pageSize,
    );
    final outcome = browse.outcome;
    final cases = outcome == null
        ? page.items
        : await _refineToTerminalOutcome(page.items, outcome);
    final animals = await animalsRepo.byIds(
      cases.map((c) => c.animal).where((id) => id.isNotEmpty),
      fields: 'id,species,name,photo',
    );
    return (
      cases: cases,
      animalsById: {for (final a in animals) a.id: a},
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }

  /// Drops the rows whose *terminal* disposition is not [outcome].
  ///
  /// The server can only ask "does this case carry a disposition of that
  /// type", which over-matches a re-disposed case. The outcome facet means the
  /// latest one — that is what `case_report_rows` reports and what the
  /// statistics screen counts — so the last narrowing happens here, over the
  /// page's own case ids and only while the facet is set.
  Future<List<Case>> _refineToTerminalOutcome(
    List<Case> cases,
    DispositionType outcome,
  ) async {
    if (cases.isEmpty) return cases;
    final repo = await ref.read(dispositionsRepositoryProvider.future);
    final terminal = terminalDispositionByCase(
      await repo.byCases(cases.map((c) => c.id)),
    );
    return cases.where((c) => terminal[c.id]?.type == outcome).toList();
  }
}

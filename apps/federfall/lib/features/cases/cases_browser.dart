import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/case_facets.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cases_browser.g.dart';

/// Active/closed split applied by the case browser. "Closed" means a disposed
/// case; "active" is everything else. (The intermediate lifecycle stages are
/// not reachable yet — see federfall-blp.1 — so a finer status filter is
/// deliberately omitted for now.)
enum CaseActivity { active, closed, all }

/// The current filter/search state of the all-cases browser (FED-7.4). Plain
/// value object held as widget state; [filterCases] turns it into a result set.
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

  /// The terminal outcome recorded on the case, or null for any. Resolved
  /// through [CaseFacets.outcomeByCase] — dispositions are their own
  /// collection, not a field on the case.
  final DispositionType? outcome;

  /// A diagnosis recorded on the case, matched by its display *label*, or null
  /// for any — see [caseConditionLabel] for why a label and not a code-list
  /// id. Resolved through [CaseFacets.conditionsByCase]. The trade-off of the
  /// label is that renaming a code-list entry orphans a link naming the old
  /// one; matching by id instead would silently drop every free-text
  /// diagnosis, which is worse.
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
  /// active marking codes (ring / chip / band).
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

  /// Whether resolving this query needs [CaseFacets] — so the browser only
  /// loads the dispositions and diagnoses when a facet actually reads them.
  bool get needsFacets => outcome != null || condition != null;

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

/// Everything the browser needs in one shot: the accessible cases (server-
/// scoped), their animals keyed by id (for species/name), the animals' active
/// marking codes (so searching a ring/chip code works here too, federfall-78b),
/// and the signed-in user's id (to resolve the "mine" scope client-side).
@immutable
class CasesBrowserData {
  const CasesBrowserData({
    required this.cases,
    required this.animalsById,
    required this.myUserId,
    this.codesByAnimal = const {},
  });

  final List<Case> cases;
  final Map<String, Animal> animalsById;
  final String myUserId;

  /// Active marking codes keyed by animal id (shared lookup with the animals
  /// registry).
  final Map<String, List<String>> codesByAnimal;

  /// Distinct species among the loaded cases' animals, sorted for the filter.
  List<String> get speciesOptions {
    final seen = <String>{};
    for (final c in cases) {
      final s = animalsById[c.animal]?.species;
      if (s != null && s.isNotEmpty) seen.add(s);
    }
    return seen.toList()..sort();
  }
}

/// Loads the browser's source data. Reads every case the access rules expose
/// plus the org's animals, then the filtering happens client-side — the dataset
/// for a single association stays small enough that this is simpler and more
/// responsive than round-tripping each filter change.
@riverpod
Future<CasesBrowserData> casesBrowserData(Ref ref) async {
  final userFuture = ref.watch(currentUserProvider.future);
  final codesFuture = ref.watch(activeMarkingCodesByAnimalProvider.future);
  final (casesRepo, animalsRepo) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
  ).waitUnwrapped;
  // The fetches are independent — issue them concurrently so a (live-)refresh
  // costs one round trip, not three in sequence.
  final (user, codesByAnimal, cases, animals) = await (
    userFuture,
    codesFuture,
    casesRepo.list(sort: '-created'),
    animalsRepo.list(),
  ).waitUnwrapped;
  return CasesBrowserData(
    cases: cases,
    animalsById: {for (final a in animals) a.id: a},
    myUserId: user?.id ?? '',
    codesByAnimal: codesByAnimal,
  );
}

/// Pure application of [query] to [cases]. Kept out of the widget so it can be
/// unit-tested without PocketBase. Input order (newest first) is preserved.
///
/// [facets] resolves the outcome and diagnosis filters, which read collections
/// the case record doesn't carry; leaving it empty is only correct for a query
/// with `needsFacets == false`.
List<Case> filterCases(
  List<Case> cases,
  Map<String, Animal> animalsById, {
  required String myUserId,
  required CaseQuery query,
  Map<String, List<String>> codesByAnimal = const {},
  CaseFacets facets = CaseFacets.empty,
}) {
  final text = query.text.trim().toLowerCase();
  final range = query.admittedRange;
  final from = range == null ? null : DateUtils.dateOnly(range.start);
  final to = range == null ? null : DateUtils.dateOnly(range.end);

  return cases.where((c) {
    // A named carer replaces the mine/all scope rather than narrowing it —
    // see [CaseQuery.carer].
    final carer = query.carer;
    if (carer != null) {
      if (c.activeCarer != carer) return false;
    } else if (!query.allScope && c.activeCarer != myUserId) {
      return false;
    }

    switch (query.activity) {
      case CaseActivity.active:
        if (c.status == CaseStatus.disposed) return false;
      case CaseActivity.closed:
        if (c.status != CaseStatus.disposed) return false;
      case CaseActivity.all:
        break;
    }

    if (query.status != null && c.status != query.status) return false;

    if (query.outcome != null && facets.outcomeByCase[c.id] != query.outcome) {
      return false;
    }

    final condition = query.condition;
    if (condition != null &&
        !(facets.conditionsByCase[c.id]?.contains(condition) ?? false)) {
      return false;
    }

    final animal = animalsById[c.animal];
    if (query.species != null && animal?.species != query.species) {
      return false;
    }

    if (from != null) {
      // `.toLocal()` is load-bearing (federfall-s0wk): `admittedAt` is UTC —
      // `pbDate` normalises every timestamp with `.toUtc()` — while [from] and
      // [to] come from a date picker, i.e. local days. Bucketing the admission
      // by its UTC day compared those across zones, so a bird admitted at
      // 00:30 on New Year's Day in UTC+1 fell out of a range starting that
      // day — and out of the list the dashboard's "intakes this year" tile
      // opens, whose count resolves the same boundary locally.
      final admitted = c.admittedAt?.toLocal();
      if (admitted == null) return false;
      final day = DateUtils.dateOnly(admitted);
      if (day.isBefore(from) || day.isAfter(to!)) return false;
    }

    if (text.isNotEmpty) {
      final number = c.caseNumber?.toLowerCase() ?? '';
      final name = animal?.name?.toLowerCase() ?? '';
      final codes = codesByAnimal[c.animal] ?? const <String>[];
      if (!number.contains(text) &&
          !name.contains(text) &&
          !codes.any((code) => code.toLowerCase().contains(text))) {
        return false;
      }
    }

    return true;
  }).toList();
}

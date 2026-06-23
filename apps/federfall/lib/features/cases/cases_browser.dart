import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
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
    this.species,
    this.admittedRange,
    this.text = '',
  });

  /// `false` = only the signed-in user's own cases ("My cases"); `true` widens
  /// to everything they may access (the server rules already scope that).
  final bool allScope;

  /// Active / closed / all split.
  final CaseActivity activity;

  /// Exact species match against the case's animal, or null for any.
  final String? species;

  /// Admission-date window (inclusive), or null for any date.
  final DateTimeRange? admittedRange;

  /// Free text matched against case number and animal name.
  final String text;

  /// Whether anything narrows the default ("my active cases") view.
  bool get isNarrowed => activeFacetCount > 0 || text.trim().isNotEmpty;

  /// Count of non-default filter facets, excluding the (always-visible) search
  /// text. Drives the badge on the collapsed filter button.
  int get activeFacetCount =>
      (allScope ? 1 : 0) +
      (activity != CaseActivity.active ? 1 : 0) +
      (species != null ? 1 : 0) +
      (admittedRange != null ? 1 : 0);

  CaseQuery copyWith({
    bool? allScope,
    CaseActivity? activity,
    String? species,
    DateTimeRange? admittedRange,
    String? text,
    bool clearSpecies = false,
    bool clearRange = false,
  }) => CaseQuery(
    allScope: allScope ?? this.allScope,
    activity: activity ?? this.activity,
    species: clearSpecies ? null : (species ?? this.species),
    admittedRange: clearRange ? null : (admittedRange ?? this.admittedRange),
    text: text ?? this.text,
  );
}

/// Everything the browser needs in one shot: the accessible cases (server-
/// scoped), their animals keyed by id (for species/name), and the signed-in
/// user's id (to resolve the "mine" scope client-side).
@immutable
class CasesBrowserData {
  const CasesBrowserData({
    required this.cases,
    required this.animalsById,
    required this.myUserId,
  });

  final List<Case> cases;
  final Map<String, Animal> animalsById;
  final String myUserId;

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
  final user = await ref.watch(currentUserProvider.future);
  final casesRepo = await ref.watch(casesRepositoryProvider.future);
  final animalsRepo = await ref.watch(animalsRepositoryProvider.future);
  final cases = await casesRepo.list(sort: '-created');
  final animals = await animalsRepo.list();
  return CasesBrowserData(
    cases: cases,
    animalsById: {for (final a in animals) a.id: a},
    myUserId: user?.id ?? '',
  );
}

/// Pure application of [query] to [cases]. Kept out of the widget so it can be
/// unit-tested without PocketBase. Input order (newest first) is preserved.
List<Case> filterCases(
  List<Case> cases,
  Map<String, Animal> animalsById, {
  required String myUserId,
  required CaseQuery query,
}) {
  final text = query.text.trim().toLowerCase();
  final range = query.admittedRange;
  final from = range == null ? null : DateUtils.dateOnly(range.start);
  final to = range == null ? null : DateUtils.dateOnly(range.end);

  return cases.where((c) {
    if (!query.allScope && c.activeCarer != myUserId) return false;

    switch (query.activity) {
      case CaseActivity.active:
        if (c.status == CaseStatus.disposed) return false;
      case CaseActivity.closed:
        if (c.status != CaseStatus.disposed) return false;
      case CaseActivity.all:
        break;
    }

    final animal = animalsById[c.animal];
    if (query.species != null && animal?.species != query.species) {
      return false;
    }

    if (from != null) {
      final admitted = c.admittedAt;
      if (admitted == null) return false;
      final day = DateUtils.dateOnly(admitted);
      if (day.isBefore(from) || day.isAfter(to!)) return false;
    }

    if (text.isNotEmpty) {
      final number = c.caseNumber?.toLowerCase() ?? '';
      final name = animal?.name?.toLowerCase() ?? '';
      if (!number.contains(text) && !name.contains(text)) return false;
    }

    return true;
  }).toList();
}

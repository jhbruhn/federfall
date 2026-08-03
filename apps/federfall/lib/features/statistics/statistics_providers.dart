import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/case_facets.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'statistics_providers.g.dart';

/// One labelled count, used for the species/condition breakdowns.
@immutable
class StatCount {
  const StatCount(this.label, this.count);

  final String label;
  final int count;
}

/// A terminal-outcome count, keyed by type so the UI resolves the label.
/// A null [type] bucket counts dispositions whose wire value this app version
/// does not know.
@immutable
class OutcomeStat {
  const OutcomeStat(this.type, this.count);

  final DispositionType? type;
  final int count;
}

/// Aggregated reporting figures for the org (FED-7.2): outcome breakdown,
/// intakes by species, conditions seen, and average time in care. Computed over
/// the cases the user may read (org-wide for coordinators/supervisors).
@immutable
class Statistics {
  const Statistics({
    required this.totalCases,
    required this.openCases,
    required this.outcomes,
    required this.bySpecies,
    required this.byCondition,
    required this.avgTimeInCareDays,
    this.intakeYears = const [],
  });

  /// Total cases in scope.
  final int totalCases;

  /// Cases with no terminal disposition yet.
  final int openCases;

  /// Terminal disposition type → count (one per disposed case).
  final List<OutcomeStat> outcomes;

  /// Species → intake (case) count, most common first.
  final List<StatCount> bySpecies;

  /// Condition → number of cases recording it, most common first.
  final List<StatCount> byCondition;

  /// Mean days from admission to terminal disposition, or null if none.
  final double? avgTimeInCareDays;

  /// Every calendar year that has at least one intake, newest first — the years
  /// an annual report can actually be run for (federfall-dk0c's export sheet
  /// offers these rather than a guessed range, so it never invites the user to
  /// print a year that was always empty).
  ///
  /// Years are the LOCAL ones, matching how the report route resolves a
  /// period's boundaries from the caller's own UTC offset — a case admitted at
  /// 00:30 on New Year's Day belongs to the year the carer was living in.
  final List<int> intakeYears;
}

/// Sorts a label→count map into [StatCount]s, highest count first then label.
List<StatCount> _ranked(Map<String, int> counts) {
  final list = [for (final e in counts.entries) StatCount(e.key, e.value)]
    ..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });
  return list;
}

/// Pure aggregation of the raw records into [Statistics]. Kept separate from
/// the provider so it can be unit-tested without PocketBase.
///
/// [recordedConditions] comes straight off the `condition_labels` view, which
/// already counted the cases per diagnosis server-side (federfall-ye5e) —
/// there is no `case_conditions` list here to aggregate.
Statistics computeStatistics({
  required List<Case> cases,
  required List<Disposition> dispositions,
  required List<ConditionLabel> recordedConditions,
  required Map<String, String> speciesByAnimal,
}) {
  final terminalByCase = terminalDispositionByCase(dispositions);

  final outcomeCounts = <DispositionType?, int>{};
  for (final d in terminalByCase.values) {
    outcomeCounts[d.type] = (outcomeCounts[d.type] ?? 0) + 1;
  }
  // Unknown types sort last within a count tie.
  int typeRank(DispositionType? t) => t?.index ?? DispositionType.values.length;
  final outcomes =
      [for (final e in outcomeCounts.entries) OutcomeStat(e.key, e.value)]
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0
              ? byCount
              : typeRank(a.type).compareTo(typeRank(b.type));
        });

  final speciesCounts = <String, int>{};
  for (final c in cases) {
    final sp = speciesByAnimal[c.animal];
    if (sp != null && sp.isNotEmpty) {
      speciesCounts[sp] = (speciesCounts[sp] ?? 0) + 1;
    }
  }

  // The view counts DISTINCT cases per label, so the figure already matches
  // the list a tap-through lands on (federfall-5puj) — a case recording the
  // same diagnosis twice is one case — and it resolves the code-list/free-text
  // split the same way the browser's facet does, in SQL rather than twice in
  // Dart.
  final conditionCounts = {
    for (final c in recordedConditions) c.label: c.caseCount,
  };

  final intakeYears = <int>{
    for (final c in cases)
      if (c.admittedAt != null) c.admittedAt!.toLocal().year,
  }.toList()..sort((a, b) => b.compareTo(a));

  final admittedByCase = {for (final c in cases) c.id: c.admittedAt};
  var totalDays = 0.0;
  var disposedWithSpan = 0;
  for (final entry in terminalByCase.entries) {
    final admitted = admittedByCase[entry.key];
    final disposed = entry.value.disposedAt;
    if (admitted != null && disposed != null) {
      final days = disposed.difference(admitted).inHours / 24.0;
      if (days >= 0) {
        totalDays += days;
        disposedWithSpan++;
      }
    }
  }

  return Statistics(
    totalCases: cases.length,
    openCases: cases.where((c) => !terminalByCase.containsKey(c.id)).length,
    outcomes: outcomes,
    bySpecies: _ranked(speciesCounts),
    byCondition: _ranked(conditionCounts),
    avgTimeInCareDays: disposedWithSpan == 0
        ? null
        : totalDays / disposedWithSpan,
    intakeYears: intakeYears,
  );
}

/// Org reporting statistics (FED-7.2). Loads the cases and dispositions the
/// user may read plus the animal lookup, and takes the condition breakdown
/// pre-counted from the `condition_labels` view instead of pulling every
/// `case_conditions` row to the device (federfall-ye5e).
///
/// **This provider is for coordinators and supervisors only** — the screen
/// gates on `canViewReports`, and that is not merely a UI nicety here: cases
/// and dispositions come back scoped to what the caller may read, while the
/// view's `case_count` is org-wide by construction (a view column is computed
/// once, not per request). For the roles that read org-wide those agree; for a
/// carer they would not, and the figures would silently mix two scopes.
@riverpod
Future<Statistics> statistics(Ref ref) async {
  final recordedFuture = ref.watch(recordedConditionsProvider.future);
  final casesRepo = await ref.watch(casesRepositoryProvider.future);
  final dispositionsRepo = await ref.watch(
    dispositionsRepositoryProvider.future,
  );
  final animalsRepo = await ref.watch(animalsRepositoryProvider.future);

  final cases = await casesRepo.list();
  final dispositions = await dispositionsRepo.list();
  final animals = await animalsRepo.list();
  final recordedConditions = await recordedFuture;

  return computeStatistics(
    cases: cases,
    dispositions: dispositions,
    recordedConditions: recordedConditions,
    speciesByAnimal: {for (final a in animals) a.id: a.species},
  );
}

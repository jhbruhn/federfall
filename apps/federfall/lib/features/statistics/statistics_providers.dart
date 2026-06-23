import 'package:federfall/data/repository_providers.dart';
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
@immutable
class OutcomeStat {
  const OutcomeStat(this.type, this.count);

  final DispositionType type;
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
}

DateTime _dispoDate(Disposition d) =>
    d.disposedAt ?? d.created ?? DateTime.fromMillisecondsSinceEpoch(0);

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
Statistics computeStatistics({
  required List<Case> cases,
  required List<Disposition> dispositions,
  required List<CaseCondition> caseConditions,
  required Map<String, String> speciesByAnimal,
  required Map<String, String> conditionLabels,
}) {
  // The latest disposition per case is its terminal outcome (handles the rare
  // re-disposition by keeping the most recent).
  final terminalByCase = <String, Disposition>{};
  for (final d in dispositions) {
    final cur = terminalByCase[d.caseId];
    if (cur == null || _dispoDate(d).isAfter(_dispoDate(cur))) {
      terminalByCase[d.caseId] = d;
    }
  }

  final outcomeCounts = <DispositionType, int>{};
  for (final d in terminalByCase.values) {
    outcomeCounts[d.type] = (outcomeCounts[d.type] ?? 0) + 1;
  }
  final outcomes =
      [for (final e in outcomeCounts.entries) OutcomeStat(e.key, e.value)]
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.type.index.compareTo(b.type.index);
        });

  final speciesCounts = <String, int>{};
  for (final c in cases) {
    final sp = speciesByAnimal[c.animal];
    if (sp != null && sp.isNotEmpty) {
      speciesCounts[sp] = (speciesCounts[sp] ?? 0) + 1;
    }
  }

  final conditionCounts = <String, int>{};
  for (final cc in caseConditions) {
    final id = cc.condition;
    final label = (id != null ? conditionLabels[id] : null) ?? cc.freeText;
    if (label != null && label.isNotEmpty) {
      conditionCounts[label] = (conditionCounts[label] ?? 0) + 1;
    }
  }

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
    avgTimeInCareDays:
        disposedWithSpan == 0 ? null : totalDays / disposedWithSpan,
  );
}

/// Org reporting statistics (FED-7.2). Loads the cases, dispositions and
/// conditions the user may read (org-wide for coordinators/supervisors) plus
/// the animal/condition lookups, then aggregates client-side.
@riverpod
Future<Statistics> statistics(Ref ref) async {
  final casesRepo = await ref.watch(casesRepositoryProvider.future);
  final dispositionsRepo =
      await ref.watch(dispositionsRepositoryProvider.future);
  final caseConditionsRepo =
      await ref.watch(caseConditionsRepositoryProvider.future);
  final animalsRepo = await ref.watch(animalsRepositoryProvider.future);
  final conditionsRepo = await ref.watch(conditionsRepositoryProvider.future);

  final cases = await casesRepo.list();
  final dispositions = await dispositionsRepo.list();
  final caseConditions = await caseConditionsRepo.list();
  final animals = await animalsRepo.list();
  final conditions = await conditionsRepo.list();

  return computeStatistics(
    cases: cases,
    dispositions: dispositions,
    caseConditions: caseConditions,
    speciesByAnimal: {for (final a in animals) a.id: a.species},
    conditionLabels: {for (final c in conditions) c.id: c.label},
  );
}

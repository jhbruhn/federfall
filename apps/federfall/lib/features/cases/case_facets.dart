import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'case_facets.g.dart';

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

/// The display label of a recorded diagnosis: its code-list entry's name, or
/// the free text when it references no entry. Null when it carries neither.
///
/// A `case_conditions` row is *either* a `conditions` reference *or* free text
/// (`1700000006_conditions_and_case_conditions.js`), so the label — not a
/// condition id — is the only key that can name every diagnosis. Shared by the
/// statistics breakdown and the browser's condition facet so the two agree on
/// what counts as the same diagnosis, and a free-text "Katzenbiss" buckets
/// with the code-list one.
String? caseConditionLabel(CaseCondition cc, Map<String, String> labels) {
  final id = cc.condition;
  final label = (id != null ? labels[id] : null) ?? cc.freeText;
  return label == null || label.isEmpty ? null : label;
}

/// The two case-browser facets that don't live on the case record: the case's
/// terminal outcome (a `dispositions` row) and the diagnoses recorded on it
/// (`case_conditions`). Both keyed by case id.
@immutable
class CaseFacets {
  const CaseFacets({
    this.outcomeByCase = const {},
    this.conditionsByCase = const {},
  });

  /// Nothing loaded — what the browser filters against while no facet is in
  /// use, and the default for callers that never set one.
  static const empty = CaseFacets();

  /// Case id → the type of its terminal disposition. Cases with no terminal
  /// disposition are absent, as are dispositions carrying a wire value this
  /// app version does not know (they can't be named, so they can't be
  /// filtered for).
  final Map<String, DispositionType> outcomeByCase;

  /// Case id → the labels of every diagnosis recorded on it (see
  /// [caseConditionLabel] for why labels and not ids).
  final Map<String, Set<String>> conditionsByCase;
}

/// Pure projection of the raw rows into [CaseFacets]. Kept out of the provider
/// so it can be unit-tested without PocketBase, mirroring
/// `filterIntakeLocations`.
CaseFacets buildCaseFacets({
  required List<Disposition> dispositions,
  required List<CaseCondition> caseConditions,
  required Map<String, String> conditionLabels,
}) {
  final outcomeByCase = <String, DispositionType>{};
  for (final entry in terminalDispositionByCase(dispositions).entries) {
    final type = entry.value.type;
    if (type != null) outcomeByCase[entry.key] = type;
  }

  final conditionsByCase = <String, Set<String>>{};
  for (final cc in caseConditions) {
    final label = caseConditionLabel(cc, conditionLabels);
    if (label != null) (conditionsByCase[cc.caseId] ??= {}).add(label);
  }

  return CaseFacets(
    outcomeByCase: outcomeByCase,
    conditionsByCase: conditionsByCase,
  );
}

/// Loads the facets for every case the user may read.
///
/// Deliberately *not* folded into `casesBrowserDataProvider`: it costs two more
/// full-collection reads, and only a query that actually filters by outcome or
/// diagnosis needs them. `CasesScreen` watches this only while
/// `CaseQuery.needsFacets`, so the plain Cases tab keeps the fetches it always
/// had and this one is disposed again as soon as the facet is cleared.
///
/// Note that the filter sheet's own pickers don't need it: the outcomes are
/// `DispositionType.values` and the diagnoses come from the small `conditions`
/// code list, so opening the filters costs nothing here — only *applying* one
/// of those two facets does.
@riverpod
Future<CaseFacets> caseFacets(Ref ref) async {
  // The code-list lookup is shared with the case timeline, so filtering by a
  // diagnosis right after viewing one costs nothing extra.
  final labelsFuture = ref.watch(conditionsByIdProvider.future);
  final (dispositionsRepo, caseConditionsRepo) = await (
    ref.watch(dispositionsRepositoryProvider.future),
    ref.watch(caseConditionsRepositoryProvider.future),
  ).waitUnwrapped;
  final (labels, dispositions, caseConditions) = await (
    labelsFuture,
    dispositionsRepo.list(),
    caseConditionsRepo.list(),
  ).waitUnwrapped;

  return buildCaseFacets(
    dispositions: dispositions,
    caseConditions: caseConditions,
    conditionLabels: {
      for (final entry in labels.entries) entry.key: entry.value.label,
    },
  );
}

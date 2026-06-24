import 'package:csv/csv.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';

/// One row of the annual-report CSV (FED-7.3): a case with its animal's
/// species/name and its terminal outcome. Structured (not localized) so the
/// assembly is unit-testable; the UI maps it to localized cells.
@immutable
class CaseReportRow {
  const CaseReportRow({
    required this.caseNumber,
    required this.species,
    required this.name,
    required this.admittedAt,
    required this.foundAt,
    required this.status,
    required this.outcome,
    required this.endedAt,
    required this.daysInCare,
    required this.city,
    required this.region,
    required this.reasons,
  });

  final String? caseNumber;
  final String species;
  final String? name;
  final DateTime? admittedAt;
  final DateTime? foundAt;
  final CaseStatus? status;
  final DispositionType? outcome;
  final DateTime? endedAt;
  final int? daysInCare;
  final String? city;
  final String? region;
  final List<AdmissionReason> reasons;
}

/// Builds report rows from the raw records, newest-first by admission. Pure, so
/// the join + time-in-care maths are unit-tested without PocketBase.
List<CaseReportRow> buildCaseReportRows({
  required List<Case> cases,
  required List<Disposition> dispositions,
  required Map<String, Animal> animalsById,
}) {
  final terminal = terminalDispositionByCase(dispositions);
  final rows = <CaseReportRow>[];
  for (final c in cases) {
    final animal = animalsById[c.animal];
    final disposition = terminal[c.id];
    final ended = disposition?.disposedAt;
    final admitted = c.admittedAt;
    final hasSpan =
        admitted != null && ended != null && !ended.isBefore(admitted);
    final days = hasSpan ? ended.difference(admitted).inDays : null;
    rows.add(
      CaseReportRow(
        caseNumber: c.caseNumber,
        species: animal?.species ?? '',
        name: animal?.name,
        admittedAt: admitted,
        foundAt: c.foundAt,
        status: c.status,
        outcome: disposition?.type,
        endedAt: ended,
        daysInCare: days,
        city: c.city,
        region: c.region,
        reasons: c.reasonsForAdmission,
      ),
    );
  }
  rows.sort((a, b) {
    final ad = a.admittedAt;
    final bd = b.admittedAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return rows;
}

/// Encodes [rows] as a CSV document. [header] supplies the localized column
/// titles (must match the 12-column order below); the label callbacks localize
/// enum values and dates. A UTF-8 BOM is prepended so spreadsheet apps render
/// German umlauts correctly.
String encodeCaseReportCsv({
  required List<CaseReportRow> rows,
  required List<String> header,
  required String Function(CaseStatus) status,
  required String Function(DispositionType) outcome,
  required String Function(AdmissionReason) reason,
  required String Function(DateTime) date,
}) {
  String d(DateTime? v) => v == null ? '' : date(v);
  String s(CaseStatus? v) => v == null ? '' : status(v);
  String o(DispositionType? v) => v == null ? '' : outcome(v);

  final table = <List<String>>[header];
  for (final r in rows) {
    table.add([
      r.caseNumber ?? '',
      r.species,
      r.name ?? '',
      d(r.admittedAt),
      d(r.foundAt),
      s(r.status),
      o(r.outcome),
      d(r.endedAt),
      r.daysInCare?.toString() ?? '',
      r.city ?? '',
      r.region ?? '',
      r.reasons.map(reason).join('; '),
    ]);
  }
  // BOM so spreadsheet apps render German umlauts as UTF-8.
  return const CsvEncoder(addBom: true).convert(table);
}

import 'package:csv/csv.dart';
import 'package:federfall_models/federfall_models.dart';

/// Encodes [rows] as the annual-report CSV (FED-7.3). The rows come pre-joined
/// from the `case_report_rows` view (federfall-80tc) — this side only formats.
///
/// [header] supplies the localized column titles (must match the 12-column
/// order below); the label callbacks localize enum values and dates. Admission
/// reasons arrive already resolved to their (user-authored) labels and joined.
/// A UTF-8 BOM is prepended so spreadsheet apps render German umlauts
/// correctly.
String encodeCaseReportCsv({
  required List<CaseReportRow> rows,
  required List<String> header,
  required String Function(CaseStatus) status,
  required String Function(DispositionType) outcome,
  required String Function(DateTime) date,
}) {
  String d(DateTime? v) => v == null ? '' : date(v);
  String s(CaseStatus? v) => v == null ? '' : status(v);
  String o(DispositionType? v) => v == null ? '' : outcome(v);

  final table = <List<String>>[header];
  for (final r in rows) {
    table.add(
      [
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
        r.reasons,
      ].map(_guardFormulaInjection).toList(growable: false),
    );
  }
  // BOM so spreadsheet apps render German umlauts as UTF-8.
  return const CsvEncoder(addBom: true).convert(table);
}

/// Neutralises spreadsheet formula injection (OWASP CSV Injection): several
/// cells carry user-authored text (species, name, city, admission-reason
/// labels), and Excel/LibreOffice execute cells starting with `=`, `+`, `-`,
/// `@`, tab or CR as formulas. A leading apostrophe forces text interpretation;
/// the csv package's quoting alone does not prevent this.
String _guardFormulaInjection(String cell) {
  if (cell.isEmpty) return cell;
  const dangerous = ['=', '+', '-', '@', '\t', '\r'];
  return dangerous.contains(cell[0]) ? "'$cell" : cell;
}

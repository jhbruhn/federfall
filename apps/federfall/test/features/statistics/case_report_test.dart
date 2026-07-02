import 'package:federfall/features/statistics/case_report.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildCaseReportRows', () {
    test('joins species/name, computes days, sorts newest-first', () {
      final rows = buildCaseReportRows(
        cases: [
          Case(
            id: 'c1',
            animal: 'a1',
            caseNumber: '2026-001',
            admittedAt: DateTime(2026, 2, 2),
          ),
          Case(
            id: 'c2',
            animal: 'a2',
            caseNumber: '2026-005',
            admittedAt: DateTime(2026, 5, 5),
          ),
        ],
        dispositions: [
          Disposition(
            id: 'd1',
            caseId: 'c1',
            type: DispositionType.released,
            disposedAt: DateTime(2026, 2, 12),
          ),
        ],
        animalsById: const {
          'a1': Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
          'a2': Animal(id: 'a2', species: 'Streptopelia decaocto'),
        },
        admissionReasonsById: const {},
      );

      // Sorted by admission, newest first: c2 (May) before c1 (Feb).
      expect(rows.map((r) => r.caseNumber).toList(), ['2026-005', '2026-001']);

      final c1 = rows.firstWhere((r) => r.caseNumber == '2026-001');
      expect(c1.species, 'Columba livia');
      expect(c1.name, 'Pip');
      expect(c1.outcome, DispositionType.released);
      expect(c1.endedAt, DateTime(2026, 2, 12));
      expect(c1.daysInCare, 10);

      final c2 = rows.firstWhere((r) => r.caseNumber == '2026-005');
      expect(c2.outcome, isNull, reason: 'no disposition');
      expect(c2.daysInCare, isNull);
      expect(c2.name, isNull);
    });
  });

  group('encodeCaseReportCsv', () {
    String enc(List<CaseReportRow> rows) => encodeCaseReportCsv(
      rows: rows,
      header: const ['No', 'Species', 'Name', 'Adm', 'Found', 'Status',
        'Outcome', 'Closed', 'Days', 'City', 'Region', 'Reasons'],
      status: (s) => s.name,
      outcome: (o) => o.name,
      date: (d) => '${d.year}-${d.month}-${d.day}',
    );

    test('prepends a UTF-8 BOM and the header row', () {
      final csv = enc(const []);
      expect(csv.codeUnitAt(0), 0xFEFF, reason: 'BOM first');
      expect(csv, contains('No,Species,Name'));
    });

    test('quotes fields containing the delimiter', () {
      final csv = enc([
        const CaseReportRow(
          caseNumber: '2026-001',
          species: 'Columba livia',
          name: 'Pip, the brave',
          admittedAt: null,
          foundAt: null,
          status: CaseStatus.inCare,
          outcome: null,
          endedAt: null,
          daysInCare: null,
          city: null,
          region: null,
          reasons: ['Injury', 'Cat attack'],
        ),
      ]);
      // The comma-bearing name is wrapped in quotes; reasons join with "; ".
      expect(csv, contains('"Pip, the brave"'));
      expect(csv, contains('Injury; Cat attack'));
      expect(csv, contains('inCare'));
    });

    test('neutralises spreadsheet formula injection in user-authored cells',
        () {
      final csv = enc([
        const CaseReportRow(
          caseNumber: null,
          species: '=HYPERLINK("http://evil.example";"x")',
          name: '+cmd',
          admittedAt: null,
          foundAt: null,
          status: null,
          outcome: null,
          endedAt: null,
          daysInCare: null,
          city: '-2+3',
          region: '@SUM(A1)',
          reasons: ['\tTAB', '\rCR'],
        ),
      ]);
      // Every dangerous leading char is escaped with an apostrophe so
      // spreadsheet apps treat the cell as text (OWASP CSV Injection).
      expect(csv, contains("'=HYPERLINK"));
      expect(csv, contains("'+cmd"));
      expect(csv, contains("'-2+3"));
      expect(csv, contains("'@SUM(A1)"));
      expect(csv, contains("'\tTAB"));
      expect(csv, isNot(contains(',=')));
      expect(csv, isNot(contains(',+')));
    });

    test('leaves benign cells untouched', () {
      final csv = enc([
        const CaseReportRow(
          caseNumber: '2026-001',
          species: 'Columba livia',
          name: 'Pip',
          admittedAt: null,
          foundAt: null,
          status: null,
          outcome: null,
          endedAt: null,
          daysInCare: 10,
          city: 'Oldenburg',
          region: 'NI',
          reasons: [],
        ),
      ]);
      expect(csv, isNot(contains("'")));
    });
  });
}

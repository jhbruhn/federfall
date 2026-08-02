import 'package:federfall/features/statistics/case_report.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeCaseReportCsv', () {
    String enc(List<CaseReportRow> rows) => encodeCaseReportCsv(
      rows: rows,
      header: const [
        'No',
        'Species',
        'Name',
        'Adm',
        'Found',
        'Status',
        'Outcome',
        'Closed',
        'Days',
        'City',
        'Region',
        'Reasons',
      ],
      status: (s) => s.name,
      outcome: (o) => o.name,
      date: (d) => '${d.year}-${d.month}-${d.day}',
    );

    test('prepends a UTF-8 BOM and the header row', () {
      final csv = enc(const []);
      expect(csv.codeUnitAt(0), 0xFEFF, reason: 'BOM first');
      expect(csv, contains('No,Species,Name'));
    });

    test('writes the joined row, its dates and the derived days in care', () {
      final csv = enc([
        CaseReportRow(
          id: 'c1',
          caseNumber: '2026-001',
          species: 'Columba livia',
          name: 'Pip',
          admittedAt: DateTime(2026, 2, 2),
          status: CaseStatus.disposed,
          outcome: DispositionType.released,
          endedAt: DateTime(2026, 2, 12),
        ),
      ]);
      expect(csv, contains('2026-001,Columba livia,Pip,2026-2-2'));
      expect(csv, contains('disposed,released,2026-2-12,10'));
    });

    test('quotes fields containing the delimiter', () {
      final csv = enc([
        const CaseReportRow(
          id: 'c1',
          caseNumber: '2026-001',
          species: 'Columba livia',
          name: 'Pip, the brave',
          status: CaseStatus.inCare,
          reasons: 'Injury; Cat attack',
        ),
      ]);
      // The comma-bearing name is wrapped in quotes; the view already joined
      // the admission reasons with "; ".
      expect(csv, contains('"Pip, the brave"'));
      expect(csv, contains('Injury; Cat attack'));
      expect(csv, contains('inCare'));
    });

    test(
      'neutralises spreadsheet formula injection in user-authored cells',
      () {
        final csv = enc([
          const CaseReportRow(
            id: 'c1',
            species: '=HYPERLINK("http://evil.example";"x")',
            name: '+cmd',
            city: '-2+3',
            region: '@SUM(A1)',
            reasons: '\tTAB',
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
      },
    );

    test('leaves benign cells untouched', () {
      final csv = enc([
        const CaseReportRow(
          id: 'c1',
          caseNumber: '2026-001',
          species: 'Columba livia',
          name: 'Pip',
          city: 'Oldenburg',
          region: 'NI',
        ),
      ]);
      expect(csv, isNot(contains("'")));
    });
  });
}

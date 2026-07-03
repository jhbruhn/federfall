import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

void main() {
  group('CaseBundle.fromRecord', () {
    test('maps the case and every expanded timeline source', () {
      final r = RecordModel.fromJson({
        'id': 'case0000000001',
        'animal': 'anml0000000001',
        'finder': 'fndr0000000001',
        'status': 'in_care',
        'expand': {
          'animal': {
            'id': 'anml0000000001',
            'species': 'Stadttaube',
            'name': 'Paula',
            'expand': {
              'markings_via_animal': [
                {
                  'id': 'mark0000000001',
                  'animal': 'anml0000000001',
                  'code': 'DV-123',
                  'applied_at': '2026-06-01 10:00:00.000Z',
                },
              ],
            },
          },
          'finder': {'id': 'fndr0000000001', 'last_name': 'Meyer'},
          'journal_entries_via_case': [
            {
              'id': 'jrnl0000000001',
              'case': 'case0000000001',
              'text': 'older',
              'entry_at': '2026-06-01 08:00:00.000Z',
            },
            {
              'id': 'jrnl0000000002',
              'case': 'case0000000001',
              'text': 'newer',
              'entry_at': '2026-06-02 08:00:00.000Z',
            },
          ],
          'weights_via_case': [
            {
              'id': 'wght0000000002',
              'animal': 'anml0000000001',
              'weight_g': 310,
              'measured_at': '2026-06-02 08:00:00.000Z',
            },
            {
              'id': 'wght0000000001',
              'animal': 'anml0000000001',
              'weight_g': 300,
              'measured_at': '2026-06-01 08:00:00.000Z',
            },
          ],
          'case_conditions_via_case': [
            {'id': 'ccnd0000000001', 'case': 'case0000000001'},
          ],
          'medications_via_case': [
            {
              'id': 'medi0000000001',
              'case': 'case0000000001',
              'drug': 'Baytril',
              'started_at': '2026-06-01 09:00:00.000Z',
            },
          ],
          'medication_administrations_via_case': [
            {
              'id': 'admn0000000001',
              'case': 'case0000000001',
              'drug': 'Baytril',
              'administered_at': '2026-06-01 10:00:00.000Z',
            },
          ],
          'placements_via_case': [
            {'id': 'plce0000000001', 'case': 'case0000000001'},
          ],
          'dispositions_via_case': [
            {
              'id': 'disp0000000001',
              'case': 'case0000000001',
              'type': 'released',
            },
          ],
          'follow_ups_via_case': [
            {
              'id': 'flwu0000000001',
              'case': 'case0000000001',
              'due_at': '2026-06-05 10:00:00.000Z',
            },
          ],
          'exams_via_case': [
            {
              'id': 'exam0000000001',
              'case': 'case0000000001',
              'examined_at': '2026-06-01 11:00:00.000Z',
              'expand': {
                'exam_findings_via_exam': [
                  {
                    'id': 'find0000000001',
                    'exam': 'exam0000000001',
                    'system': 'wings',
                    'status': 'abnormal',
                  },
                ],
              },
            },
          ],
          'quarantine_records_via_case': [
            {'id': 'quar0000000001', 'case': 'case0000000001'},
          ],
        },
      });

      final b = CaseBundle.fromRecord(r);
      expect(b.medicalCase.id, 'case0000000001');
      expect(b.animal?.name, 'Paula');
      expect(b.finder?.lastName, 'Meyer');
      expect(b.markings.single.code, 'DV-123');
      expect(b.caseConditions.single.id, 'ccnd0000000001');
      expect(b.medications.single.drug, 'Baytril');
      expect(b.administrations.single.id, 'admn0000000001');
      expect(b.placements.single.id, 'plce0000000001');
      expect(b.dispositions.single.id, 'disp0000000001');
      expect(b.followUps.single.id, 'flwu0000000001');
      expect(b.exams.single.id, 'exam0000000001');
      expect(b.examFindings.single.exam, 'exam0000000001');
      expect(b.quarantines.single.id, 'quar0000000001');

      // Sorted like the per-collection queries: journal newest first,
      // weights oldest first (the trend chart's order).
      expect(b.journal.map((e) => e.text), ['newer', 'older']);
      expect(b.weights.map((w) => w.weightG), [300, 310]);
    });

    test('an unexpanded record maps to an empty bundle', () {
      final b = CaseBundle.fromRecord(
        RecordModel.fromJson({'id': 'case0000000001', 'animal': 'a'}),
      );
      expect(b.medicalCase.id, 'case0000000001');
      expect(b.animal, isNull);
      expect(b.finder, isNull);
      expect(b.journal, isEmpty);
      expect(b.weights, isEmpty);
      expect(b.caseConditions, isEmpty);
      expect(b.medications, isEmpty);
      expect(b.administrations, isEmpty);
      expect(b.markings, isEmpty);
      expect(b.placements, isEmpty);
      expect(b.dispositions, isEmpty);
      expect(b.followUps, isEmpty);
      expect(b.exams, isEmpty);
      expect(b.examFindings, isEmpty);
      expect(b.quarantines, isEmpty);
    });
  });
}

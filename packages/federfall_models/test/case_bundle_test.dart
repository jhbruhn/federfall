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
              'egg_records_via_animal': [
                {
                  'id': 'eggr0000000001',
                  'animal': 'anml0000000001',
                  'count': 1,
                  'laid_at': '2026-06-02 06:00:00.000Z',
                },
                {
                  'id': 'eggr0000000002',
                  'animal': 'anml0000000001',
                  'count': 2,
                  'laid_at': '2026-06-20 06:00:00.000Z',
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
          'microscopy_samples_via_case': [
            {
              'id': 'micr0000000001',
              'case': 'case0000000001',
              'sample_type': 'fecal',
              'method': 'flotation',
              'examined_at': '2026-06-03 09:00:00.000Z',
              'expand': {
                'microscopy_findings_via_sample': [
                  {
                    'id': 'mfnd0000000001',
                    'sample': 'micr0000000001',
                    'severity': 'plus_plus',
                  },
                ],
              },
            },
            {
              'id': 'micr0000000002',
              'case': 'case0000000001',
              'sample_type': 'crop_swab',
              'examined_at': '2026-06-05 09:00:00.000Z',
              'no_findings': true,
            },
          ],
          'quarantine_records_via_case': [
            {'id': 'quar0000000001', 'case': 'case0000000001'},
          ],
          'vet_appointments_via_case': [
            {
              'id': 'vapt0000000002',
              'case': 'case0000000001',
              'starts_at': '2026-08-06 12:30:00.000Z',
              'vet': 'Dr. Meyer',
            },
            {
              'id': 'vapt0000000001',
              'case': 'case0000000001',
              'starts_at': '2026-07-06 12:30:00.000Z',
            },
          ],
        },
      });

      final b = CaseBundle.fromRecord(r);
      expect(b.medicalCase.id, 'case0000000001');
      expect(b.animal?.name, 'Paula');
      expect(b.finder?.lastName, 'Meyer');
      expect(b.markings.single.code, 'DV-123');
      // Eggs come off the ANIMAL, newest first — they carry no case relation.
      expect(b.eggs.map((e) => e.id), ['eggr0000000002', 'eggr0000000001']);
      expect(b.caseConditions.single.id, 'ccnd0000000001');
      expect(b.medications.single.drug, 'Baytril');
      expect(b.administrations.single.id, 'admn0000000001');
      expect(b.placements.single.id, 'plce0000000001');
      expect(b.dispositions.single.id, 'disp0000000001');
      expect(b.followUps.single.id, 'flwu0000000001');
      expect(b.exams.single.id, 'exam0000000001');
      expect(b.examFindings.single.exam, 'exam0000000001');
      // Samples newest first, and their findings flattened across them in that
      // order — the exam shape.
      expect(b.microscopySamples.map((s) => s.id), [
        'micr0000000002',
        'micr0000000001',
      ]);
      expect(b.microscopyFindings.single.sample, 'micr0000000001');
      expect(b.quarantines.single.id, 'quar0000000001');
      expect(b.vetAppointments.map((a) => a.vet), [null, 'Dr. Meyer']);

      // Sorted like the per-collection queries: journal newest first,
      // weights oldest first (the trend chart's order), appointments soonest
      // first.
      expect(b.journal.map((e) => e.text), ['newer', 'older']);
      expect(b.weights.map((w) => w.weightG), [300, 310]);
      expect(b.vetAppointments.map((a) => a.id), [
        'vapt0000000001',
        'vapt0000000002',
      ]);
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
      expect(b.eggs, isEmpty);
      expect(b.placements, isEmpty);
      expect(b.dispositions, isEmpty);
      expect(b.followUps, isEmpty);
      expect(b.exams, isEmpty);
      expect(b.examFindings, isEmpty);
      expect(b.microscopySamples, isEmpty);
      expect(b.microscopyFindings, isEmpty);
      expect(b.quarantines, isEmpty);
      expect(b.vetAppointments, isEmpty);
    });
  });
}

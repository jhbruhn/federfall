import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

void main() {
  group('MicroscopyFindingType.fromRecord', () {
    test('maps the label and the applicability multi-select', () {
      final t = MicroscopyFindingType.fromRecord(
        RecordModel({
          'id': 'mfty0000000001',
          'label': 'Hefen',
          'sample_types': ['crop_swab', 'fecal'],
          'description': 'Sprosszellen',
          'active': true,
          'org': 'org00000000001',
          'created': '2026-08-09 09:00:00.000Z',
          'updated': '2026-08-09 09:01:00.000Z',
        }),
      );
      expect(t.label, 'Hefen');
      expect(t.sampleTypes, [
        MicroscopySampleType.cropSwab,
        MicroscopySampleType.fecal,
      ]);
      expect(t.description, 'Sprosszellen');
      expect(t.active, isTrue);
      expect(t.created?.hour, 9);
    });

    test('an entry with no applicability maps to an empty list', () {
      final t = MicroscopyFindingType.fromRecord(
        RecordModel({'id': 'x', 'label': 'Kokzidien', 'sample_types': ''}),
      );
      expect(t.sampleTypes, isEmpty);
      // PB stores an unset bool as false; the code list treats that literally.
      expect(t.active, isFalse);
    });
  });

  group('MicroscopySample.fromRecord', () {
    test('maps the enums, the attachments and the case link', () {
      final s = MicroscopySample.fromRecord(
        RecordModel({
          'id': 'micr0000000001',
          'case': 'case0000000001',
          'sample_type': 'fecal',
          'method': 'flotation',
          'examined_at': '2026-08-09 09:12:00.000Z',
          'examined_by': 'lab',
          'examiner': '',
          'external_lab': 'Labor Müller',
          'no_findings': false,
          'attachments': ['smear.jpg', 'clip.mp4'],
          'notes': 'stark bewegt',
          'author': 'user0000000001',
          'org': 'org00000000001',
          'created': '2026-08-09 09:13:00.000Z',
        }),
      );
      expect(s.caseId, 'case0000000001');
      expect(s.sampleType, MicroscopySampleType.fecal);
      expect(s.method, MicroscopyMethod.flotation);
      expect(s.examinedAt?.minute, 12);
      expect(s.examinedBy, MicroscopyExaminedBy.lab);
      expect(s.examiner, isNull);
      expect(s.externalLab, 'Labor Müller');
      expect(s.noFindings, isFalse);
      expect(s.attachments, ['smear.jpg', 'clip.mp4']);
      expect(s.notes, 'stark bewegt');
    });

    test('an unread lab sample keeps every optional field null', () {
      final s = MicroscopySample.fromRecord(
        RecordModel({
          'id': 'micr0000000002',
          'case': 'case0000000001',
          'sample_type': 'crop_swab',
          'method': '',
          'examined_by': '',
        }),
      );
      // Neither noFindings nor a finding: the legitimate "result pending"
      // state, which must not read as "ohne Befund".
      expect(s.noFindings, isFalse);
      expect(s.method, isNull);
      expect(s.examinedBy, isNull);
      expect(s.examinedAt, isNull);
      expect(s.attachments, isEmpty);
    });
  });

  group('MicroscopyFinding.fromRecord', () {
    test('maps a graded vocabulary reference', () {
      final f = MicroscopyFinding.fromRecord(
        RecordModel({
          'id': 'mfnd0000000001',
          'sample': 'micr0000000001',
          'finding_type': 'mfty0000000001',
          'free_text': '',
          'severity': 'plus_plus_plus',
          'org': 'org00000000001',
        }),
      );
      expect(f.sample, 'micr0000000001');
      expect(f.findingType, 'mfty0000000001');
      expect(f.freeText, isNull);
      expect(f.severity, MicroscopySeverity.plusPlusPlus);
    });

    test('maps the free-text path', () {
      final f = MicroscopyFinding.fromRecord(
        RecordModel({
          'id': 'mfnd0000000002',
          'sample': 'micr0000000001',
          'finding_type': '',
          'free_text': 'Ziliaten',
          'severity': 'plus',
        }),
      );
      expect(f.findingType, isNull);
      expect(f.freeText, 'Ziliaten');
      expect(f.severity, MicroscopySeverity.plus);
    });
  });

  group('severity ordering', () {
    test('the enum is declared weakest first, so index orders grades', () {
      expect(MicroscopySeverity.values.map((s) => s.wire), [
        'plus',
        'plus_plus',
        'plus_plus_plus',
      ]);
    });
  });
}

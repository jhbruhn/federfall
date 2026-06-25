import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

void main() {
  group('Case.fromRecord', () {
    test('maps fields, dates, geo, enums and multi-select', () {
      final r = RecordModel({
        'id': 'case0000000001',
        'animal': 'anml0000000001',
        'case_number': '2026-014',
        'age_class': 'adult',
        'admitted_at': '2026-03-10 09:00:00.000Z',
        'found_at': '',
        'finder': '',
        'find_geo': {'lon': 9.99, 'lat': 53.55},
        'reasons_for_admission': ['injury', 'cat_attack'],
        'intake_weight_g': 320,
        'status': 'in_care',
        'is_releasable': true,
        'exam_temperature': 41.2,
      });

      final c = Case.fromRecord(r);

      expect(c.id, 'case0000000001');
      expect(c.animal, 'anml0000000001');
      expect(c.caseNumber, '2026-014');
      expect(c.ageClass, AgeClass.adult);
      expect(c.admittedAt?.hour, 9);
      expect(c.foundAt, isNull, reason: 'empty date → null');
      expect(c.finder, isNull, reason: 'empty relation → null');
      expect(c.findGeo, const GeoPoint(lon: 9.99, lat: 53.55));
      expect(c.reasonsForAdmission,
          [AdmissionReason.injury, AdmissionReason.catAttack]);
      expect(c.intakeWeightG, 320);
      expect(c.status, CaseStatus.inCare);
      expect(c.isReleasable, isTrue);
      expect(c.examTemperature, 41.2);
    });

    test('treats {0,0} geoPoint as no pin', () {
      final r = RecordModel({
        'id': 'c',
        'animal': 'a',
        'find_geo': {'lon': 0, 'lat': 0},
      });
      expect(Case.fromRecord(r).findGeo, isNull);
    });
  });

  group('CaseSummary.fromRecord', () {
    test('maps the clinical-detail-free summary fields', () {
      final r = RecordModel({
        'id': 'case0000000001',
        'animal': 'anml0000000001',
        'case_number': '2026-014',
        'status': 'disposed',
        'admitted_at': '2026-03-10 09:00:00.000Z',
        'found_at': '',
        'ended_at': '2026-04-01 12:00:00.000Z',
        'org': 'org00000000001',
      });

      final s = CaseSummary.fromRecord(r);

      expect(s.id, 'case0000000001');
      expect(s.animal, 'anml0000000001');
      expect(s.caseNumber, '2026-014');
      expect(s.status, CaseStatus.disposed);
      expect(s.admittedAt?.hour, 9);
      expect(s.foundAt, isNull, reason: 'empty date → null');
      expect(s.endedAt?.month, 4);
      expect(s.org, 'org00000000001');
    });
  });

  group('Animal.fromRecord', () {
    test('maps name, sex, lifetime status, tags', () {
      final r = RecordModel({
        'id': 'anml0000000001',
        'name': 'Lotte',
        'species': 'Stadttaube',
        'sex': 'female',
        'lifetime_status': 'in_aviary',
        'tags': ['ringed', 'resident'],
      });

      final a = Animal.fromRecord(r);
      expect(a.name, 'Lotte');
      expect(a.species, 'Stadttaube');
      expect(a.sex, Sex.female);
      expect(a.lifetimeStatus, LifetimeStatus.inAviary);
      expect(a.tags, ['ringed', 'resident']);
    });
  });

  group('Disposition.fromRecord', () {
    test('maps type and release geo', () {
      final r = RecordModel({
        'id': 'disp000000001',
        'case': 'case0000000001',
        'type': 'released',
        'release_geo': {'lon': 10.0, 'lat': 54.0},
      });
      final d = Disposition.fromRecord(r);
      expect(d.type, DispositionType.released);
      expect(d.caseId, 'case0000000001');
      expect(d.releaseGeo, const GeoPoint(lon: 10, lat: 54));
    });
  });

  group('Exam.fromRecord', () {
    test('maps vitals, enums and denormalized animal', () {
      final r = RecordModel({
        'id': 'exam0000000001',
        'case': 'case0000000001',
        'animal': 'anml0000000001',
        'examined_at': '2026-03-10 09:00:00.000Z',
        'examiner': 'user0000000001',
        'body_condition': 3,
        'hydration': 'moderate',
        'mentation': 'quiet',
        'notes': 'mild dehydration on admission',
      });
      final e = Exam.fromRecord(r);
      expect(e.caseId, 'case0000000001');
      expect(e.animal, 'anml0000000001');
      expect(e.examinedAt?.hour, 9);
      expect(e.examiner, 'user0000000001');
      expect(e.bodyCondition, 3);
      expect(e.hydration, Hydration.moderate);
      expect(e.mentation, Mentation.quiet);
      expect(e.notes, 'mild dehydration on admission');
    });

    test('leaves unset vitals null (a sparse, partial exam)', () {
      final r = RecordModel({
        'id': 'exam0000000002',
        'case': 'case0000000001',
        'animal': 'anml0000000001',
        'body_condition': '',
        'hydration': '',
        'mentation': '',
      });
      final e = Exam.fromRecord(r);
      expect(e.bodyCondition, isNull);
      expect(e.hydration, isNull);
      expect(e.mentation, isNull);
      expect(e.examinedAt, isNull);
    });
  });

  group('ExamFinding.fromRecord', () {
    test('maps system, status and note', () {
      final r = RecordModel({
        'id': 'find0000000001',
        'exam': 'exam0000000001',
        'system': 'legs_feet',
        'status': 'abnormal',
        'note': 'pododermatitis left foot',
      });
      final f = ExamFinding.fromRecord(r);
      expect(f.exam, 'exam0000000001');
      expect(f.system, BodySystem.legsFeet);
      expect(f.status, FindingStatus.abnormal);
      expect(f.note, 'pododermatitis left foot');
    });
  });
}

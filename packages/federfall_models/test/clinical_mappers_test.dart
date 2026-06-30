import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

void main() {
  group('Weight.fromRecord', () {
    test('maps grams, dates and case link', () {
      final r = RecordModel({
        'id': 'wght0000000001',
        'animal': 'anml0000000001',
        'case': 'case0000000001',
        'weight_g': 312.5,
        'measured_at': '2026-03-11 08:30:00.000Z',
        'notes': 'pre-feed',
        'author': 'user0000000001',
        'org': 'org00000000001',
        'created': '2026-03-11 08:31:00.000Z',
        'updated': '2026-03-11 08:32:00.000Z',
      });
      final w = Weight.fromRecord(r);
      expect(w.id, 'wght0000000001');
      expect(w.animal, 'anml0000000001');
      expect(w.caseId, 'case0000000001');
      expect(w.weightG, 312.5);
      expect(w.measuredAt?.hour, 8);
      expect(w.notes, 'pre-feed');
      expect(w.author, 'user0000000001');
      expect(w.org, 'org00000000001');
      expect(w.created?.minute, 31);
      expect(w.updated?.minute, 32);
    });

    test('defaults weight to 0 and leaves optional links null', () {
      final w = Weight.fromRecord(
        RecordModel({'id': 'w', 'animal': 'a', 'weight_g': ''}),
      );
      expect(w.weightG, 0);
      expect(w.caseId, isNull);
      expect(w.measuredAt, isNull);
      expect(w.notes, isNull);
    });
  });

  group('Medication.fromRecord', () {
    test('maps dose, route, frequency-kind and controlled flag', () {
      final r = RecordModel({
        'id': 'medi0000000001',
        'case': 'case0000000001',
        'drug': 'Meloxicam',
        'concentration': '1.5 mg/ml',
        'dose': 0.2,
        'dose_unit': 'mg',
        'frequency': 'twice daily',
        'frequency_kind': 'scheduled',
        'interval_hours': 12,
        'route': 'oral',
        'started_at': '2026-03-12 09:00:00.000Z',
        'ended_at': '2026-03-19 09:00:00.000Z',
        'is_controlled': true,
        'instructions': 'with food',
        'prescribed_by': 'user0000000001',
        'org': 'org00000000001',
      });
      final m = Medication.fromRecord(r);
      expect(m.caseId, 'case0000000001');
      expect(m.drug, 'Meloxicam');
      expect(m.concentration, '1.5 mg/ml');
      expect(m.dose, 0.2);
      expect(m.doseUnit, 'mg');
      expect(m.frequency, 'twice daily');
      expect(m.frequencyKind, MedicationFrequencyKind.scheduled);
      expect(m.intervalHours, 12);
      expect(m.route, MedicationRoute.oral);
      expect(m.startedAt?.day, 12);
      expect(m.endedAt?.day, 19);
      expect(m.isControlled, isTrue);
      expect(m.instructions, 'with food');
      expect(m.prescribedBy, 'user0000000001');
    });

    test('defaults isControlled to false and leaves optionals null', () {
      final m = Medication.fromRecord(
        RecordModel({'id': 'm', 'case': 'c', 'drug': 'Saline'}),
      );
      expect(m.isControlled, isFalse);
      expect(m.dose, isNull);
      expect(m.frequencyKind, isNull);
      expect(m.route, isNull);
      expect(m.startedAt, isNull);
    });
  });

  group('MedicationDue.fromRecord', () {
    test('maps the view fields including the computed next-due', () {
      final r = RecordModel({
        'id': 'medi0000000001',
        'case_id': 'case0000000001',
        'drug': 'Enrofloxacin',
        'dose': 5,
        'dose_unit': 'mg',
        'route': 'subcutaneous',
        'frequency_kind': 'scheduled',
        'interval_hours': 24,
        'started_at': '2026-03-12 09:00:00.000Z',
        'ended_at': '',
        'next_due': '2026-03-13 09:00:00.000Z',
        'active_carer': 'user0000000001',
        'org': 'org00000000001',
      });
      final m = MedicationDue.fromRecord(r);
      expect(m.caseId, 'case0000000001');
      expect(m.drug, 'Enrofloxacin');
      expect(m.dose, 5);
      expect(m.route, MedicationRoute.subcutaneous);
      expect(m.frequencyKind, MedicationFrequencyKind.scheduled);
      expect(m.intervalHours, 24);
      expect(m.startedAt?.day, 12);
      expect(m.endedAt, isNull);
      expect(m.nextDue?.day, 13);
      expect(m.activeCarer, 'user0000000001');
    });
  });

  group('JournalEntry.fromRecord', () {
    test('maps text, entry date and attachment list', () {
      final r = RecordModel({
        'id': 'jrnl0000000001',
        'case': 'case0000000001',
        'text': 'eating well',
        'entry_at': '2026-03-12 18:00:00.000Z',
        'attachments': ['a.jpg', 'b.jpg'],
        'author': 'user0000000001',
        'org': 'org00000000001',
      });
      final j = JournalEntry.fromRecord(r);
      expect(j.caseId, 'case0000000001');
      expect(j.text, 'eating well');
      expect(j.entryAt?.hour, 18);
      expect(j.attachments, ['a.jpg', 'b.jpg']);
      expect(j.author, 'user0000000001');
    });

    test('defaults to no text and an empty attachment list', () {
      final j = JournalEntry.fromRecord(RecordModel({'id': 'j', 'case': 'c'}));
      expect(j.text, '');
      expect(j.attachments, isEmpty);
      expect(j.entryAt, isNull);
    });
  });

  group('FollowUp.fromRecord', () {
    test('maps due/done dates and note', () {
      final r = RecordModel({
        'id': 'flup0000000001',
        'case': 'case0000000001',
        'due_at': '2026-03-15 09:00:00.000Z',
        'note': 'recheck wound',
        'done_at': '2026-03-15 10:00:00.000Z',
        'created_by': 'user0000000001',
        'org': 'org00000000001',
      });
      final f = FollowUp.fromRecord(r);
      expect(f.caseId, 'case0000000001');
      expect(f.dueAt?.day, 15);
      expect(f.note, 'recheck wound');
      expect(f.doneAt?.hour, 10);
      expect(f.createdBy, 'user0000000001');
    });

    test('an open follow-up has no done date', () {
      final f = FollowUp.fromRecord(
        RecordModel({'id': 'f', 'case': 'c', 'done_at': ''}),
      );
      expect(f.doneAt, isNull);
      expect(f.note, isNull);
    });
  });

  group('Placement.fromRecord', () {
    test('maps the chain-of-custody handoff fields', () {
      final r = RecordModel({
        'id': 'plac0000000001',
        'case': 'case0000000001',
        'moved_in_at': '2026-03-12 12:00:00.000Z',
        'carer': 'user0000000001',
        'where_holding': 'home',
        'area': 'flight room',
        'enclosure': 'cage 3',
        'from_user': 'user0000000002',
        'to_user': 'user0000000001',
        'condition_at_handoff': 'stable',
        'comments': 'eating on own',
        'org': 'org00000000001',
      });
      final p = Placement.fromRecord(r);
      expect(p.caseId, 'case0000000001');
      expect(p.movedInAt?.hour, 12);
      expect(p.carer, 'user0000000001');
      expect(p.whereHolding, 'home');
      expect(p.area, 'flight room');
      expect(p.enclosure, 'cage 3');
      expect(p.fromUser, 'user0000000002');
      expect(p.toUser, 'user0000000001');
      expect(p.conditionAtHandoff, 'stable');
      expect(p.comments, 'eating on own');
    });
  });

  group('MedicationAdministration.fromRecord', () {
    test('maps a dose given, denormalized drug/route and plan link', () {
      final r = RecordModel({
        'id': 'mdad0000000001',
        'case': 'case0000000001',
        'drug': 'Meloxicam',
        'medication': 'medi0000000001',
        'dose': 0.2,
        'dose_unit': 'mg',
        'route': 'oral',
        'administered_at': '2026-03-12 09:05:00.000Z',
        'administered_by': 'user0000000001',
        'notes': 'no spit-up',
        'org': 'org00000000001',
      });
      final a = MedicationAdministration.fromRecord(r);
      expect(a.caseId, 'case0000000001');
      expect(a.drug, 'Meloxicam');
      expect(a.medication, 'medi0000000001');
      expect(a.dose, 0.2);
      expect(a.doseUnit, 'mg');
      expect(a.route, MedicationRoute.oral);
      expect(a.administeredAt?.minute, 5);
      expect(a.administeredBy, 'user0000000001');
      expect(a.notes, 'no spit-up');
    });

    test('an ad-hoc dose stands alone with no plan reference', () {
      final a = MedicationAdministration.fromRecord(
        RecordModel(
          {'id': 'x', 'case': 'c', 'drug': 'Glucose', 'medication': ''},
        ),
      );
      expect(a.medication, isNull);
      expect(a.route, isNull);
    });
  });

  group('CaseShare.fromRecord', () {
    test('maps access level and grant metadata', () {
      final r = RecordModel({
        'id': 'shar0000000001',
        'case': 'case0000000001',
        'shared_with': 'user0000000002',
        'access': 'edit',
        'shared_by': 'user0000000001',
        'org': 'org00000000001',
      });
      final s = CaseShare.fromRecord(r);
      expect(s.caseId, 'case0000000001');
      expect(s.sharedWith, 'user0000000002');
      expect(s.access, ShareAccess.edit);
      expect(s.sharedBy, 'user0000000001');
    });

    test('defaults an unknown access to read-only', () {
      final s = CaseShare.fromRecord(
        RecordModel({'id': 's', 'case': 'c', 'shared_with': 'u', 'access': ''}),
      );
      expect(s.access, ShareAccess.read);
    });
  });

  group('Organisation.fromRecord', () {
    test('maps name, contacts and a settings map', () {
      final r = RecordModel({
        'id': 'org00000000001',
        'name': 'Taubenhilfe Hamburg',
        'contact_email': 'info@example.org',
        'contact_phone': '+49 40 123456',
        'settings': {'caseNumberPrefix': '2026', 'quarantineDays': 14},
      });
      final o = Organisation.fromRecord(r);
      expect(o.name, 'Taubenhilfe Hamburg');
      expect(o.contactEmail, 'info@example.org');
      expect(o.contactPhone, '+49 40 123456');
      expect(o.settings['quarantineDays'], 14);
    });

    test('defaults settings to an empty map when absent or malformed', () {
      final o = Organisation.fromRecord(
        RecordModel({'id': 'o', 'name': 'X', 'settings': 'not-a-map'}),
      );
      expect(o.settings, isEmpty);
    });
  });

  group('Aviary.fromRecord', () {
    test('maps keeper, capacity, geo and active flag', () {
      final r = RecordModel({
        'id': 'avir0000000001',
        'name': 'Voliere Nord',
        'keeper': 'user0000000001',
        'location': 'Garten',
        'location_geo': {'lon': 10.1, 'lat': 53.6},
        'capacity': 12,
        'active': true,
        'notes': 'south-facing',
        'org': 'org00000000001',
      });
      final a = Aviary.fromRecord(r);
      expect(a.name, 'Voliere Nord');
      expect(a.keeper, 'user0000000001');
      expect(a.location, 'Garten');
      expect(a.locationGeo, const GeoPoint(lon: 10.1, lat: 53.6));
      expect(a.capacity, 12);
      expect(a.active, isTrue);
      expect(a.notes, 'south-facing');
    });

    test('treats {0,0} geo as no pin and reads inactive', () {
      final a = Aviary.fromRecord(
        RecordModel({
          'id': 'v',
          'name': 'X',
          'location_geo': {'lon': 0, 'lat': 0},
          'active': false,
        }),
      );
      expect(a.locationGeo, isNull);
      expect(a.active, isFalse);
      expect(a.capacity, isNull);
    });
  });

  group('AppUser.fromRecord', () {
    test('maps email, role, flags and contact', () {
      final r = RecordModel({
        'id': 'user0000000001',
        'email': 'carer@example.org',
        'name': 'Mara',
        'role': 'coordinator',
        'org': 'org00000000001',
        'is_active': true,
        'invited_by': 'user0000000002',
        'phone': '+49 170 0000000',
        'verified': true,
        'mfa_enabled': true,
      });
      final u = AppUser.fromRecord(r);
      expect(u.email, 'carer@example.org');
      expect(u.name, 'Mara');
      expect(u.role, UserRole.coordinator);
      expect(u.isActive, isTrue);
      expect(u.invitedBy, 'user0000000002');
      expect(u.phone, '+49 170 0000000');
      expect(u.verified, isTrue);
      expect(u.mfaEnabled, isTrue);
    });

    test('defaults boolean flags to false and role to null', () {
      final u = AppUser.fromRecord(
        RecordModel({'id': 'u', 'email': 'x@y.z', 'role': ''}),
      );
      expect(u.role, isNull);
      expect(u.isActive, isFalse);
      expect(u.verified, isFalse);
      expect(u.mfaEnabled, isFalse);
    });
  });

  group('Finder.fromRecord', () {
    test('maps the GDPR-sensitive contact PII', () {
      final r = RecordModel({
        'id': 'fndr0000000001',
        'first_name': 'Anke',
        'last_name': 'Berger',
        'organisation': 'Feuerwehr',
        'phone': '+49 40 111',
        'alt_phone': '+49 40 222',
        'email': 'anke@example.org',
        'address': 'Hauptstr. 1',
        'postal_code': '20095',
        'city': 'Hamburg',
        'region': 'HH',
        'notes': 'found on balcony',
        'org': 'org00000000001',
      });
      final f = Finder.fromRecord(r);
      expect(f.firstName, 'Anke');
      expect(f.lastName, 'Berger');
      expect(f.organisation, 'Feuerwehr');
      expect(f.phone, '+49 40 111');
      expect(f.altPhone, '+49 40 222');
      expect(f.email, 'anke@example.org');
      expect(f.address, 'Hauptstr. 1');
      expect(f.postalCode, '20095');
      expect(f.city, 'Hamburg');
      expect(f.region, 'HH');
      expect(f.notes, 'found on balcony');
    });

    test('leaves every PII field null on an empty record', () {
      final f = Finder.fromRecord(RecordModel({'id': 'f'}));
      expect(f.firstName, isNull);
      expect(f.lastName, isNull);
      expect(f.email, isNull);
      expect(f.city, isNull);
    });
  });

  group('Marking.fromRecord', () {
    test('maps type, code, scheme and active flag', () {
      final r = RecordModel({
        'id': 'mark0000000001',
        'animal': 'anml0000000001',
        'type': 'association_ring',
        'code': 'DE-1234',
        'scheme_org': 'Vogelwarte',
        'colour': 'red',
        'applied_at': '2026-03-12 09:00:00.000Z',
        'applied_by': 'user0000000001',
        'applied_in_case': 'case0000000001',
        'removed_at': '',
        'removed_reason': '',
        'is_active': true,
        'org': 'org00000000001',
      });
      final m = Marking.fromRecord(r);
      expect(m.animal, 'anml0000000001');
      expect(m.type, 'association_ring');
      expect(m.code, 'DE-1234');
      expect(m.schemeOrg, 'Vogelwarte');
      expect(m.colour, 'red');
      expect(m.appliedAt?.day, 12);
      expect(m.appliedBy, 'user0000000001');
      expect(m.appliedInCase, 'case0000000001');
      expect(m.removedAt, isNull);
      expect(m.isActive, isTrue);
    });

    test('maps an empty type relation to an empty id', () {
      final m = Marking.fromRecord(
        RecordModel({'id': 'm', 'animal': 'a', 'type': ''}),
      );
      expect(m.type, '');
      expect(m.isActive, isFalse);
    });
  });

  group('Condition.fromRecord', () {
    test('maps a notifiable code-list entry', () {
      final r = RecordModel({
        'id': 'cond0000000001',
        'label': 'Trichomoniasis',
        'is_notifiable': true,
        'description': 'protozoal',
        'active': true,
        'org': 'org00000000001',
      });
      final c = Condition.fromRecord(r);
      expect(c.label, 'Trichomoniasis');
      expect(c.isNotifiable, isTrue);
      expect(c.description, 'protozoal');
      expect(c.active, isTrue);
    });

    test('defaults notifiable false and reads inactive', () {
      final c = Condition.fromRecord(
        RecordModel({'id': 'c', 'label': 'X', 'active': false}),
      );
      expect(c.isNotifiable, isFalse);
      expect(c.active, isFalse);
    });
  });

  group('CaseCondition.fromRecord', () {
    test('maps a code-list diagnosis with certainty and dates', () {
      final r = RecordModel({
        'id': 'ccnd0000000001',
        'case': 'case0000000001',
        'condition': 'cond0000000001',
        'free_text': '',
        'certainty': 'confirmed',
        'onset_date': '2026-03-10 00:00:00.000Z',
        'resolved_date': '2026-03-20 00:00:00.000Z',
        'notes': 'responded to treatment',
        'org': 'org00000000001',
      });
      final c = CaseCondition.fromRecord(r);
      expect(c.caseId, 'case0000000001');
      expect(c.condition, 'cond0000000001');
      expect(c.freeText, isNull);
      expect(c.certainty, Certainty.confirmed);
      expect(c.onsetDate?.day, 10);
      expect(c.resolvedDate?.day, 20);
      expect(c.notes, 'responded to treatment');
    });

    test('maps a free-text diagnosis with no certainty', () {
      final c = CaseCondition.fromRecord(
        RecordModel({
          'id': 'cc',
          'case': 'c',
          'free_text': 'suspected fracture',
          'certainty': '',
        }),
      );
      expect(c.freeText, 'suspected fracture');
      expect(c.condition, isNull);
      expect(c.certainty, isNull);
    });
  });

  group('CaseLastActivity.fromRecord', () {
    test('maps the view: record id is the case id', () {
      final r = RecordModel({
        'id': 'case0000000001',
        'last_activity': '2026-03-12 18:00:00.000Z',
        'org': 'org00000000001',
      });
      final a = CaseLastActivity.fromRecord(r);
      expect(a.id, 'case0000000001');
      expect(a.lastActivity?.hour, 18);
      expect(a.org, 'org00000000001');
    });

    test('handles a case with no recorded activity', () {
      final a = CaseLastActivity.fromRecord(
        RecordModel({'id': 'case1', 'last_activity': ''}),
      );
      expect(a.lastActivity, isNull);
    });
  });
}

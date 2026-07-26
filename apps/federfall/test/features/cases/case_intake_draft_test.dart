import 'dart:convert';

import 'package:federfall/features/cases/case_intake_draft.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A draft with every field populated — the round-trip baseline.
  final full = CaseIntakeDraft(
    savedAt: DateTime(2026, 7, 26, 14, 32, 10),
    idempotencyKey: 'key-1',
    step: 2,
    routeAnimalId: 'anim-route',
    linkedAnimalId: 'anim-linked',
    species: 'Stadttaube',
    name: 'Pauli',
    reasons: const ['adre1', 'adre2'],
    ageClass: AgeClass.fledgling,
    foundAt: DateTime(2026, 7, 25),
    admittedAt: DateTime(2026, 7, 26),
    findLocation: 'Bahnhofstr. 1',
    findGeo: const GeoPoint(lon: 8.8, lat: 53.07),
    findCity: 'Oldenburg',
    findRegion: 'Niedersachsen',
    intakeWeight: '280',
    quarantineDays: '14',
    intakeNotes: 'Flügel hängt',
    finderFirstName: 'Anna',
    finderLastName: 'Schmidt',
    finderPhone: '+49 170 0000000',
    finderEmail: 'anna@example.org',
    finderCity: 'Oldenburg',
    photoPaths: const ['/tmp/a.jpg', '/tmp/b.jpg'],
    withExam: true,
  );

  group('encode/decode', () {
    test('round-trips every field', () {
      final back = CaseIntakeDraft.decode(full.encode())!;

      expect(back.savedAt, full.savedAt);
      expect(back.idempotencyKey, 'key-1');
      expect(back.step, 2);
      expect(back.routeAnimalId, 'anim-route');
      expect(back.linkedAnimalId, 'anim-linked');
      expect(back.species, 'Stadttaube');
      expect(back.name, 'Pauli');
      expect(back.reasons, ['adre1', 'adre2']);
      expect(back.ageClass, AgeClass.fledgling);
      expect(back.foundAt, DateTime(2026, 7, 25));
      expect(back.admittedAt, DateTime(2026, 7, 26));
      expect(back.findLocation, 'Bahnhofstr. 1');
      expect(back.findGeo, const GeoPoint(lon: 8.8, lat: 53.07));
      expect(back.findCity, 'Oldenburg');
      expect(back.findRegion, 'Niedersachsen');
      expect(back.intakeWeight, '280');
      expect(back.quarantineDays, '14');
      expect(back.intakeNotes, 'Flügel hängt');
      expect(back.finderFirstName, 'Anna');
      expect(back.finderLastName, 'Schmidt');
      expect(back.finderPhone, '+49 170 0000000');
      expect(back.finderEmail, 'anna@example.org');
      expect(back.finderCity, 'Oldenburg');
      expect(back.photoPaths, ['/tmp/a.jpg', '/tmp/b.jpg']);
      expect(back.withExam, isTrue);
      expect(back.partial, isFalse);
    });

    test('round-trips an all-but-empty draft', () {
      final minimal = CaseIntakeDraft(
        savedAt: DateTime(2026, 7, 26, 9),
        idempotencyKey: 'key-2',
        step: 0,
      );

      final back = CaseIntakeDraft.decode(minimal.encode())!;

      expect(back.routeAnimalId, isNull);
      expect(back.linkedAnimalId, isNull);
      expect(back.species, '');
      expect(back.reasons, isEmpty);
      expect(back.ageClass, isNull);
      expect(back.foundAt, isNull);
      expect(back.admittedAt, isNull);
      expect(back.findGeo, isNull);
      expect(back.findCity, isNull);
      expect(back.photoPaths, isEmpty);
      expect(back.withExam, isFalse);
    });

    test('keeps number fields as raw text, not parsed values', () {
      // The carer sees exactly what they typed on restore — a leading zero
      // must not be normalised away behind their back.
      final draft = CaseIntakeDraft(
        savedAt: DateTime(2026, 7, 26),
        idempotencyKey: 'k',
        step: 1,
        intakeWeight: '0280',
        quarantineDays: '007',
      );

      final back = CaseIntakeDraft.decode(draft.encode())!;

      expect(back.intakeWeight, '0280');
      expect(back.quarantineDays, '007');
    });

    test('a date-only value survives the UTC round-trip unshifted', () {
      // Times travel as UTC; a local midnight must come back as the SAME
      // calendar day rather than sliding across it.
      final draft = CaseIntakeDraft(
        savedAt: DateTime(2026, 7, 26),
        idempotencyKey: 'k',
        step: 1,
        foundAt: DateTime(2026, 7, 25),
      );

      final back = CaseIntakeDraft.decode(draft.encode())!;

      expect(back.foundAt!.year, 2026);
      expect(back.foundAt!.month, 7);
      expect(back.foundAt!.day, 25);
      expect(back.foundAt!.isUtc, isFalse);
    });

    test('a null-island geo point decodes as no location', () {
      // GeoPoint.fromPb treats {lon:0,lat:0} as unset; the draft inherits that
      // so a hand-edited or legacy entry cannot pin a case to the Gulf of
      // Guinea.
      final raw = jsonEncode({
        'v': CaseIntakeDraft.schemaVersion,
        'saved_at': DateTime(2026, 7, 26).toUtc().toIso8601String(),
        'idempotency_key': 'k',
        'step': 0,
        'find_geo': {'lon': 0, 'lat': 0},
      });

      expect(CaseIntakeDraft.decode(raw)!.findGeo, isNull);
    });
  });

  group('decode rejects what is not a usable draft', () {
    test('nothing stored', () {
      expect(CaseIntakeDraft.decode(null), isNull);
      expect(CaseIntakeDraft.decode(''), isNull);
    });

    test('not JSON, or JSON that is not an object', () {
      expect(CaseIntakeDraft.decode('not json'), isNull);
      expect(CaseIntakeDraft.decode('[1,2,3]'), isNull);
      expect(CaseIntakeDraft.decode('"a string"'), isNull);
    });

    test('a draft written by another schema version', () {
      final other = jsonDecode(full.encode()) as Map<String, dynamic>
        ..['v'] = CaseIntakeDraft.schemaVersion + 1;

      expect(CaseIntakeDraft.decode(jsonEncode(other)), isNull);
    });

    test('an unversioned draft', () {
      final other = jsonDecode(full.encode()) as Map<String, dynamic>
        ..remove('v');

      expect(CaseIntakeDraft.decode(jsonEncode(other)), isNull);
    });

    test('a draft missing its timestamp or key', () {
      for (final missing in ['saved_at', 'idempotency_key']) {
        final other = jsonDecode(full.encode()) as Map<String, dynamic>
          ..remove(missing);
        expect(
          CaseIntakeDraft.decode(jsonEncode(other)),
          isNull,
          reason: 'without $missing',
        );
      }
    });

    test('an unparseable timestamp or blank key', () {
      final badDate = jsonDecode(full.encode()) as Map<String, dynamic>
        ..['saved_at'] = 'yesterday';
      final blankKey = jsonDecode(full.encode()) as Map<String, dynamic>
        ..['idempotency_key'] = '';

      expect(CaseIntakeDraft.decode(jsonEncode(badDate)), isNull);
      expect(CaseIntakeDraft.decode(jsonEncode(blankKey)), isNull);
    });
  });

  test('wrongly typed fields degrade to defaults instead of throwing', () {
    // A draft is untrusted input: on web it sits in localStorage where anyone
    // can hand-edit it. A mangled entry must open a usable wizard, not crash
    // it on the first frame.
    final raw = jsonEncode({
      'v': CaseIntakeDraft.schemaVersion,
      'saved_at': DateTime(2026, 7, 26).toUtc().toIso8601String(),
      'idempotency_key': 'k',
      'step': 'two',
      'species': 42,
      'reasons': [1, 'adre1', null],
      'age_class': 'nonsense',
      'found_at': 12345,
      'find_geo': 'somewhere',
      'photo_paths': 'a.jpg',
      'with_exam': 'yes',
      'partial': 1,
    });

    final draft = CaseIntakeDraft.decode(raw)!;

    expect(draft.step, 0);
    expect(draft.species, '');
    expect(draft.reasons, ['adre1']);
    expect(draft.ageClass, isNull);
    expect(draft.foundAt, isNull);
    expect(draft.findGeo, isNull);
    expect(draft.photoPaths, isEmpty);
    expect(draft.withExam, isFalse);
    expect(draft.partial, isFalse);
  });

  group('staleness', () {
    final draft = CaseIntakeDraft(
      savedAt: DateTime(2026, 7, 26, 12),
      idempotencyKey: 'k',
      step: 0,
    );

    test('is fresh right up to the cutoff', () {
      expect(
        draft.isStaleAt(draft.savedAt.add(CaseIntakeDraft.maxAge)),
        isFalse,
      );
    });

    test('is stale past the cutoff', () {
      expect(
        draft.isStaleAt(
          draft.savedAt
              .add(CaseIntakeDraft.maxAge)
              .add(
                const Duration(seconds: 1),
              ),
        ),
        isTrue,
      );
    });
  });

  group('hasFinder', () {
    CaseIntakeDraft withFinder({String first = '', String phone = ''}) =>
        CaseIntakeDraft(
          savedAt: DateTime(2026, 7, 26),
          idempotencyKey: 'k',
          step: 0,
          finderFirstName: first,
          finderPhone: phone,
        );

    test('is false for a blank or whitespace-only section', () {
      expect(withFinder().hasFinder, isFalse);
      expect(withFinder(first: '   ').hasFinder, isFalse);
    });

    test('is true as soon as any field carries input', () {
      expect(withFinder(phone: '0170').hasFinder, isTrue);
    });
  });

  group('forPlaintextStore', () {
    test('drops the finder PII and the photo paths, and says so', () {
      final reduced = full.forPlaintextStore();

      expect(reduced.finderFirstName, '');
      expect(reduced.finderLastName, '');
      expect(reduced.finderPhone, '');
      expect(reduced.finderEmail, '');
      expect(reduced.finderCity, '');
      expect(reduced.hasFinder, isFalse);
      expect(reduced.photoPaths, isEmpty);
      expect(reduced.partial, isTrue);
    });

    test('no PII survives into the encoded form', () {
      // The point of the reduction: none of these strings may reach a
      // script-readable store.
      final encoded = full.forPlaintextStore().encode();

      for (final pii in [
        'Anna',
        'Schmidt',
        '+49 170 0000000',
        'anna@example.org',
      ]) {
        expect(encoded, isNot(contains(pii)), reason: pii);
      }
    });

    test('keeps everything else intact', () {
      final reduced = full.forPlaintextStore();

      expect(reduced.idempotencyKey, 'key-1');
      expect(reduced.savedAt, full.savedAt);
      expect(reduced.step, 2);
      expect(reduced.routeAnimalId, 'anim-route');
      expect(reduced.linkedAnimalId, 'anim-linked');
      expect(reduced.species, 'Stadttaube');
      expect(reduced.name, 'Pauli');
      expect(reduced.reasons, ['adre1', 'adre2']);
      expect(reduced.ageClass, AgeClass.fledgling);
      expect(reduced.foundAt, full.foundAt);
      expect(reduced.admittedAt, full.admittedAt);
      expect(reduced.findLocation, 'Bahnhofstr. 1');
      expect(reduced.findGeo, full.findGeo);
      expect(reduced.findCity, 'Oldenburg');
      expect(reduced.findRegion, 'Niedersachsen');
      expect(reduced.intakeWeight, '280');
      expect(reduced.quarantineDays, '14');
      expect(reduced.intakeNotes, 'Flügel hängt');
      expect(reduced.withExam, isTrue);
    });

    test('is not flagged partial when there was nothing to drop', () {
      final draft = CaseIntakeDraft(
        savedAt: DateTime(2026, 7, 26),
        idempotencyKey: 'k',
        step: 1,
        species: 'Stadttaube',
      );

      expect(draft.forPlaintextStore().partial, isFalse);
    });

    test('stays flagged partial once reduced, even applied twice', () {
      expect(full.forPlaintextStore().forPlaintextStore().partial, isTrue);
    });
  });
}

import 'package:federfall/features/cases/case_intake_draft.dart';
import 'package:federfall/features/cases/case_intake_draft_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final draft = CaseIntakeDraft(
    savedAt: DateTime(2026, 7, 26, 14, 32),
    idempotencyKey: 'key-1',
    step: 2,
    species: 'Stadttaube',
    intakeNotes: 'Flügel hängt',
    finderFirstName: 'Anna',
    finderPhone: '+49 170 0000000',
    photoPaths: const ['/tmp/a.jpg'],
  );

  group('SecureCaseIntakeDraftStore', () {
    late MockSecureStorage storage;
    late SecureCaseIntakeDraftStore store;
    // Stands in for the keystore so a write can be read back.
    String? stored;

    setUp(() {
      stored = null;
      storage = MockSecureStorage();
      store = SecureCaseIntakeDraftStore(storage);
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        stored = invocation.namedArguments[#value] as String?;
      });
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => stored);
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async => stored = null);
    });

    test('reads back what it wrote, finder contact included', () async {
      // On native the draft lives in the keychain/keystore, so unlike the web
      // fallback it may hold the finder's details.
      await store.write(draft);
      final back = await store.read();

      expect(back!.idempotencyKey, 'key-1');
      expect(back.species, 'Stadttaube');
      expect(back.finderFirstName, 'Anna');
      expect(back.finderPhone, '+49 170 0000000');
      expect(back.photoPaths, ['/tmp/a.jpg']);
      expect(back.partial, isFalse);
    });

    test('an empty store reads as no draft', () async {
      expect(await store.read(), isNull);
    });

    test('a corrupted entry reads as no draft', () async {
      stored = '{ not json';

      expect(await store.read(), isNull);
    });

    test('clear removes the entry', () async {
      await store.write(draft);
      await store.clear();

      expect(await store.read(), isNull);
      verify(() => storage.delete(key: any(named: 'key'))).called(1);
    });
  });

  group('PrefsCaseIntakeDraftStore (web fallback)', () {
    late PrefsCaseIntakeDraftStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = PrefsCaseIntakeDraftStore();
    });

    test('reads back the draft without the finder or the photos', () async {
      await store.write(draft);
      final back = await store.read();

      expect(back!.idempotencyKey, 'key-1');
      expect(back.species, 'Stadttaube');
      expect(back.intakeNotes, 'Flügel hängt');
      // Dropped on the way in — localStorage is readable by any script in the
      // origin, and these are a third party's contact details.
      expect(back.hasFinder, isFalse);
      expect(back.photoPaths, isEmpty);
      // ...and the draft says so, so the restore prompt can warn.
      expect(back.partial, isTrue);
    });

    test('the finder PII never reaches the backing store', () async {
      await store.write(draft);

      final raw = (await SharedPreferences.getInstance()).getString(
        'federfall.case_intake_draft',
      )!;

      expect(raw, isNot(contains('Anna')));
      expect(raw, isNot(contains('+49 170 0000000')));
      expect(raw, contains('Stadttaube'));
    });

    test('an empty store reads as no draft', () async {
      expect(await store.read(), isNull);
    });

    test('a hand-edited entry reads as no draft', () async {
      SharedPreferences.setMockInitialValues({
        'federfall.case_intake_draft': 'tampered',
      });

      expect(await PrefsCaseIntakeDraftStore().read(), isNull);
    });

    test('clear removes the entry', () async {
      await store.write(draft);
      await store.clear();

      expect(await store.read(), isNull);
    });
  });
}

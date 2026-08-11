import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  group('isCatchAllLabel', () {
    test('matches the whole label, case- and space-insensitively', () {
      expect(isCatchAllLabel('Sonstiges'), isTrue);
      expect(isCatchAllLabel('  other '), isTrue);
      expect(isCatchAllLabel('UNBEKANNT'), isTrue);
    });

    test('does not match a label that merely starts with one', () {
      // A diagnosis named "Sonstige Verletzung" is a diagnosis, not the
      // catch-all, and belongs in its alphabetical place.
      expect(isCatchAllLabel('Sonstige Verletzung'), isFalse);
      expect(isCatchAllLabel('Other injury'), isFalse);
      expect(isCatchAllLabel('Verletzung'), isFalse);
    });
  });

  group('catchAllLast', () {
    test('appends the catch-all and leaves every other entry in place', () {
      expect(
        catchAllLast([
          'Krankheit',
          'Sonstiges',
          'Trauma',
          'Verletzung',
        ], (s) => s),
        ['Krankheit', 'Trauma', 'Verletzung', 'Sonstiges'],
      );
    });

    test('preserves the incoming order among several catch-alls', () {
      // The server's order is the only order this has an opinion about
      // relative to: a partition, not a sort, so nothing else moves.
      expect(
        catchAllLast(['Andere', 'Krankheit', 'Sonstiges'], (s) => s),
        ['Krankheit', 'Andere', 'Sonstiges'],
      );
    });

    test('is a no-op on a list without one', () {
      expect(catchAllLast(['Krankheit', 'Trauma'], (s) => s), [
        'Krankheit',
        'Trauma',
      ]);
    });
  });

  group('CodelistRepository', () {
    late _MockPb pb;
    late _MockService service;

    setUp(() {
      pb = _MockPb();
      service = _MockService();
      when(() => pb.collection('admission_reasons')).thenReturn(service);
      when(() => pb.filter(any(), any())).thenAnswer(
        (i) => i.positionalArguments[0] as String,
      );
      when(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      ).thenAnswer(
        (_) async => ResultList(
          items: [
            RecordModel({'id': 'r1', 'label': 'Krankheit', 'active': true}),
            RecordModel({'id': 'r2', 'label': 'Sonstiges', 'active': true}),
            RecordModel({'id': 'r3', 'label': 'Trauma', 'active': true}),
          ],
        ),
      );
    });

    test('codelist() sorts by label server-side, catch-all last', () async {
      final entries = await PbAdmissionReasonsRepository(pb).codelist();

      // federfall-do0l: alphabetically "Sonstiges" sits between the two, where
      // a reader scanning the chips stops and assumes the list ended.
      expect(
        [for (final e in entries) e.label],
        [
          'Krankheit',
          'Trauma',
          'Sonstiges',
        ],
      );
      expect(
        verify(
          () => service.getList(
            page: any(named: 'page'),
            perPage: any(named: 'perPage'),
            skipTotal: any(named: 'skipTotal'),
            filter: captureAny(named: 'filter'),
            sort: captureAny(named: 'sort'),
            expand: any(named: 'expand'),
          ),
        ).captured,
        [null, 'label'],
      );
    });

    test('active() narrows to live entries and orders them the same', () async {
      final entries = await PbAdmissionReasonsRepository(pb).active();

      expect(
        [for (final e in entries) e.label],
        [
          'Krankheit',
          'Trauma',
          'Sonstiges',
        ],
      );
      verify(() => pb.filter('active = true')).called(1);
    });
  });
}

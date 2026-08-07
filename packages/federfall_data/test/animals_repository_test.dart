import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late PbAnimalsRepository repo;

  setUp(() {
    pb = _MockPb();
    repo = PbAnimalsRepository(pb);
  });

  group('browse()', () {
    late _MockService service;

    /// The (filter, sort, fields) actually sent, with the params spliced into
    /// the filter so the bound expression is visible.
    List<Object?> capturedQuery() => verify(
      () => service.getList(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        skipTotal: any(named: 'skipTotal'),
        filter: captureAny(named: 'filter'),
        sort: captureAny(named: 'sort'),
        expand: any(named: 'expand'),
        fields: captureAny(named: 'fields'),
      ),
    ).captured;

    setUp(() {
      service = _MockService();
      when(() => pb.collection('animals')).thenReturn(service);
      when(() => pb.filter(any(), any())).thenAnswer((i) {
        var expr = i.positionalArguments.first as String;
        final params = i.positionalArguments[1] as Map<String, dynamic>? ?? {};
        for (final param in params.entries) {
          expr = expr.replaceAll('{:${param.key}}', "'${param.value}'");
        }
        return expr;
      });
      when(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer(
        (_) async => ResultList(
          items: [
            RecordModel({'id': 'anml1', 'name': 'Berta', 'species': 'Taube'}),
          ],
        ),
      );
    });

    test('no search term asks for the registry in name order', () async {
      final page = await repo.browse();

      expect(page.items.single.id, 'anml1');
      final q = capturedQuery();
      expect(q[0], isNull);
      // Ascending, tie-broken by id — the key the cursor is built from.
      expect(q[1], 'name,id');
    });

    test('a search term matches the name or any marking code', () async {
      await repo.browse(text: ' DE-1 ');

      // Trimmed, and one parenthesised OR group so a keyset clause cannot be
      // swallowed by the second alternative.
      expect(
        capturedQuery()[0],
        "(name ~ 'DE-1' || markings_via_animal.code ~ 'DE-1')",
      );
    });

    test('the next page resumes past the last name AND id', () async {
      await repo.browse(
        after: const PbCursor(value: 'Berta', id: 'anml1'),
      );

      // `>` because the order ascends; the id breaks the tie between the many
      // animals that share a name (or share the empty one).
      expect(
        capturedQuery()[0],
        "(name > 'Berta' || (name = 'Berta' && id > 'anml1'))",
      );
    });

    test('a full page hands back a cursor built from the sort key', () async {
      final page = await repo.browse(perPage: 1);

      expect(page.hasMore, isTrue);
      expect(page.cursor, const PbCursor(value: 'Berta', id: 'anml1'));
    });
  });

  group('merge()', () {
    void stubSend(Map<String, dynamic> response) {
      when(
        () => pb.send<Map<String, dynamic>>(
          any(),
          method: any(named: 'method'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => response);
    }

    test(
      'posts survivor/duplicate/fields to the atomic route, returns the id',
      () async {
        stubSend({'id': 'anml_survivor'});

        final result = await repo.merge(
          survivor: 'anml_survivor',
          duplicate: 'anml_duplicate',
          fields: {'name': 'duplicate', 'species': 'survivor'},
        );

        expect(result, 'anml_survivor');
        final captured = verify(
          () => pb.send<Map<String, dynamic>>(
            captureAny(),
            method: captureAny(named: 'method'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        expect(captured[0], '/api/federfall/merge-animals');
        expect(captured[1], 'POST');
        final body = captured[2] as Map<String, dynamic>;
        expect(body['survivor'], 'anml_survivor');
        expect(body['duplicate'], 'anml_duplicate');
        expect(body['fields'], {'name': 'duplicate', 'species': 'survivor'});
      },
    );

    test(
      'a response missing the surviving id surfaces as unknownOutcome',
      () async {
        stubSend({});

        await expectLater(
          () => repo.merge(survivor: 's1', duplicate: 'd1'),
          throwsA(
            isA<RepositoryException>().having(
              (e) => e.kind,
              'kind',
              RepositoryErrorKind.unknownOutcome,
            ),
          ),
        );
      },
    );
  });
}

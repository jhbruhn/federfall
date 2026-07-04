import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

void main() {
  late _MockPb pb;
  late PbAnimalsRepository repo;

  setUp(() {
    pb = _MockPb();
    repo = PbAnimalsRepository(pb);
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

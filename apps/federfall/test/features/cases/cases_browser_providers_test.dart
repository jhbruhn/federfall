import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

void main() {
  late MockCasesRepo cases;
  late MockAnimalsRepo animals;

  setUp(() {
    cases = MockCasesRepo();
    animals = MockAnimalsRepo();
    when(
      () => animals.list(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async => const []);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      // Riverpod 3 retries a failed provider on its own, which keeps it in the
      // loading state forever and makes an error assertion time out rather than
      // fail. What is under test is the first failure, not the retry policy.
      retry: (_, _) => null,
      overrides: [
        casesRepositoryProvider.overrideWith((ref) async => cases),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        currentUserProvider.overrideWith((ref) async => null),
        activeMarkingCodesByAnimalProvider.overrideWith(
          (ref) async => const {},
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a dropped connection surfaces as itself, not wrapped', () {
    // federfall-s5mm, end to end on the busiest screen in the app. Gathered
    // with `(a, b, …).wait` this arrived as a ParallelWaitError, which
    // `isNetworkError` does not recognise — so the case browser showed a
    // generic error and threw away the list, the scroll position and the
    // filters, instead of keeping them until the connection returned.
    when(
      () => cases.list(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer(
      (_) => Future.error(
        const RepositoryException(
          'Could not reach the server',
          kind: RepositoryErrorKind.network,
        ),
      ),
    );

    return expectLater(
      makeContainer().read(casesBrowserDataProvider.future),
      throwsA(
        isA<RepositoryException>().having(
          (e) => e.kind,
          'kind',
          RepositoryErrorKind.network,
        ),
      ),
    );
  });

  test('the gathered reads still all land on the happy path', () async {
    when(
      () => cases.list(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async => const []);

    final data = await makeContainer().read(casesBrowserDataProvider.future);

    expect(data.cases, isEmpty);
    expect(data.animalsById, isEmpty);
    expect(data.myUserId, '');
  });
}

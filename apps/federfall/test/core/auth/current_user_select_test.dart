import 'dart:async';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepo extends Mock implements AuthRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

AppUser _user(String id) =>
    AppUser(id: id, email: '$id@example.org', role: UserRole.carer);

void main() {
  late MockAuthRepo auth;
  late MockCasesRepo cases;
  late MockAnimalsRepo animals;
  late StreamController<AppUser?> authChanges;
  // A counter, not `verify(...).callCount`: mocktail marks calls as verified,
  // so a second verify in the same test counts only what happened since the
  // first and reports zero.
  late int caseReads;

  setUp(() {
    caseReads = 0;
    auth = MockAuthRepo();
    cases = MockCasesRepo();
    animals = MockAnimalsRepo();
    authChanges = StreamController<AppUser?>.broadcast();
    addTearDown(authChanges.close);

    when(() => auth.changes).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenReturn(_user('me'));
    when(
      () => cases.list(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async {
      caseReads++;
      return const [];
    });
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
      overrides: [
        // The REAL currentUserProvider, driven through its repository — the
        // selectAsync behaviour under test lives in that provider's plumbing,
        // so overriding it would test nothing.
        authRepositoryProvider.overrideWith((ref) async => auth),
        casesRepositoryProvider.overrideWith((ref) async => cases),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        activeMarkingCodesByAnimalProvider.overrideWith(
          (ref) async => const {},
        ),
      ],
    );
    addTearDown(container.dispose);
    // Subscribed, so a dependency change propagates eagerly instead of waiting
    // for the next read — otherwise "did it refetch?" only ever measures the
    // read itself.
    container.listen(
      casesBrowserDataProvider,
      (_, _) {},
      onError: (_, _) {},
    );
    return container;
  }

  test('a token refresh does not refetch the case list', () async {
    // federfall-bpw6: sessionRefresh rolls the token on
    // AppLifecycleListener.onResume, which on web is every window refocus.
    // That saves the auth store, so `changes` emits — with an identical user.
    // Watching `currentUserProvider.future` re-ran this whole load each time;
    // selecting the id means the same id changes nothing.
    final container = makeContainer();
    await container.read(casesBrowserDataProvider.future);
    expect(caseReads, 1);

    authChanges.add(_user('me'));
    // Generous on purpose: a wait too short to let a refetch happen would make
    // this pass for the wrong reason. The contrasting test below refetches
    // within the same window.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await container.read(casesBrowserDataProvider.future);

    expect(caseReads, 1, reason: 'the signed-in id did not change');
  });

  test('signing in as someone else does refetch', () async {
    // The other half: the dependency must still be real. "Mine" is resolved
    // client-side from this id, so a different user has to reload.
    final container = makeContainer();
    await container.read(casesBrowserDataProvider.future);
    expect(caseReads, 1);

    when(() => auth.currentUser).thenReturn(_user('someone-else'));
    authChanges.add(_user('someone-else'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final data = await container.read(casesBrowserDataProvider.future);

    expect(caseReads, 2);
    expect(data.myUserId, 'someone-else');
  });
}

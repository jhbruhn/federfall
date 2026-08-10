import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSharesRepo extends Mock implements PbCaseSharesRepository {}

/// How the app gets custody's four facts — the predicate itself is covered in
/// `test/core/auth/roles_test.dart`. What matters here is the plumbing:
/// coordinators cost nothing, the share branch is one user-wide query, and an
/// enclosure that will not load does not take the rest of the answer with it.
void main() {
  const carer = AppUser(id: 'me', email: 'me@x.org', org: 'org1');
  const coordinator = AppUser(
    id: 'coord',
    email: 'c@x.org',
    org: 'org1',
    role: UserRole.coordinator,
  );

  late _MockSharesRepo shares;

  setUp(() {
    shares = _MockSharesRepo();
    when(() => shares.editSharedWith(any())).thenAnswer((_) async => const []);
  });

  ProviderContainer makeContainer({
    AppUser? me = carer,
    Animal animal = const Animal(id: 'a1', species: 'Columba livia'),
    List<CaseSummary> cases = const [],
    Aviary? aviary,
    bool aviaryFails = false,
  }) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        currentUserProvider.overrideWith((ref) async => me),
        caseSharesRepositoryProvider.overrideWith((ref) async => shares),
        animalByIdProvider('a1').overrideWith((ref) async => animal),
        caseSummariesForAnimalProvider('a1').overrideWith((ref) async => cases),
        aviaryByIdProvider('av1').overrideWith((ref) async {
          if (aviaryFails) throw Exception('enclosure unreachable');
          return aviary ?? const Aviary(id: 'av1', name: 'V1', keeper: 'other');
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a coordinator resolves without reading anything', () async {
    // No animal/case/share override is even consulted: the role short-circuits,
    // which is what keeps the override from costing a request per screen.
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        currentUserProvider.overrideWith((ref) async => coordinator),
      ],
    );
    addTearDown(container.dispose);

    final custody = await container.read(animalCustodyProvider('a1').future);
    expect(custody.canWrite, isTrue);
    expect(custody.canOpenCase, isTrue);
    verifyNever(() => shares.editSharedWith(any()));
  });

  test('a signed-out session holds nothing', () async {
    final container = makeContainer(me: null);
    final custody = await container.read(animalCustodyProvider('a1').future);
    expect(custody.canWrite, isFalse);
    expect(custody.canOpenCase, isFalse);
  });

  test('the active carer of an open case holds the bird', () async {
    final container = makeContainer(
      cases: const [CaseSummary(id: 'c1', animal: 'a1', activeCarer: 'me')],
    );
    expect(await container.read(canWriteAnimalProvider('a1').future), isTrue);
  });

  test('an edit share is read once, user-wide, and grants custody', () async {
    when(() => shares.editSharedWith('me')).thenAnswer(
      (_) async => const [
        CaseShare(
          id: 's1',
          caseId: 'c1',
          sharedWith: 'me',
          access: ShareAccess.edit,
        ),
      ],
    );
    final container = makeContainer(
      cases: const [CaseSummary(id: 'c1', animal: 'a1', activeCarer: 'other')],
    );

    expect(await container.read(canWriteAnimalProvider('a1').future), isTrue);
    // Both derived providers share the one resolution, so the query runs once
    // however many controls watch it.
    expect(
      await container.read(canOpenCaseOnAnimalProvider('a1').future),
      isTrue,
    );
    verify(() => shares.editSharedWith('me')).called(1);
  });

  test("another carer's open case leaves the bird theirs", () async {
    final container = makeContainer(
      cases: const [CaseSummary(id: 'c1', animal: 'a1', activeCarer: 'other')],
    );
    expect(await container.read(canWriteAnimalProvider('a1').future), isFalse);
    expect(
      await container.read(canOpenCaseOnAnimalProvider('a1').future),
      isFalse,
    );
  });

  test('the enclosure is resolved to find its keeper', () async {
    final container = makeContainer(
      animal: const Animal(
        id: 'a1',
        species: 'Columba livia',
        currentAviary: 'av1',
      ),
      aviary: const Aviary(id: 'av1', name: 'V1', keeper: 'me'),
    );
    expect(await container.read(canWriteAnimalProvider('a1').future), isTrue);
  });

  // Same tolerance as `lib_custody.js`'s holds(): the enclosure grants nothing
  // rather than throwing — and the case branch still answers.
  test('an unreadable enclosure does not fail the whole answer', () async {
    final container = makeContainer(
      animal: const Animal(
        id: 'a1',
        species: 'Columba livia',
        currentAviary: 'av1',
      ),
      cases: const [CaseSummary(id: 'c1', animal: 'a1', activeCarer: 'me')],
      aviaryFails: true,
    );
    final custody = await container.read(animalCustodyProvider('a1').future);
    expect(custody.canWrite, isTrue);
  });

  test('and it does not turn a housed bird into one at large', () async {
    final container = makeContainer(
      animal: const Animal(
        id: 'a1',
        species: 'Columba livia',
        currentAviary: 'av1',
      ),
      aviaryFails: true,
    );
    final custody = await container.read(animalCustodyProvider('a1').future);
    expect(custody.canWrite, isFalse);
    // Housed is read off the animal, so "nobody holds it" stays false.
    expect(custody.canOpenCase, isFalse);
  });

  test('a bird nobody holds can be admitted but not written about', () async {
    final container = makeContainer(
      animal: const Animal(
        id: 'a1',
        species: 'Columba livia',
        lifetimeStatus: LifetimeStatus.atLargeReleased,
      ),
    );
    final custody = await container.read(animalCustodyProvider('a1').future);
    expect(custody.canWrite, isFalse);
    expect(custody.canOpenCase, isTrue);
  });

  test('myEditSharedCaseIds is empty for a signed-out session', () async {
    final container = makeContainer(me: null);
    expect(await container.read(myEditSharedCaseIdsProvider.future), isEmpty);
    verifyNever(() => shares.editSharedWith(any()));
  });
}

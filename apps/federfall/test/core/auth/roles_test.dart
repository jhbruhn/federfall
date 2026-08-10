import 'package:federfall/core/auth/roles.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A case carried by someone else, so editability comes only from role/share.
  const medicalCase = Case(id: 'c1', animal: 'a1', activeCarer: 'carer1');

  AppUser user(String id, UserRole role) =>
      AppUser(id: id, email: '$id@x.org', role: role);

  CaseShare share(String withId, ShareAccess access) => CaseShare(
    id: 's-$withId',
    caseId: 'c1',
    sharedWith: withId,
    access: access,
  );

  group('caseEditableBy', () {
    test('a signed-out user can never edit', () {
      expect(caseEditableBy(medicalCase, null, const []), isFalse);
    });

    test('a supervisor can edit any case', () {
      expect(
        caseEditableBy(medicalCase, user('sup', UserRole.supervisor), const []),
        isTrue,
      );
    });

    test('the active carer can edit', () {
      expect(
        caseEditableBy(
          const Case(id: 'c1', animal: 'a1', activeCarer: 'me'),
          user('me', UserRole.carer),
          const [],
        ),
        isTrue,
      );
    });

    test('a user shared with edit access can edit', () {
      expect(
        caseEditableBy(medicalCase, user('me', UserRole.carer), [
          share('me', ShareAccess.edit),
        ]),
        isTrue,
      );
    });

    test('a user shared with only read access cannot edit', () {
      expect(
        caseEditableBy(medicalCase, user('me', UserRole.carer), [
          share('me', ShareAccess.read),
        ]),
        isFalse,
      );
    });

    test('a coordinator who is not the carer cannot edit (view only)', () {
      expect(
        caseEditableBy(
          medicalCase,
          user('coord', UserRole.coordinator),
          const [],
        ),
        isFalse,
      );
    });

    test('an unrelated carer cannot edit', () {
      expect(
        caseEditableBy(medicalCase, user('other', UserRole.carer), [
          share('someone-else', ShareAccess.edit),
        ]),
        isFalse,
      );
    });
  });

  // The result matrix the epic (federfall-q7ks) verified against a live
  // PocketBase 0.39.8, restated against the app-side mirror so the two cannot
  // drift. `animalWritableBy` reproduces 1700000077's rule; every row below
  // names the branch it exercises.
  group('animalWritableBy', () {
    const atLarge = Animal(
      id: 'a1',
      species: 'Columba livia',
      lifetimeStatus: LifetimeStatus.atLargeReleased,
    );
    const resident = Animal(
      id: 'a1',
      species: 'Columba livia',
      currentAviary: 'av1',
      lifetimeStatus: LifetimeStatus.inAviary,
    );
    const aviary = Aviary(id: 'av1', name: 'Voliere 1', keeper: 'keeper');

    CaseSummary openCase(String id, String carer) =>
        CaseSummary(id: id, animal: 'a1', activeCarer: carer);
    CaseSummary closedCase(String id, String carer) => CaseSummary(
      id: id,
      animal: 'a1',
      activeCarer: carer,
      status: CaseStatus.disposed,
    );

    bool writable(
      Animal animal,
      AppUser? me, {
      Aviary? aviary,
      List<CaseSummary> cases = const [],
      Set<String> editShares = const {},
    }) => animalWritableBy(
      animal,
      me,
      aviary: aviary,
      cases: cases,
      editSharedCaseIds: editShares,
    );

    test('a signed-out user holds nothing', () {
      expect(writable(atLarge, null), isFalse);
    });

    test('the active carer of an open case holds the bird', () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: [openCase('c1', 'me')],
        ),
        isTrue,
      );
    });

    test('ready_for_release still counts as held', () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: const [
            CaseSummary(
              id: 'c1',
              animal: 'a1',
              activeCarer: 'me',
              status: CaseStatus.readyForRelease,
            ),
          ],
        ),
        isTrue,
      );
    });

    test('a status-less case counts as open, matching the rule\'s ""', () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: [openCase('c1', 'me')],
        ),
        isTrue,
      );
    });

    test('an edit share on the open case holds the bird', () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: [openCase('c1', 'carer1')],
          editShares: const {'c1'},
        ),
        isTrue,
      );
    });

    test('a read share on the open case does not — it is not an edit id', () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: [openCase('c1', 'carer1')],
        ),
        isFalse,
      );
    });

    test('the carer of a disposed case has handed the bird back', () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: [closedCase('c1', 'me')],
        ),
        isFalse,
      );
    });

    test('an edit share on a disposed case grants nothing', () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: [closedCase('c1', 'carer1')],
          editShares: const {'c1'},
        ),
        isFalse,
      );
    });

    // The trap the server rule had to be probed for: the clauses must bind to
    // the SAME case. A closed case of mine plus somebody else's open one must
    // not add up to custody.
    test("my closed case + another carer's open one is still refused", () {
      expect(
        writable(
          atLarge,
          user('me', UserRole.carer),
          cases: [closedCase('c1', 'me'), openCase('c2', 'carer1')],
        ),
        isFalse,
      );
    });

    test('an unrelated carer holds nothing', () {
      expect(
        writable(
          atLarge,
          user('other', UserRole.carer),
          cases: [openCase('c1', 'carer1')],
        ),
        isFalse,
      );
    });

    test('the keeper of the enclosure holds its residents', () {
      expect(
        writable(resident, user('keeper', UserRole.carer), aviary: aviary),
        isTrue,
      );
    });

    test('another carer does not hold a resident bird', () {
      expect(
        writable(resident, user('other', UserRole.carer), aviary: aviary),
        isFalse,
      );
    });

    // Custody keys on the live facts, not on the derived label that lags
    // (federfall-sinp): a resident under treatment still reads `in_aviary`.
    test('a resident under treatment belongs to its carer, not the keeper '
        'alone', () {
      expect(
        writable(
          resident,
          user('me', UserRole.carer),
          aviary: aviary,
          cases: [openCase('c1', 'me')],
        ),
        isTrue,
      );
    });

    test('a coordinator overrides every branch', () {
      expect(writable(resident, user('coord', UserRole.coordinator)), isTrue);
    });

    test('a supervisor overrides every branch', () {
      expect(writable(resident, user('sup', UserRole.supervisor)), isTrue);
    });
  });

  group('animalAdmissibleBy', () {
    const atLarge = Animal(
      id: 'a1',
      species: 'Columba livia',
      lifetimeStatus: LifetimeStatus.atLargeReleased,
    );
    const dead = Animal(
      id: 'a1',
      species: 'Columba livia',
      lifetimeStatus: LifetimeStatus.deceased,
    );
    const resident = Animal(
      id: 'a1',
      species: 'Columba livia',
      currentAviary: 'av1',
      lifetimeStatus: LifetimeStatus.inAviary,
    );
    const aviary = Aviary(id: 'av1', name: 'Voliere 1', keeper: 'keeper');

    bool admissible(
      Animal animal,
      AppUser? me, {
      Aviary? aviary,
      List<CaseSummary> cases = const [],
    }) => animalAdmissibleBy(
      animal,
      me,
      aviary: aviary,
      cases: cases,
      editSharedCaseIds: const {},
    );

    test("a bird nobody holds is anyone's to admit", () {
      expect(admissible(atLarge, user('anyone', UserRole.carer)), isTrue);
    });

    test('a bird whose only case is closed is still at large', () {
      expect(
        admissible(
          atLarge,
          user('anyone', UserRole.carer),
          cases: const [
            CaseSummary(
              id: 'c1',
              animal: 'a1',
              activeCarer: 'carer1',
              status: CaseStatus.disposed,
            ),
          ],
        ),
        isTrue,
      );
    });

    test("a bird in another carer's care is not a stranger's to admit", () {
      expect(
        admissible(
          atLarge,
          user('other', UserRole.carer),
          cases: const [
            CaseSummary(id: 'c1', animal: 'a1', activeCarer: 'carer1'),
          ],
        ),
        isFalse,
      );
    });

    test('its own holder may re-admit it', () {
      expect(
        admissible(
          atLarge,
          user('me', UserRole.carer),
          cases: const [CaseSummary(id: 'c1', animal: 'a1', activeCarer: 'me')],
        ),
        isTrue,
      );
    });

    test("a resident is the keeper's to admit and nobody else's", () {
      expect(
        admissible(resident, user('keeper', UserRole.carer), aviary: aviary),
        isTrue,
      );
      expect(
        admissible(resident, user('other', UserRole.carer), aviary: aviary),
        isFalse,
      );
    });

    // An unreadable enclosure must not make a resident look at large: housed is
    // read off the animal, not off a resolved Aviary.
    test('a housed bird whose enclosure did not resolve is not at large', () {
      expect(admissible(resident, user('other', UserRole.carer)), isFalse);
    });

    test('a deceased bird needs a coordinator to correct the record', () {
      expect(admissible(dead, user('anyone', UserRole.carer)), isFalse);
      expect(admissible(dead, user('coord', UserRole.coordinator)), isTrue);
      expect(admissible(dead, user('sup', UserRole.supervisor)), isTrue);
    });

    test('a signed-out user may admit nothing', () {
      expect(admissible(atLarge, null), isFalse);
    });
  });

  group('aviaryStockableBy', () {
    const aviary = Aviary(id: 'av1', name: 'Voliere 1', keeper: 'keeper');

    test('the keeper may place a bird into their own enclosure', () {
      expect(aviaryStockableBy(aviary, user('keeper', UserRole.carer)), isTrue);
    });

    test('another carer may not', () {
      expect(aviaryStockableBy(aviary, user('other', UserRole.carer)), isFalse);
    });

    test('a coordinator and a supervisor may', () {
      expect(
        aviaryStockableBy(aviary, user('coord', UserRole.coordinator)),
        isTrue,
      );
      expect(
        aviaryStockableBy(aviary, user('sup', UserRole.supervisor)),
        isTrue,
      );
    });

    test('a signed-out user may not', () {
      expect(aviaryStockableBy(aviary, null), isFalse);
    });
  });
}

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
}

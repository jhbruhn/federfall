import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockMedDueRepo extends Mock implements PbMedicationDueRepository {}

class MockActivityRepo extends Mock implements PbCaseLastActivityRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockFollowUpsRepo extends Mock implements PbFollowUpsRepository {}

class MockQuarantineRepo extends Mock implements PbCaseQuarantineRepository {}

class MockAppointmentsRepo extends Mock
    implements PbVetAppointmentsRepository {}

void main() {
  late MockCasesRepo cases;
  late MockMedDueRepo medDue;
  late MockActivityRepo activity;
  late MockAnimalsRepo animals;
  late MockFollowUpsRepo followUps;
  late MockQuarantineRepo quarantine;
  late MockAppointmentsRepo appointments;

  setUpAll(() => registerFallbackValue(DateTime(0)));

  setUp(() {
    cases = MockCasesRepo();
    medDue = MockMedDueRepo();
    activity = MockActivityRepo();
    animals = MockAnimalsRepo();
    followUps = MockFollowUpsRepo();
    quarantine = MockQuarantineRepo();
    appointments = MockAppointmentsRepo();

    when(() => medDue.mine(any())).thenAnswer((_) async => const []);
    when(() => followUps.openForCarer(any())).thenAnswer((_) async => const []);
    when(activity.all).thenAnswer((_) async => const []);
    when(quarantine.all).thenAnswer((_) async => const []);
    when(
      () => animals.byIds(any(), fields: any(named: 'fields')),
    ).thenAnswer((_) async => const []);
    when(
      () => appointments.openForCarer(any(), since: any(named: 'since')),
    ).thenAnswer((_) async => const []);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async => const AppUser(
            id: 'me',
            email: 'me@example.org',
            role: UserRole.carer,
          ),
        ),
        casesRepositoryProvider.overrideWith((ref) async => cases),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        medicationDueRepositoryProvider.overrideWith((ref) async => medDue),
        caseActivityRepositoryProvider.overrideWith((ref) async => activity),
        followUpsRepositoryProvider.overrideWith((ref) async => followUps),
        caseQuarantineRepositoryProvider.overrideWith(
          (ref) async => quarantine,
        ),
        vetAppointmentsRepositoryProvider.overrideWith(
          (ref) async => appointments,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('asks the server for this carer, not for every case', () async {
    // federfall-trep: the worklist used to read EVERY case the caller may see
    // — org-wide for a coordinator — and keep the handful they carry. Only the
    // carer's own cases come over the wire now.
    //
    // One disposed case, so the provider returns early and this test needs no
    // stubs for the six other repositories: what is under test is which query
    // the case list came from.
    when(() => cases.forCarer('me')).thenAnswer(
      (_) async => [
        const Case(id: 'c1', animal: 'a1', status: CaseStatus.disposed),
      ],
    );

    final source = await makeContainer().read(worklistSourceProvider.future);

    expect(source.cases, isEmpty, reason: 'a disposed case is not open work');
    verify(() => cases.forCarer('me')).called(1);
    verifyNever(
      () => cases.list(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    );
  });

  test('the disposed filter still runs on the device', () async {
    // Deliberately NOT pushed into the server query: it needs a `!=`, and
    // federfall-jt5u records one of those disagreeing with the arithmetic on
    // three runs out of four. Over one carer's cases it costs a few rows.
    when(() => cases.forCarer('me')).thenAnswer(
      (_) async => [
        const Case(id: 'open', animal: 'a1', status: CaseStatus.inCare),
        const Case(id: 'gone', animal: 'a2', status: CaseStatus.disposed),
      ],
    );

    final source = await makeContainer().read(worklistSourceProvider.future);

    expect(source.cases.map((c) => c.id), ['open']);
    verify(() => cases.forCarer('me')).called(1);
  });
}

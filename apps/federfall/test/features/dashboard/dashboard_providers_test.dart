import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall_data/federfall_data.dart';
// `Finder` here is flutter_test's, so hide the models' unrelated PII record of
// the same name (see CLAUDE.md).
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockCarerLoadRepo extends Mock implements PbCarerLoadRepository {}

AppUser _user(
  String id, {
  String? name,
  UserRole role = UserRole.carer,
  bool active = true,
}) => AppUser(
  id: id,
  email: '$id@example.org',
  name: name,
  role: role,
  isActive: active,
);

CarerCaseLoad _load(String carer, int open) =>
    CarerCaseLoad(id: 'org1:$carer', carer: carer, openCases: open);

void main() {
  // `countAdmittedBetween` takes non-nullable DateTimes, so `any()` needs a
  // dummy to build its matcher from.
  setUpAll(() => registerFallbackValue(DateTime(0)));

  group('buildDashboardSummary', () {
    test('derives active cases by subtracting disposed from the total', () {
      // NOT a `status != "disposed"` count — not because that filter is
      // suspect (federfall-jt5u probed it and cleared it), but because
      // subtraction keeps a case with no status at all counted as active,
      // which is what "has not yet been disposed" means.
      final s = buildDashboardSummary(
        totalCases: 10,
        disposedCases: 4,
        activeByStatus: const {},
        intakesThisYear: 0,
      );

      expect(s.activeCount, 6);
    });

    test('never reports a negative active count', () {
      // The total and the disposed count are separate requests; a case
      // disposed between them can invert them. A KPI tile reading "-1" looks
      // broken, a momentary 0 just resolves on the next refresh.
      final s = buildDashboardSummary(
        totalCases: 3,
        disposedCases: 4,
        activeByStatus: const {},
        intakesThisYear: 0,
      );

      expect(s.activeCount, 0);
    });

    test('breaks active cases down by status in enum order', () {
      final s = buildDashboardSummary(
        totalCases: 4,
        disposedCases: 1,
        activeByStatus: const {
          CaseStatus.readyForRelease: 1,
          CaseStatus.inCare: 2,
        },
        intakesThisYear: 0,
      );

      expect(s.byStatus[CaseStatus.inCare], 2);
      expect(s.byStatus[CaseStatus.readyForRelease], 1);
      // Disposed is not an active status and must not appear as a tile.
      expect(s.byStatus.containsKey(CaseStatus.disposed), isFalse);
      expect(s.byStatus.keys.toList(), const [
        CaseStatus.inCare,
        CaseStatus.readyForRelease,
      ]);
    });

    test('fills a status the server reported nothing for with 0', () {
      final s = buildDashboardSummary(
        totalCases: 0,
        disposedCases: 0,
        activeByStatus: const {},
        intakesThisYear: 0,
      );

      expect(s.byStatus, const {
        CaseStatus.inCare: 0,
        CaseStatus.readyForRelease: 0,
      });
    });

    test('keys the workload by carer, straight off the view rows', () {
      final s = buildDashboardSummary(
        totalCases: 5,
        disposedCases: 0,
        activeByStatus: const {},
        intakesThisYear: 0,
        carerLoad: [_load('anna', 2), _load('bert', 1)],
      );

      expect(s.openByCarer, {'anna': 2, 'bert': 1});
    });

    test('a row with no carer belongs to nobody', () {
      // The view only emits rows for cases that have an active carer, but an
      // empty id must never render as a nameless workload row.
      final s = buildDashboardSummary(
        totalCases: 1,
        disposedCases: 0,
        activeByStatus: const {},
        intakesThisYear: 0,
        carerLoad: [_load('', 3), _load('anna', 1)],
      );

      expect(s.openByCarer, {'anna': 1});
    });

    test('an unreadable workload view is an empty map, not an error', () {
      // A carer cannot read `case_carer_load`; a list request applies the rule
      // as a filter, so they get no rows. The card is canViewReports-gated, so
      // nothing is lost.
      final s = buildDashboardSummary(
        totalCases: 2,
        disposedCases: 0,
        activeByStatus: const {},
        intakesThisYear: 0,
      );

      expect(s.openByCarer, isEmpty);
    });
  });

  group('dashboardSummaryProvider', () {
    late MockCasesRepo cases;
    late MockAnimalsRepo animals;
    late MockCarerLoadRepo carerLoad;

    setUp(() {
      cases = MockCasesRepo();
      animals = MockAnimalsRepo();
      carerLoad = MockCarerLoadRepo();

      when(
        () => cases.count(filter: any(named: 'filter')),
      ).thenAnswer((_) async => 10);
      when(
        () => cases.countWithStatus(CaseStatus.disposed),
      ).thenAnswer((_) async => 4);
      when(
        () => cases.countWithStatus(CaseStatus.inCare),
      ).thenAnswer((_) async => 5);
      when(
        () => cases.countWithStatus(CaseStatus.readyForRelease),
      ).thenAnswer((_) async => 1);
      when(
        () => cases.countAdmittedBetween(any(), any()),
      ).thenAnswer((_) async => 7);
      when(animals.countHoused).thenAnswer((_) async => 3);
      when(carerLoad.all).thenAnswer((_) async => [_load('anna', 2)]);
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        // Riverpod 3 retries a failed provider on its own, with backoff. Good
        // in the app — the dashboard recovers from a blip without the user
        // pulling to refresh — but it means a provider that keeps throwing
        // stays in the LOADING state forever, so `.future` never settles and
        // an error assertion just times out. Off for these tests: what is
        // under test is the first failure, not the recovery policy.
        retry: (_, _) => null,
        overrides: [
          casesRepositoryProvider.overrideWith((ref) async => cases),
          animalsRepositoryProvider.overrideWith((ref) async => animals),
          carerLoadRepositoryProvider.overrideWith((ref) async => carerLoad),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('assembles every figure from server-side counts', () async {
      final s = await makeContainer().read(dashboardSummaryProvider.future);

      expect(s.activeCount, 6);
      expect(s.byStatus[CaseStatus.inCare], 5);
      expect(s.byStatus[CaseStatus.readyForRelease], 1);
      expect(s.intakesThisYear, 7);
      expect(s.inAviaryCount, 3);
      expect(s.openByCarer, {'anna': 2});
    });

    test('pulls no collection to the device', () async {
      // federfall-s0wk: this used to fetch all of `cases` and all of `animals`
      // on every dashboard open, then tally them here. Each figure is now one
      // request that transfers a single row.
      await makeContainer().read(dashboardSummaryProvider.future);

      verifyNever(
        () => cases.list(
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      );
      verifyNever(
        () => animals.list(
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      );
    });

    test("the intake year boundary is the DEVICE's, not UTC's", () async {
      // The counterpart to the fix in this issue's first half. Building the
      // range server-side would resolve it in SQL, i.e. in UTC, and put a bird
      // admitted at 00:30 on New Year's Day in UTC+1 in last year here while
      // the statistics screen — which resolves it through the caller's own
      // offset — puts it in this one. Same case, same org, two answers.
      await makeContainer().read(dashboardSummaryProvider.future);

      final range = verify(
        () => cases.countAdmittedBetween(captureAny(), captureAny()),
      ).captured;
      final from = range[0] as DateTime;
      final to = range[1] as DateTime;
      final year = DateTime.now().year;

      expect(from, DateTime(year), reason: 'local New Year, not UTC midnight');
      // Half-open and a full year wide: the next New Year, so 31 Dec 23:59:59
      // is inside and nothing has to be rounded.
      expect(to, DateTime(year + 1));

      final offset = DateTime.now().timeZoneOffset;
      // East or west of Greenwich, that instant is NOT midnight UTC — which is
      // what fails if the boundary is ever rebuilt from UTC parts. A device on
      // UTC cannot express the difference; flagged so a green run there is not
      // mistaken for coverage.
      expect(
        offset == Duration.zero || from.toUtc() != DateTime.utc(year),
        isTrue,
        reason: offset == Duration.zero
            ? 'device is on UTC: this test cannot distinguish the two readings'
            : 'expected the local boundary to differ from midnight UTC',
      );
    });

    test('asks for a count per active status, by wire value', () async {
      await makeContainer().read(dashboardSummaryProvider.future);

      // Driven off the same list the KPI tiles read, so the two cannot drift.
      verify(() => cases.countWithStatus(CaseStatus.inCare)).called(1);
      verify(() => cases.countWithStatus(CaseStatus.readyForRelease)).called(1);
      // Disposed is counted only to subtract it from the total.
      verify(() => cases.countWithStatus(CaseStatus.disposed)).called(1);
    });

    test('a carer reading no workload rows still gets a summary', () async {
      when(carerLoad.all).thenAnswer((_) async => const []);

      final s = await makeContainer().read(dashboardSummaryProvider.future);

      expect(s.openByCarer, isEmpty);
      expect(s.activeCount, 6);
    });

    test('an unreadable workload view costs the card, not the dashboard', () {
      // An app talking to an OLDER server inside the same major — permitted,
      // only the major is the wire contract — finds no `case_carer_load`
      // collection and gets a 404. The card is supplementary and already
      // canViewReports-gated, so that must not blank out the KPI grid too.
      // `thenAnswer` with a failed future, not `thenThrow`: a real repository
      // raises from inside `guard()`, i.e. always asynchronously.
      when(carerLoad.all).thenAnswer(
        (_) => Future.error(
          const RepositoryException(
            'Missing collection',
            kind: RepositoryErrorKind.notFound,
          ),
        ),
      );

      return expectLater(
        makeContainer().read(dashboardSummaryProvider.future),
        completion(
          isA<DashboardSummary>()
              .having((s) => s.openByCarer, 'openByCarer', isEmpty)
              .having((s) => s.activeCount, 'activeCount', 6)
              .having((s) => s.intakesThisYear, 'intakesThisYear', 7),
        ),
      );
    });

    test('a failed count surfaces as itself, not wrapped', () {
      // `(a, b, …).wait` reports a failure as ParallelWaitError, and the app's
      // error mapping only understands RepositoryException: wrapped, a dropped
      // connection renders as a generic error AND loses the figures already on
      // screen, which AsyncValueView deliberately keeps through a network blip.
      when(() => cases.countWithStatus(CaseStatus.inCare)).thenAnswer(
        (_) => Future.error(
          const RepositoryException(
            'Could not reach the server',
            kind: RepositoryErrorKind.network,
          ),
        ),
      );

      return expectLater(
        makeContainer().read(dashboardSummaryProvider.future),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.kind,
            'kind',
            RepositoryErrorKind.network,
          ),
        ),
      );
    });
  });

  group('buildCarerWorkload', () {
    test('sorts by open caseload, then by name', () {
      final rows = buildCarerWorkload(
        [
          _user('u1', name: 'Zora'),
          _user('u2', name: 'Anna'),
          _user('u3', name: 'Bert'),
        ],
        const {'u1': 1, 'u2': 1, 'u3': 4},
      );

      expect(
        rows.map((r) => r.user.name).toList(),
        // Busiest first, so the card leads with who needs relieving; ties fall
        // back to the name so the order is stable.
        ['Bert', 'Anna', 'Zora'],
      );
      expect(rows.map((r) => r.openCases).toList(), [4, 1, 1]);
    });

    test('lists an idle member with a zero count', () {
      final rows = buildCarerWorkload([_user('u1', name: 'Anna')], const {});

      expect(rows.single.openCases, 0);
    });

    test('excludes guests and deactivated members with nothing open', () {
      final rows = buildCarerWorkload([
        _user('u1', name: 'Anna'),
        _user('guest', name: 'Gast', role: UserRole.guest),
        _user('gone', name: 'Gone', active: false),
      ], const {});

      expect(rows.map((r) => r.user.id).toList(), ['u1']);
    });

    test('keeps a deactivated member who still holds open cases', () {
      // Deactivating a member is NOT blocked on their caseload (only deleting
      // one is), so their cases can be stranded — that is exactly the row a
      // coordinator has to see, not one to filter away.
      final rows = buildCarerWorkload(
        [
          _user('u1', name: 'Anna'),
          _user('gone', name: 'Gone', active: false),
        ],
        const {'gone': 3},
      );

      expect(rows.map((r) => r.user.id).toList(), ['gone', 'u1']);
      expect(rows.first.openCases, 3);
    });

    test('names a member without a name by their email local part', () {
      final rows = buildCarerWorkload([_user('u1')], const {});

      // memberLabel's fallback — the sort and the card share it, so an
      // unnamed member still lands in a predictable place.
      expect(rows.single.user.name, isNull);
      expect(rows.single.user.email, 'u1@example.org');
    });
  });
}

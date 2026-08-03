import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

Case _case({
  required String id,
  CaseStatus? status,
  DateTime? admittedAt,
  String? carer,
}) => Case(
  id: id,
  animal: 'a-$id',
  status: status,
  admittedAt: admittedAt,
  activeCarer: carer,
);

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

void main() {
  final now = DateTime(2026, 6, 23);

  test('counts active cases and excludes disposed', () {
    final s = buildDashboardSummary([
      _case(id: '1', status: CaseStatus.inCare),
      _case(id: '2', status: CaseStatus.readyForRelease),
      _case(id: '3', status: CaseStatus.disposed),
    ], now);

    expect(s.activeCount, 2);
  });

  test('counts intakes in the current calendar year only', () {
    final s = buildDashboardSummary([
      _case(id: '1', admittedAt: DateTime(2026, 3, 15)),
      _case(id: '2', admittedAt: DateTime(2026, 12, 31)),
      _case(id: '3', admittedAt: DateTime(2025, 12, 31)),
      _case(id: '4'),
    ], now);

    expect(s.intakesThisYear, 2);
  });

  test('breaks active cases down by status in enum order', () {
    final s = buildDashboardSummary([
      _case(id: '1', status: CaseStatus.inCare),
      _case(id: '2', status: CaseStatus.inCare),
      _case(id: '3', status: CaseStatus.readyForRelease),
      _case(id: '4', status: CaseStatus.disposed),
    ], now);

    expect(s.byStatus[CaseStatus.inCare], 2);
    expect(s.byStatus[CaseStatus.readyForRelease], 1);
    expect(s.byStatus.containsKey(CaseStatus.disposed), isFalse);
    expect(s.byStatus.keys.toList(), const [
      CaseStatus.inCare,
      CaseStatus.readyForRelease,
    ]);
  });

  test('counts OPEN cases per active carer, ignoring disposed ones', () {
    // Matches the server's definition of an open caseload
    // (`active_carer = {:id} && status != 'disposed'`, main.pb.js), so the card
    // never disagrees with the delete guard that quotes the same figure.
    final s = buildDashboardSummary([
      _case(id: '1', status: CaseStatus.inCare, carer: 'anna'),
      _case(id: '2', status: CaseStatus.readyForRelease, carer: 'anna'),
      _case(id: '3', status: CaseStatus.disposed, carer: 'anna'),
      _case(id: '4', status: CaseStatus.inCare, carer: 'bert'),
    ], now);

    expect(s.openByCarer, {'anna': 2, 'bert': 1});
  });

  test('an open case with no active carer belongs to nobody', () {
    // `active_carer` is optional server-side; such a case must not be bucketed
    // under an empty-string carer, which would render as a nameless row.
    final s = buildDashboardSummary([
      _case(id: '1', status: CaseStatus.inCare),
      _case(id: '2', status: CaseStatus.inCare, carer: ''),
      _case(id: '3', status: CaseStatus.inCare, carer: 'anna'),
    ], now);

    expect(s.openByCarer, {'anna': 1});
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

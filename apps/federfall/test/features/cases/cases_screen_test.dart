import 'package:federfall/core/auth/current_user.dart';
// The FULL roster provider — the one the filter's carer picker reads (not
// `placements_providers`' active-only namesake).
import 'package:federfall/features/admin/admin_providers.dart';
import 'package:federfall/features/cases/animal_species_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/helpers.dart';

/// Seeds [pendingCaseQueryProvider] with a value, as if a dashboard KPI had
/// queued a filter before switching to the Cases tab.
class _SeededPending extends PendingCaseQuery {
  _SeededPending(this._initial);

  final CaseQuery? _initial;

  @override
  CaseQuery? build() => _initial;
}

/// Longer than the search field's debounce, so a typed term reaches the feed.
/// `pumpAndSettle` alone would not get there: a pending Timer schedules no
/// frame, so it stops before the debounce elapses.
const _pastDebounce = Duration(milliseconds: 400);

/// Every filter is resolved by the server now (federfall-trep), so these
/// pump the screen over a fake feed and assert on the QUERY it asks with —
/// what used to be checked by counting the rows that survived on the device.
Future<List<CaseQuery>> _pump(
  WidgetTester tester, {
  List<Case> cases = const [],
  List<Case> Function(CaseQuery query)? rowsFor,
  Map<String, Animal> animalsById = const {},
  AppUser? user,
  CaseQuery? initialQuery,
  CaseQuery? pending,
  List<ConditionLabel> recorded = const [],
  List<String> species = const [],
  List<AppUser> members = const [],
}) async {
  // Compact width so the account menu sits in the app bar (on wider widths it
  // moves to the navigation rail, which this standalone screen has no shell to
  // provide).
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final asked = <CaseQuery>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        caseBrowseFeedProvider.overrideWith2(
          (_) => FakeCaseBrowseFeed(
            cases: cases,
            animalsById: animalsById,
            rowsFor: rowsFor,
            onQuery: asked.add,
          ),
        ),
        currentUserProvider.overrideWith((ref) async => user),
        pendingCaseQueryProvider.overrideWith(() => _SeededPending(pending)),
        recordedConditionsProvider.overrideWith((ref) async => recorded),
        animalSpeciesProvider.overrideWith((ref) async => species),
        orgMembersProvider.overrideWith((ref) async => members),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CasesScreen(initialQuery: initialQuery),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return asked;
}

/// Pumps [CasesScreen] behind a [GoRouter] parked at `/cases/<selectedId>`,
/// mimicking the shell where the list pane stays mounted while a case detail
/// route is open (the two-pane web layout) — [CasesScreen] reads the open
/// case's id via [GoRouterState], as it does in production.
Future<void> _pumpWithSelection(
  WidgetTester tester, {
  required String selectedId,
  required List<Case> Function(CaseQuery query) rowsFor,
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/cases/$selectedId',
    routes: [
      GoRoute(path: '/cases/:id', builder: (_, _) => const CasesScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        caseBrowseFeedProvider.overrideWith2(
          (_) => FakeCaseBrowseFeed(rowsFor: rowsFor),
        ),
        currentUserProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _mine = Case(
  id: 'c1',
  animal: 'a1',
  caseNumber: '2026-001',
  activeCarer: 'me',
  status: CaseStatus.inCare,
);
const _theirs = Case(
  id: 'c2',
  animal: 'a2',
  caseNumber: '2026-099',
  activeCarer: 'other',
  status: CaseStatus.inCare,
);

void main() {
  testWidgets('shows the empty state when there are no cases', (tester) async {
    await _pump(tester);
    expect(find.text('No cases yet'), findsOneWidget);
  });

  testWidgets('an empty NARROWED list says no matches, not no cases', (
    tester,
  ) async {
    // The loaded rows can no longer tell the two apart — the server sent only
    // what matched — so the query is what the empty state reads.
    await _pump(tester, initialQuery: const CaseQuery(species: 'Hohltaube'));

    expect(find.text('No matching cases'), findsOneWidget);
    expect(find.text('No cases yet'), findsNothing);
  });

  testWidgets("defaults to asking for the user's own active cases", (
    tester,
  ) async {
    final asked = await _pump(tester, cases: const [_mine]);

    expect(asked.last.allScope, isFalse);
    expect(asked.last.activity, CaseActivity.active);
    final browse = asked.last.toBrowseQuery('me');
    expect(browse.activeCarer, 'me');
    expect(browse.statuses, [CaseStatus.inCare, CaseStatus.readyForRelease]);
    expect(find.text('2026-001'), findsOneWidget);
  });

  testWidgets('a deep-linked initialQuery widens to all cases', (tester) async {
    final asked = await _pump(
      tester,
      cases: const [_theirs],
      initialQuery: const CaseQuery(allScope: true),
    );

    expect(asked.last.allScope, isTrue);
    // No carer clause, so the access rules alone decide what comes back.
    expect(asked.last.toBrowseQuery('me').activeCarer, isNull);
    expect(find.text('2026-099'), findsOneWidget);
  });

  testWidgets(
    'opening a case excluded by "mine" scope widens to all cases',
    (tester) async {
      await _pumpWithSelection(
        tester,
        selectedId: 'c2',
        // What the server would answer for each scope.
        rowsFor: (q) => q.allScope ? const [_mine, _theirs] : const [_mine],
      );

      // c2 belongs to another carer, so the default "mine" scope would
      // otherwise hide it from the list while its detail is open.
      expect(find.text('2026-001'), findsOneWidget);
      expect(find.text('2026-099'), findsOneWidget);
    },
  );

  testWidgets(
    "doesn't re-widen after the user manually narrows back to mine",
    (tester) async {
      await _pumpWithSelection(
        tester,
        selectedId: 'c2',
        rowsFor: (q) => q.allScope ? const [_theirs] : const [],
      );
      expect(find.text('2026-099'), findsOneWidget);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All cases').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('My cases').last);
      await tester.pumpAndSettle();

      // Narrowed back to "mine" on purpose — the auto-widen must not
      // immediately re-trigger for the same still-open case.
      expect(find.text('2026-099'), findsNothing);
    },
  );

  testWidgets('applies a pending KPI filter on mount', (tester) async {
    final asked = await _pump(
      tester,
      cases: const [_theirs],
      pending: const CaseQuery(allScope: true),
    );

    expect(asked.last.allScope, isTrue);
    expect(find.text('2026-099'), findsOneWidget);
  });

  testWidgets('the search term reaches the server, once the typing stops', (
    tester,
  ) async {
    final asked = await _pump(tester, cases: const [_mine]);
    final before = asked.length;

    await tester.enterText(find.byType(TextField), 'pip');
    await tester.pump();

    // Debounced: mid-keystroke nothing has been asked yet, so a three-letter
    // term is one request rather than three.
    expect(asked.length, before);

    await tester.pump(_pastDebounce);
    await tester.pumpAndSettle();

    expect(asked.last.text, 'pip');
  });

  testWidgets('account menu offers profile but hides admin for a carer', (
    tester,
  ) async {
    await _pump(
      tester,
      user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Administration'), findsNothing);
    expect(find.text('Statistics'), findsNothing);
  });

  testWidgets('account menu shows admin and reports for a supervisor', (
    tester,
  ) async {
    await _pump(
      tester,
      user: const AppUser(
        id: 'u1',
        email: 's@x.org',
        role: UserRole.supervisor,
      ),
    );

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Administration'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
  });

  testWidgets('an outcome handed over from statistics is asked for', (
    tester,
  ) async {
    final asked = await _pump(
      tester,
      cases: const [_mine],
      pending: const CaseQuery(
        allScope: true,
        activity: CaseActivity.all,
        outcome: DispositionType.released,
      ),
    );

    expect(asked.last.outcome, DispositionType.released);
    expect(asked.last.toBrowseQuery('me').outcome, DispositionType.released);
  });

  testWidgets('the filter sheet shows and clears a handed-over facet', (
    tester,
  ) async {
    final asked = await _pump(
      tester,
      cases: const [_mine],
      pending: const CaseQuery(
        allScope: true,
        activity: CaseActivity.all,
        condition: 'Katzenbiss',
      ),
    );

    expect(asked.last.condition, 'Katzenbiss');

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    // Recorded as free text, so it is deliberately absent from the code list
    // this dropdown is built from — the handed-over value still has to show,
    // or the list would be short of cases with nothing on screen saying why.
    expect(find.text('Katzenbiss'), findsOneWidget);

    // Clearing it re-asks without the facet, and the list behind the sheet
    // updates live.
    await tester.tap(find.text('Katzenbiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any diagnosis').last);
    await tester.pumpAndSettle();

    expect(asked.last.condition, isNull);
  });

  testWidgets('the filter sheet can pick an outcome and a diagnosis', (
    tester,
  ) async {
    final asked = await _pump(
      tester,
      cases: const [_mine],
      pending: const CaseQuery(allScope: true, activity: CaseActivity.all),
      recorded: const [
        ConditionLabel(id: 'k1', label: 'Katzenbiss', caseCount: 1),
      ],
    );

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();

    // The outcome options need no data at all and the diagnoses come from the
    // small `condition_labels` view, so opening the filters costs no per-case
    // read — there is none left to cost.
    expect(find.text('Any outcome'), findsOneWidget);
    expect(find.text('Any diagnosis'), findsOneWidget);

    await tester.tap(find.text('Any diagnosis'));
    await tester.pumpAndSettle();
    // Offered because a case actually records it, not because the code list
    // happens to contain it.
    expect(find.text('Katzenbiss'), findsWidgets);
    await tester.tap(find.text('Katzenbiss').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Any outcome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Released').last);
    await tester.pumpAndSettle();

    expect(asked.last.condition, 'Katzenbiss');
    expect(asked.last.outcome, DispositionType.released);
  });

  testWidgets('the species picker offers the org vocabulary, not the page', (
    tester,
  ) async {
    // It used to be the distinct species among the loaded cases, which only
    // worked while the whole collection was on the device — and could not
    // offer a species held only by cases outside the current scope.
    final asked = await _pump(
      tester,
      cases: const [_mine],
      species: const ['Columba livia', 'Hohltaube'],
    );

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any species'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hohltaube').last);
    await tester.pumpAndSettle();

    expect(asked.last.species, 'Hohltaube');
  });

  group('carer filter (federfall-9mit)', () {
    const anna = AppUser(
      id: 'anna',
      email: 'anna@example.org',
      name: 'Anna',
      role: UserRole.carer,
      isActive: true,
    );
    const annas = Case(
      id: 'c1',
      animal: 'a1',
      caseNumber: '2026-001',
      activeCarer: 'anna',
    );

    testWidgets('a handed-over carer filter names them and asks for theirs', (
      tester,
    ) async {
      final asked = await _pump(
        tester,
        cases: const [annas],
        pending: const CaseQuery(carer: 'anna'),
        members: const [anna],
      );

      // The dashboard's workload card queues the filter without widening the
      // scope, so this also proves the carer supersedes the "mine" default.
      expect(asked.last.toBrowseQuery('me').activeCarer, 'anna');
      expect(find.text('2026-001'), findsOneWidget);
      // Titled by whose caseload it is — "All cases" would read as though the
      // tap had not taken.
      expect(find.text('Cases of Anna'), findsOneWidget);
    });

    testWidgets('falls back to the widened title until the roster lands', (
      tester,
    ) async {
      await _pump(
        tester,
        cases: const [annas],
        pending: const CaseQuery(carer: 'anna'),
      );

      // No roster to name the id with — the honest fallback is the scope the
      // filter implies, not a name we do not have.
      expect(find.text('All cases'), findsOneWidget);
      expect(find.text('2026-001'), findsOneWidget);
    });

    testWidgets('one picker covers mine, all, and a colleague', (
      tester,
    ) async {
      // Mine / all / a named carer were never independent — a carer
      // supersedes the scope — so they are one control. Two of them made the
      // default self-contradictory: a "Mine" toggle beside an "Any carer"
      // picker, describing the same list.
      final asked = await _pump(
        tester,
        cases: const [annas],
        members: const [anna],
      );

      // It opens on what the list is actually showing, not on "any".
      expect(find.text('My cases'), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsNothing);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My cases').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anna').last);
      await tester.pumpAndSettle();

      expect(asked.last.toBrowseQuery('me').activeCarer, 'anna');

      // Leaving the colleague again lands on a scope, not on a half-cleared
      // state that still carries them.
      await tester.tap(find.text('Anna').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All cases').last);
      await tester.pumpAndSettle();

      expect(asked.last.carer, isNull);
      expect(asked.last.allScope, isTrue);
      expect(asked.last.toBrowseQuery('me').activeCarer, isNull);
    });

    testWidgets('the filter pickers take no free text', (tester) async {
      await _pump(
        tester,
        cases: const [annas],
        // A species so that picker is offered too — all four have to hold.
        species: const ['Columba livia'],
        members: const [anna],
        recorded: const [
          ConditionLabel(id: 'k1', label: 'Katzenbiss', caseCount: 1),
        ],
      );

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();

      // Closed sets, so a typed value could not mean anything — and left at
      // the platform default these fields are editable on desktop/web while
      // filtering nothing, silently overwriting a selection still in force.
      final menus = tester.widgetList<DropdownMenu<Object?>>(
        find.byWidgetPredicate((w) => w is DropdownMenu),
      );
      expect(menus, hasLength(4));
      for (final menu in menus) {
        expect(menu.requestFocusOnTap, isFalse);
      }
    });
  });
}

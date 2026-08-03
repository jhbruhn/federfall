import 'package:federfall/core/auth/current_user.dart';
// The FULL roster provider — the one the filter's carer picker reads (not
// `placements_providers`' active-only namesake).
import 'package:federfall/features/admin/admin_providers.dart';
import 'package:federfall/features/cases/case_facets.dart';
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

/// Seeds [pendingCaseQueryProvider] with a value, as if a dashboard KPI had
/// queued a filter before switching to the Cases tab.
class _SeededPending extends PendingCaseQuery {
  _SeededPending(this._initial);

  final CaseQuery? _initial;

  @override
  CaseQuery? build() => _initial;
}

Future<void> _pump(
  WidgetTester tester, {
  List<Case> cases = const [],
  Map<String, Animal> animalsById = const {},
  String myUserId = 'me',
  AppUser? user,
  CaseQuery? initialQuery,
  CaseQuery? pending,
  CaseFacets facets = CaseFacets.empty,
  List<ConditionLabel> recorded = const [],
  List<AppUser> members = const [],
}) async {
  // Compact width so the account menu sits in the app bar (on wider widths it
  // moves to the navigation rail, which this standalone screen has no shell to
  // provide).
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        casesBrowserDataProvider.overrideWith(
          (ref) async => CasesBrowserData(
            cases: cases,
            animalsById: animalsById,
            myUserId: myUserId,
          ),
        ),
        currentUserProvider.overrideWith((ref) async => user),
        pendingCaseQueryProvider.overrideWith(() => _SeededPending(pending)),
        caseFacetsProvider.overrideWith((ref) async => facets),
        recordedConditionsProvider.overrideWith((ref) async => recorded),
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
}

/// Pumps [CasesScreen] behind a [GoRouter] parked at `/cases/<selectedId>`,
/// mimicking the shell where the list pane stays mounted while a case detail
/// route is open (the two-pane web layout) — [CasesScreen] reads the open
/// case's id via [GoRouterState], as it does in production.
Future<void> _pumpWithSelection(
  WidgetTester tester, {
  required String selectedId,
  required List<Case> cases,
  Map<String, Animal> animalsById = const {},
  String myUserId = 'me',
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
        casesBrowserDataProvider.overrideWith(
          (ref) async => CasesBrowserData(
            cases: cases,
            animalsById: animalsById,
            myUserId: myUserId,
          ),
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

void main() {
  testWidgets('shows the empty state when there are no cases', (tester) async {
    await _pump(tester);
    expect(find.text('No cases yet'), findsOneWidget);
  });

  testWidgets('a deep-linked initialQuery widens to all cases', (tester) async {
    await _pump(
      tester,
      // A case owned by someone else: hidden under the default "mine" scope,
      // shown when the dashboard deep-links scope=all.
      cases: const [
        Case(
          id: 'c1',
          animal: 'a1',
          caseNumber: '2026-099',
          activeCarer: 'other',
          status: CaseStatus.inCare,
        ),
      ],
      initialQuery: const CaseQuery(allScope: true),
    );

    expect(find.text('2026-099'), findsOneWidget);
  });

  testWidgets(
    'opening a case excluded by "mine" scope widens to all cases',
    (tester) async {
      await _pumpWithSelection(
        tester,
        selectedId: 'c2',
        cases: const [
          Case(
            id: 'c1',
            animal: 'a1',
            caseNumber: '2026-001',
            activeCarer: 'me',
            status: CaseStatus.inCare,
          ),
          Case(
            id: 'c2',
            animal: 'a2',
            caseNumber: '2026-099',
            activeCarer: 'other',
            status: CaseStatus.inCare,
          ),
        ],
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
        cases: const [
          Case(
            id: 'c2',
            animal: 'a2',
            caseNumber: '2026-099',
            activeCarer: 'other',
            status: CaseStatus.inCare,
          ),
        ],
      );
      expect(find.text('2026-099'), findsOneWidget);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mine'));
      await tester.pumpAndSettle();

      // Narrowed back to "mine" on purpose — the auto-widen must not
      // immediately re-trigger for the same still-open case.
      expect(find.text('2026-099'), findsNothing);
    },
  );

  testWidgets('applies a pending KPI filter on mount', (tester) async {
    await _pump(
      tester,
      // Another carer's case: hidden under the default "mine" scope, revealed
      // by the pending scope=all filter a dashboard KPI queued.
      cases: const [
        Case(
          id: 'c1',
          animal: 'a1',
          caseNumber: '2026-099',
          activeCarer: 'other',
          status: CaseStatus.inCare,
        ),
      ],
      pending: const CaseQuery(allScope: true),
    );

    expect(find.text('2026-099'), findsOneWidget);
  });

  testWidgets("defaults to the user's own active cases", (tester) async {
    await _pump(
      tester,
      cases: const [
        Case(
          id: 'c1',
          animal: 'a1',
          caseNumber: '2026-001',
          activeCarer: 'me',
          status: CaseStatus.inCare,
        ),
        Case(
          id: 'c2',
          animal: 'a2',
          caseNumber: '2026-002',
          activeCarer: 'someone-else',
          status: CaseStatus.inCare,
        ),
        Case(
          id: 'c3',
          animal: 'a3',
          caseNumber: '2026-003',
          activeCarer: 'me',
          status: CaseStatus.disposed,
        ),
      ],
    );

    // Mine + active only: c1 shows; the other carer's (c2) and the closed
    // (c3) ones are filtered out by default.
    expect(find.text('2026-001'), findsOneWidget);
    expect(find.text('2026-002'), findsNothing);
    expect(find.text('2026-003'), findsNothing);
  });

  testWidgets('search matches case number and animal name', (tester) async {
    await _pump(
      tester,
      cases: const [
        Case(
          id: 'c1',
          animal: 'a1',
          caseNumber: '2026-001',
          activeCarer: 'me',
          status: CaseStatus.inCare,
        ),
        Case(
          id: 'c2',
          animal: 'a2',
          caseNumber: '2026-002',
          activeCarer: 'me',
          status: CaseStatus.inCare,
        ),
      ],
      animalsById: const {
        'a1': Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        'a2': Animal(id: 'a2', species: 'Columba livia', name: 'Fritz'),
      },
    );

    await tester.enterText(find.byType(TextField), 'pip');
    await tester.pumpAndSettle();

    expect(find.text('2026-001'), findsOneWidget);
    expect(find.text('2026-002'), findsNothing);
  });

  testWidgets('shows the no-matches state when filters exclude all', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: const [
        Case(
          id: 'c1',
          animal: 'a1',
          caseNumber: '2026-001',
          activeCarer: 'me',
          status: CaseStatus.inCare,
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pumpAndSettle();

    expect(find.text('No matching cases'), findsOneWidget);
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

  testWidgets('an outcome handed over from statistics filters the list', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: const [
        Case(id: 'c1', animal: 'a1', caseNumber: '2026-001'),
        Case(id: 'c2', animal: 'a1', caseNumber: '2026-002'),
      ],
      pending: const CaseQuery(
        allScope: true,
        activity: CaseActivity.all,
        outcome: DispositionType.released,
      ),
      facets: const CaseFacets(
        outcomeByCase: {
          'c1': DispositionType.released,
          'c2': DispositionType.died,
        },
      ),
    );

    expect(find.text('2026-001'), findsOneWidget);
    expect(find.text('2026-002'), findsNothing);
  });

  testWidgets('the filter sheet shows and clears a handed-over facet', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: const [
        Case(id: 'c1', animal: 'a1', caseNumber: '2026-001'),
        Case(id: 'c2', animal: 'a1', caseNumber: '2026-002'),
      ],
      pending: const CaseQuery(
        allScope: true,
        activity: CaseActivity.all,
        condition: 'Katzenbiss',
      ),
      facets: const CaseFacets(
        conditionsByCase: {
          'c1': {'Katzenbiss'},
        },
      ),
    );

    expect(find.text('2026-002'), findsNothing);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    // Recorded as free text, so it is deliberately absent from the code list
    // this dropdown is built from — the handed-over value still has to show,
    // or the list would be short of cases with nothing on screen saying why.
    expect(find.text('Katzenbiss'), findsOneWidget);

    // Clearing it releases the list behind the sheet, which updates live.
    await tester.tap(find.text('Katzenbiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any diagnosis').last);
    await tester.pumpAndSettle();

    expect(find.text('2026-002'), findsOneWidget);
  });

  testWidgets('the filter sheet can pick an outcome and a diagnosis', (
    tester,
  ) async {
    await _pump(
      tester,
      cases: const [
        Case(id: 'c1', animal: 'a1', caseNumber: '2026-001'),
        Case(id: 'c2', animal: 'a1', caseNumber: '2026-002'),
      ],
      pending: const CaseQuery(allScope: true, activity: CaseActivity.all),
      facets: const CaseFacets(
        outcomeByCase: {
          'c1': DispositionType.released,
          'c2': DispositionType.died,
        },
      ),
      recorded: const [
        ConditionLabel(id: 'k1', label: 'Katzenbiss', caseCount: 1),
      ],
    );

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();

    // The outcome options need no data at all and the diagnoses come from the
    // org's code list, so neither picker waits on the per-case facet load.
    expect(find.text('Any outcome'), findsOneWidget);
    expect(find.text('Any diagnosis'), findsOneWidget);

    await tester.tap(find.text('Any diagnosis'));
    await tester.pumpAndSettle();
    // Offered because a case actually records it, not because the code list
    // happens to contain it.
    expect(find.text('Katzenbiss'), findsWidgets);
    await tester.tap(find.text('Any diagnosis').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Any outcome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Released').last);
    await tester.pumpAndSettle();

    expect(find.text('2026-001'), findsOneWidget);
    expect(find.text('2026-002'), findsNothing);
  });

  group('carer filter (federfall-9mit)', () {
    const anna = AppUser(
      id: 'anna',
      email: 'anna@example.org',
      name: 'Anna',
      role: UserRole.carer,
      isActive: true,
    );
    const cases = [
      Case(
        id: 'c1',
        animal: 'a1',
        caseNumber: '2026-001',
        activeCarer: 'anna',
      ),
      Case(id: 'c2', animal: 'a1', caseNumber: '2026-002', activeCarer: 'me'),
    ];

    testWidgets('a handed-over carer filter names them and lists their cases', (
      tester,
    ) async {
      await _pump(
        tester,
        cases: cases,
        pending: const CaseQuery(carer: 'anna'),
        members: const [anna],
      );

      // The dashboard's workload card queues the filter without widening the
      // scope, so this also proves the carer supersedes the "mine" default.
      expect(find.text('2026-001'), findsOneWidget);
      expect(find.text('2026-002'), findsNothing);
      // Titled by whose caseload it is — "All cases" would read as though the
      // tap had not taken.
      expect(find.text('Cases of Anna'), findsOneWidget);
    });

    testWidgets('falls back to the widened title until the roster lands', (
      tester,
    ) async {
      await _pump(
        tester,
        cases: cases,
        pending: const CaseQuery(carer: 'anna'),
      );

      // No roster to name the id with — the honest fallback is the scope the
      // filter implies, not a name we do not have.
      expect(find.text('All cases'), findsOneWidget);
      expect(find.text('2026-001'), findsOneWidget);
    });

    testWidgets('the sheet picks a carer and parks the scope toggle', (
      tester,
    ) async {
      await _pump(tester, cases: cases, members: const [anna]);

      expect(find.text('2026-002'), findsOneWidget);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any carer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anna').last);
      await tester.pumpAndSettle();

      // The list behind the sheet swaps to Anna's caseload…
      expect(find.text('2026-001'), findsOneWidget);
      expect(find.text('2026-002'), findsNothing);
      // …and the mine/all toggle goes inert, because the carer stands in for
      // it rather than intersecting with it.
      final scope = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(scope.onSelectionChanged, isNull);
    });

    testWidgets('the filter pickers take no free text', (tester) async {
      await _pump(
        tester,
        cases: cases,
        // A species so that picker is offered too — all four have to hold.
        animalsById: const {'a1': Animal(id: 'a1', species: 'Columba livia')},
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

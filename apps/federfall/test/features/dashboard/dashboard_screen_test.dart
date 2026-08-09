import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/dashboard/dashboard_screen.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
// `Finder` here is flutter_test's, so hide the models' unrelated PII record of
// the same name (the mirror image of the usual clash — see CLAUDE.md).
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

AppUser _user(String id, {String? name, UserRole role = UserRole.carer}) =>
    AppUser(
      id: id,
      email: '$id@example.org',
      name: name,
      role: role,
      isActive: true,
    );

Future<void> _pump(
  WidgetTester tester,
  DashboardSummary summary, {
  AppUser? me,
  List<CarerWorkload>? workload,
  List<WorklistItem>? worklist,
  Size? window,
}) async {
  if (window != null) {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardSummaryProvider.overrideWith((ref) async => summary),
        currentUserProvider.overrideWith((ref) async => me),
        carerWorkloadProvider.overrideWith((ref) async => workload ?? const []),
        worklistProvider.overrideWith((ref) async => worklist ?? const []),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DashboardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Today preview's card. Its title sits inside a [ListTile], indented past
/// the leading icon, so the card is what tells you where the column is.
Rect _todayCard(WidgetTester tester) => tester.getRect(
  find.ancestor(of: find.text('Today'), matching: find.byType(Card)).first,
);

void main() {
  testWidgets('renders the caseload KPI grid', (tester) async {
    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {
          CaseStatus.inCare: 3,
          CaseStatus.readyForRelease: 1,
        },
        inAviaryCount: 5,
      ),
    );

    expect(find.text('Caseload'), findsOneWidget);
    expect(find.text('Active cases'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Intakes this year'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // The 'Ready for release' status is promoted to its own tile…
    expect(find.text('Ready for release'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // …and aviary residents get a tile too.
    expect(find.text('In aviary'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('every KPI tile is tappable (deep-link to a filtered view)', (
    tester,
  ) async {
    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {CaseStatus.inCare: 3, CaseStatus.readyForRelease: 1},
        inAviaryCount: 5,
      ),
    );

    // Each of the four tiles carries a chevron affordance.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
  });

  testWidgets('narrow screens lead with the all-caught-up Today card', (
    tester,
  ) async {
    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {},
      ),
    );

    // Today always leads (federfall-6ds): even with nothing due the phone
    // layout shows the compact "all caught up" card above the caseload.
    expect(find.text('Caseload'), findsOneWidget);
    expect(find.text("Nothing due — you're all caught up."), findsOneWidget);
  });

  group('Today preview through a reload (federfall-f8xe)', () {
    const summary = DashboardSummary(
      activeCount: 4,
      intakesThisYear: 7,
      byStatus: {},
    );

    WorklistItem item(String id) => WorklistItem(
      kind: WorklistKind.medicationDue,
      caseId: id,
      dueAt: DateTime(2026, 6, 23, 9),
      severity: WorklistSeverity.upcoming,
      caseNumber: id,
      animalName: 'Lotte',
      drug: 'Metacam',
    );

    /// Pumps the dashboard with a worklist the test controls: each build of
    /// `worklistProvider` takes the next completer, so a reload can be held
    /// open and inspected mid-flight.
    Future<(ProviderContainer, List<Completer<List<WorklistItem>>>)> pump(
      WidgetTester tester,
    ) async {
      final completers = <Completer<List<WorklistItem>>>[];
      final container = ProviderContainer(
        // Riverpod 3 retries a failed provider on a timer, which outlives the
        // widget tree and trips the pending-timer check. The error states here
        // are about the first failure, not the recovery policy.
        retry: (_, _) => null,
        overrides: [
          dashboardSummaryProvider.overrideWith((ref) async => summary),
          currentUserProvider.overrideWith((ref) async => null),
          carerWorkloadProvider.overrideWith((ref) async => const []),
          // The real one starts periodic timers; nothing here needs them.
          worklistTickerProvider.overrideWith((ref) {}),
          worklistProvider.overrideWith((ref) {
            final completer = Completer<List<WorklistItem>>();
            completers.add(completer);
            return completer.future;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DashboardScreen(),
          ),
        ),
      );
      // `pump`, never `pumpAndSettle`: the card's progress bar animates for as
      // long as the load runs, so settling would wait for a frame that never
      // comes. Two frames is enough for the immediate futures above.
      await tester.pump();
      await tester.pump();
      return (container, completers);
    }

    testWidgets('keeps the list on screen while it reloads', (tester) async {
      final (container, completers) = await pump(tester);
      completers.first.complete([item('c1'), item('c2')]);
      await tester.pump();
      expect(find.text('2 tasks due'), findsOneWidget);

      // The ticker's refetch, held open — this is the window the card used to
      // spend as a `SizedBox.shrink()`, blinking out of the layout.
      container.invalidate(worklistProvider);
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('2 tasks due'), findsOneWidget);
      // ...and it says so rather than pretending nothing is happening.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      completers.last.complete([item('c1')]);
      await tester.pump();
      expect(find.text('1 task due'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a failed reload keeps the list, not an error', (tester) async {
      final (container, completers) = await pump(tester);
      completers.first.complete([item('c1')]);
      await tester.pump();

      container.invalidate(worklistProvider);
      await tester.pump();
      completers.last.completeError(
        const RepositoryException(
          'Could not reach the server',
          kind: RepositoryErrorKind.network,
        ),
      );
      await tester.pump();

      // The app-wide offline strip states the cause; replacing a good list
      // with an error would only cost the user what they were reading.
      expect(find.text('1 task due'), findsOneWidget);
    });

    testWidgets('a first load that fails says so, with a retry', (
      tester,
    ) async {
      final (_, completers) = await pump(tester);

      completers.first.completeError(
        const RepositoryException('nope'),
      );
      await tester.pump();

      // Nothing to preserve here, so the card reports instead of vanishing —
      // which is what it used to do, until the next tick.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('the card holds its place during the first load', (
      tester,
    ) async {
      await pump(tester);

      // Never completed: the shell is up with its progress bar, so the
      // caseload below it does not jump when the list lands.
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('due'), findsNothing);
    });
  });

  group('Today headline counts obligations (federfall-9m9n)', () {
    const summary = DashboardSummary(
      activeCount: 4,
      intakesThisYear: 7,
      byStatus: {},
    );

    WorklistItem med(String id) => WorklistItem(
      kind: WorklistKind.medicationDue,
      caseId: id,
      // Later than the stale items below, so a plain date sort would bury it.
      dueAt: DateTime(2026, 6, 23, 9),
      severity: WorklistSeverity.overdue,
      caseNumber: id,
      animalName: 'Lotte',
      drug: 'Metacam',
    );

    WorklistItem stale(String id) => WorklistItem(
      kind: WorklistKind.staleCase,
      caseId: id,
      dueAt: DateTime(2026, 5, 15),
      severity: WorklistSeverity.overdue,
      caseNumber: id,
      animalName: 'Bruno',
    );

    // The reported shape: one overdue dose behind four staleness notices.
    List<WorklistItem> oneDoseFourQuiet() => [
      stale('c1'),
      stale('c2'),
      stale('c3'),
      stale('c4'),
      med('c5'),
    ];

    testWidgets('a quiet case is not a task due', (tester) async {
      await _pump(tester, summary, worklist: oneDoseFourQuiet());

      // One dose is owed; four cases have merely been quiet. Summing the
      // list said "5 tasks due" and a carer read five obligations.
      expect(find.text('1 task due · 4 cases quiet'), findsOneWidget);
      expect(find.text('5 tasks due'), findsNothing);
    });

    testWidgets('nothing owed reads as quiet, not as due', (tester) async {
      await _pump(tester, summary, worklist: [stale('c1'), stale('c2')]);

      expect(find.text('2 cases quiet'), findsOneWidget);
      expect(find.textContaining('due'), findsNothing);
    });

    testWidgets('the preview leads with what is owed', (tester) async {
      await _pump(tester, summary, worklist: oneDoseFourQuiet());

      // The worklist is sorted soonest-`dueAt` first and a long-quiet case
      // carries an old one, so the dose sorted behind all four — and the
      // preview shows only four rows, so the one real task fell off it
      // entirely. It leads now, and a quiet case is what gets cut.
      final dose = tester.getRect(find.textContaining('Metacam'));
      final firstQuiet = tester.getRect(find.textContaining('Bruno').first);
      expect(dose.top, lessThan(firstQuiet.top));
      expect(find.textContaining('Bruno'), findsNWidgets(3));
    });
  });

  group('layout (federfall-773v)', () {
    const summary = DashboardSummary(
      activeCount: 4,
      intakesThisYear: 7,
      byStatus: {CaseStatus.inCare: 3, CaseStatus.readyForRelease: 1},
      inAviaryCount: 5,
    );

    testWidgets('a desktop window puts Today beside the caseload', (
      tester,
    ) async {
      await _pump(tester, summary, window: const Size(1200, 900));

      // Two columns: the caseload and the Today preview (here its empty-state
      // card, shown so the column isn't blank) are visible at once.
      expect(find.text('Caseload'), findsOneWidget);
      expect(find.text("Nothing due — you're all caught up."), findsOneWidget);

      // Geometry, not just presence. Measured on the Today *card* rather than
      // its title, which a ListTile indents past the leading icon.
      final today = _todayCard(tester);
      final caseload = tester.getRect(find.text('Caseload'));
      // Side by side, with Today on the left — it leads in both layouts.
      expect(today.right, lessThanOrEqualTo(caseload.left));
      // ...and the two columns start on the same line.
      expect(today.top, caseload.top);
    });

    testWidgets('a window too narrow for two readable columns stacks', (
      tester,
    ) async {
      // 1000 is past the old `isExpanded` split at 840 and still stacks: two
      // columns here would each hold KPI tiles under their 240px minimum,
      // which is the state this issue found on every laptop.
      await _pump(tester, summary, window: const Size(1000, 900));

      final today = _todayCard(tester);
      final caseload = tester.getRect(find.text('Caseload'));
      expect(today.left, caseload.left);
      expect(today.bottom, lessThanOrEqualTo(caseload.top));
    });

    testWidgets('the split gives its tiles a readable width', (tester) async {
      // The threshold is derived from this: at 1040 each column must still fit
      // two tiles at KpiGrid's own 240px minimum.
      await _pump(tester, summary, window: const Size(1040, 900));

      final tiles = find.byType(KpiCard);
      expect(tiles, findsNWidgets(4));
      expect(tester.getSize(tiles.first).width, greaterThanOrEqualTo(240));
    });

    testWidgets('a 4K window does not stretch the cards across it', (
      tester,
    ) async {
      await _pump(tester, summary, window: const Size(2400, 1000));

      // ContentBounds caps and centres the page, as on every other flat
      // surface — without it a breakdown row spans half a metre.
      expect(
        tester.getSize(find.byType(ListView)).width,
        lessThanOrEqualTo(kWideContentMaxWidth),
      );
    });
  });

  group('carer workload card (federfall-9mit)', () {
    const summary = DashboardSummary(
      activeCount: 4,
      intakesThisYear: 7,
      byStatus: {},
    );

    testWidgets('is hidden from a carer', (tester) async {
      await _pump(
        tester,
        summary,
        me: _user('me'),
        workload: [
          CarerWorkload(user: _user('anna', name: 'Anna'), openCases: 3),
        ],
      );

      // A carer reads only their own cases plus what was shared with them, so
      // the same figures would be a misleading fragment.
      expect(find.text('Carer workload'), findsNothing);
      expect(find.text('Anna'), findsNothing);
    });

    testWidgets('lists each carer with their open caseload for a coordinator', (
      tester,
    ) async {
      await _pump(
        tester,
        summary,
        me: _user('me', role: UserRole.coordinator),
        workload: [
          CarerWorkload(user: _user('anna', name: 'Anna'), openCases: 3),
          CarerWorkload(user: _user('bert', name: 'Bert'), openCases: 0),
        ],
      );

      // Scoped to the card: the KPI grid above it shows counts of its own.
      Finder inCard(String text) => find.descendant(
        of: find.byType(BreakdownCard),
        matching: find.text(text),
      );

      expect(find.text('Carer workload'), findsOneWidget);
      expect(inCard('Anna'), findsOneWidget);
      expect(inCard('3'), findsOneWidget);
      // A member carrying nothing gets no row of its own — that is not
      // workload, and several of them made the card longer than the fact it
      // reports (federfall-06v1). They are not dropped either: the footnote
      // still says how many there are.
      expect(inCard('Bert'), findsNothing);
      expect(inCard('0'), findsNothing);
      expect(inCard('1 member with no open cases'), findsOneWidget);
      // Each row names the member's role, so a coordinator or supervisor
      // carrying cases doesn't read as a stray entry.
      expect(inCard('Carer'), findsOneWidget);
    });

    testWidgets('a team that is carrying nothing says so, not "no team"', (
      tester,
    ) async {
      await _pump(
        tester,
        summary,
        me: _user('me', role: UserRole.coordinator),
        workload: [
          CarerWorkload(user: _user('anna', name: 'Anna'), openCases: 0),
          CarerWorkload(user: _user('bert', name: 'Bert'), openCases: 0),
        ],
      );

      // Every row filtered away must not fall through to the roster-is-empty
      // message — there is a team, it is just idle.
      expect(find.text('No team members'), findsNothing);
      expect(find.text('2 members with no open cases'), findsOneWidget);
    });

    testWidgets('shows a supervisor an empty roster honestly', (tester) async {
      await _pump(tester, summary, me: _user('me', role: UserRole.supervisor));

      expect(find.text('Carer workload'), findsOneWidget);
      expect(find.text('No team members'), findsOneWidget);
    });

    testWidgets('a row queues a filter for that carer and switches tabs', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          dashboardSummaryProvider.overrideWith((ref) async => summary),
          currentUserProvider.overrideWith(
            (ref) async => _user('me', role: UserRole.coordinator),
          ),
          carerWorkloadProvider.overrideWith(
            (ref) async => [
              CarerWorkload(user: _user('anna', name: 'Anna'), openCases: 3),
            ],
          ),
          worklistProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/cases',
            builder: (_, _) => const Scaffold(body: Text('CASES')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The pending query auto-disposes once nothing listens, which in
      // production is the Cases tab consuming it on mount. The stub route here
      // doesn't, so hold a subscription open for the assertion below.
      container.listen(pendingCaseQueryProvider, (_, _) {});

      // The card sits below the Today preview and the KPI grid, so on the test
      // viewport it starts off-screen — scroll it in before tapping.
      await tester.ensureVisible(find.text('Anna'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anna'));
      await tester.pumpAndSettle();

      expect(find.text('CASES'), findsOneWidget);
      final pending = container.read(pendingCaseQueryProvider);
      expect(pending?.carer, 'anna');
      // The count is of OPEN cases, so the target keeps the browser's active
      // default — otherwise the list would overshoot the number tapped.
      expect(pending?.activity, CaseActivity.active);
    });
  });
}

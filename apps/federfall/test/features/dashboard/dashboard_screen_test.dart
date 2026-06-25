import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/dashboard/dashboard_screen.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, DashboardSummary summary) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardSummaryProvider.overrideWith((ref) async => summary),
        currentUserProvider.overrideWith((ref) async => null),
        worklistProvider.overrideWith((ref) async => const []),
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
        quarantineEndingSoon: [],
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
        quarantineEndingSoon: [],
        inAviaryCount: 5,
      ),
    );

    // Each of the four tiles carries a chevron affordance.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
  });
}

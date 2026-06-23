import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/dashboard/dashboard_screen.dart';
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
  testWidgets('renders KPI figures and the status breakdown', (tester) async {
    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {
          CaseStatus.inCare: 3,
          CaseStatus.inTreatment: 0,
          CaseStatus.rehab: 1,
          CaseStatus.readyForRelease: 0,
        },
        quarantineEndingSoon: [],
      ),
    );

    expect(find.text('Active cases'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Intakes this year'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(
      find.text('No quarantines ending in the next week.'),
      findsOneWidget,
    );
  });

  testWidgets('lists quarantines ending soon', (tester) async {
    await _pump(
      tester,
      DashboardSummary(
        activeCount: 1,
        intakesThisYear: 1,
        byStatus: const {CaseStatus.inCare: 1},
        quarantineEndingSoon: [
          Case(
            id: 'c1',
            animal: 'a1',
            caseNumber: '2026-001',
            status: CaseStatus.inCare,
            quarantineUntil: DateTime.now().add(const Duration(days: 2)),
          ),
        ],
      ),
    );

    expect(find.text('2026-001'), findsOneWidget);
  });
}

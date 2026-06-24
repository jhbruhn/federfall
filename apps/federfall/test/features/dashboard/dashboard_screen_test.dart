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
  testWidgets('renders KPI figures and the status breakdown', (tester) async {
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

    // Statuses with no cases are hidden, so only non-zero rows show. The
    // lifecycle is the 3-state model: in_care -> ready_for_release -> disposed.
    expect(find.text('In care'), findsOneWidget);
    expect(find.text('Ready for release'), findsOneWidget);
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

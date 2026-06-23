import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<Case> cases = const [],
  Map<String, Animal> animalsById = const {},
  String myUserId = 'me',
  AppUser? user,
}) async {
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
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CasesScreen(),
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

  testWidgets('shows the no-matches state when filters exclude all',
      (tester) async {
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

  testWidgets('always offers the profile action, hides admin for a carer',
      (tester) async {
    await _pump(
      tester,
      user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    expect(find.byTooltip('Profile'), findsOneWidget);
    expect(find.byTooltip('Administration'), findsNothing);
  });

  testWidgets('shows the admin action for a supervisor', (tester) async {
    await _pump(
      tester,
      user: const AppUser(
        id: 'u1',
        email: 's@x.org',
        role: UserRole.supervisor,
      ),
    );

    expect(find.byTooltip('Administration'), findsOneWidget);
  });
}

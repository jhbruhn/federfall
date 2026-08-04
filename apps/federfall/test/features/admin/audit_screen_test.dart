import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/audit/audit_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuditRepo extends Mock implements PbAuditEventsRepository {}

class FakeAuditQuery extends Fake implements AuditQuery {}

AuditEvent _event({
  String id = 'audt1',
  AuditAction action = AuditAction.caseHandoff,
  AuditSeverity severity = AuditSeverity.info,
  String actorLabel = 'Anna Karin',
  String subjectLabel = '2026-014',
  AuditDetail detail = const AuditDetail.none(),
  DateTime? at,
}) => AuditEvent(
  id: id,
  rawAction: action.wire,
  action: action,
  at: at ?? DateTime.utc(2026, 8, 4, 9, 15),
  actorKind: AuditActorKind.user,
  severity: severity,
  detail: detail,
  actorLabel: actorLabel,
  subjectLabel: subjectLabel,
  subjectCollection: 'cases',
  caseId: 'case1',
);

Future<void> _pump(
  WidgetTester tester, {
  required UserRole role,
  required PbAuditEventsRepository repo,
  Widget home = const AuditScreen(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async => AppUser(id: 'u1', email: 'me@x.org', role: role),
        ),
        auditEventsRepositoryProvider.overrideWith((ref) async => repo),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(FakeAuditQuery()));

  late MockAuditRepo repo;

  setUp(() {
    repo = MockAuditRepo();
    when(
      () => repo.search(
        query: any(named: 'query'),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    ).thenAnswer((_) async => PbPage(items: [_event()]));
    when(
      () => repo.forCase(
        any(),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    ).thenAnswer((_) async => PbPage(items: [_event()]));
  });

  testWidgets('a carer is refused, and never asks the server', (tester) async {
    await _pump(tester, role: UserRole.carer, repo: repo);

    expect(find.text('You are not authorized to do that'), findsOneWidget);
    verifyNever(
      () => repo.search(
        query: any(named: 'query'),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    );
  });

  testWidgets('a supervisor sees the feed', (tester) async {
    await _pump(tester, role: UserRole.supervisor, repo: repo);

    expect(find.text('Case handed over'), findsOneWidget);
    // Actor, time and subject on one line under the action.
    expect(find.textContaining('Anna Karin'), findsOneWidget);
    expect(find.textContaining('2026-014'), findsOneWidget);
  });

  testWidgets('an empty log says so rather than showing a blank list', (
    tester,
  ) async {
    when(
      () => repo.search(
        query: any(named: 'query'),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    ).thenAnswer((_) async => const PbPage(items: []));

    await _pump(tester, role: UserRole.supervisor, repo: repo);

    expect(find.text('Nothing recorded yet'), findsOneWidget);
  });

  testWidgets('the severity filter reaches the query, not just the chip', (
    tester,
  ) async {
    await _pump(tester, role: UserRole.supervisor, repo: repo);

    await tester.tap(find.widgetWithText(FilterChip, 'Security'));
    await tester.pumpAndSettle();

    final captured = verify(
      () => repo.search(
        query: captureAny(named: 'query'),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    ).captured.cast<AuditQuery>();
    expect(captured.last.severity, AuditSeverity.security);
  });

  testWidgets('an event with detail shows its facts', (tester) async {
    when(
      () => repo.search(
        query: any(named: 'query'),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    ).thenAnswer(
      (_) async => PbPage(
        items: [
          _event(
            action: AuditAction.caseIntake,
            detail: const AuditDetail.caseIntake(
              species: 'Türkentaube',
              reidentified: false,
              hasFinder: true,
            ),
          ),
        ],
      ),
    );

    await _pump(tester, role: UserRole.supervisor, repo: repo);

    expect(find.text('Case admitted'), findsOneWidget);
    expect(find.textContaining('Türkentaube'), findsOneWidget);
  });

  group('the per-case activity section', () {
    testWidgets('is invisible to a carer, who also never asks for it', (
      tester,
    ) async {
      await _pump(
        tester,
        role: UserRole.carer,
        repo: repo,
        home: const Scaffold(body: CaseActivitySection(caseId: 'case1')),
      );

      expect(find.text('Who changed what'), findsNothing);
      verifyNever(
        () => repo.forCase(
          any(),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      );
    });

    testWidgets("shows the case's own events to a supervisor", (tester) async {
      await _pump(
        tester,
        role: UserRole.supervisor,
        repo: repo,
        home: const Scaffold(body: CaseActivitySection(caseId: 'case1')),
      );

      expect(find.text('Who changed what'), findsOneWidget);
      expect(find.text('Case handed over'), findsOneWidget);
      verify(
        () => repo.forCase(
          'case1',
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).called(1);
    });

    testWidgets('stays out of the way when the log read fails', (tester) async {
      // Supplementary context must never break the case detail around it.
      when(
        () => repo.forCase(
          any(),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).thenThrow(Exception('boom'));

      await _pump(
        tester,
        role: UserRole.supervisor,
        repo: repo,
        home: const Scaffold(body: CaseActivitySection(caseId: 'case1')),
      );

      expect(find.text('Who changed what'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

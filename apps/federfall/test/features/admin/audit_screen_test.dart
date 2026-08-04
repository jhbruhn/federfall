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
  UserRole? actorRole,
  String subjectLabel = '2026-014',
  AuditDetail detail = const AuditDetail.none(),
  List<AuditFieldChange> changes = const [],
  String requestId = '',
  String? userAgent,
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
  actorRole: actorRole,
  subjectLabel: subjectLabel,
  subjectCollection: 'cases',
  caseId: 'case1',
  changes: changes,
  requestId: requestId,
  userAgent: userAgent,
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
    when(() => repo.forRequest(any())).thenAnswer((_) async => const []);
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

  group('the date filter', () {
    testWidgets('a preset narrows the query to that period', (tester) async {
      await _pump(tester, role: UserRole.supervisor, repo: repo);

      await tester.tap(find.widgetWithText(FilterChip, '7 days'));
      await tester.pumpAndSettle();

      final q = verify(
        () => repo.search(
          query: captureAny(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).captured.cast<AuditQuery>().last;

      expect(q.from, isNotNull);
      expect(q.to, isNotNull);
      // Seven days INCLUDING today, and half-open at the end — an event at
      // 23:30 today has to fall inside its own range.
      expect(q.to!.difference(q.from!).inDays, 7);
      expect(q.to!.isAfter(DateTime.now()), isTrue);
    });

    testWidgets('clearing it goes back to the whole log', (tester) async {
      await _pump(tester, role: UserRole.supervisor, repo: repo);

      await tester.tap(find.widgetWithText(FilterChip, 'Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Today'));
      await tester.pumpAndSettle();

      final q = verify(
        () => repo.search(
          query: captureAny(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).captured.cast<AuditQuery>().last;

      expect(q.from, isNull);
      expect(q.to, isNull);
    });

    testWidgets('a period and a severity narrow together', (tester) async {
      await _pump(tester, role: UserRole.supervisor, repo: repo);

      await tester.tap(find.widgetWithText(FilterChip, 'Security'));
      await tester.pumpAndSettle();
      // The filter row scrolls horizontally; the later chips are off-screen at
      // the default test surface.
      final thirty = find.widgetWithText(FilterChip, '30 days');
      await tester.ensureVisible(thirty);
      await tester.pumpAndSettle();
      await tester.tap(thirty);
      await tester.pumpAndSettle();

      final q = verify(
        () => repo.search(
          query: captureAny(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).captured.cast<AuditQuery>().last;

      expect(q.severity, AuditSeverity.security);
      expect(q.from, isNotNull);
    });
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

  // federfall-ybua.5 — the line is a summary; everything it leaves out used to
  // be unreachable, because nothing on the row responded to a tap.
  group('the detail sheet', () {
    const many = [
      AuditFieldChange(field: 'status', from: 'in_care', to: 'disposed'),
      AuditFieldChange(field: 'age_class', from: 'juvenile', to: 'adult'),
      AuditFieldChange(field: 'species', from: 'Ringeltaube', to: 'Hohltaube'),
      AuditFieldChange(field: 'name', from: 'Pip', to: 'Pipa'),
      AuditFieldChange(
        field: 'notes',
        from: 'kurz',
        to: 'lang',
        truncated: true,
      ),
    ];

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
    }

    testWidgets('reaches the changes the line had to leave out', (
      tester,
    ) async {
      when(
        () => repo.search(
          query: any(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).thenAnswer((_) async => PbPage(items: [_event(changes: many)]));

      await _pump(tester, role: UserRole.supervisor, repo: repo);
      // The line summarises and shows the first three; the 5th is nowhere.
      expect(find.textContaining('5 fields changed'), findsOneWidget);
      expect(find.textContaining('Notes'), findsNothing);

      await open(tester);

      expect(find.text('All changes'), findsOneWidget);
      // Every one of them, now, including the one the summary cut.
      expect(find.textContaining('Notes'), findsOneWidget);
      expect(find.text('Value stored shortened'), findsOneWidget);
    });

    testWidgets('names the actor with the role it snapshotted', (tester) async {
      when(
        () => repo.search(
          query: any(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).thenAnswer(
        (_) async => PbPage(items: [_event(actorRole: UserRole.carer)]),
      );

      await _pump(tester, role: UserRole.supervisor, repo: repo);
      await open(tester);

      expect(find.textContaining('Anna Karin (Carer)'), findsOneWidget);
    });

    testWidgets('shows the device only when one was recorded', (tester) async {
      await _pump(tester, role: UserRole.supervisor, repo: repo);
      await open(tester);
      expect(find.text('Device'), findsNothing);
    });

    testWidgets('puts the rest of the action back together', (tester) async {
      // What request_id is for: an intake writes several rows, and until now
      // nothing read them back.
      when(
        () => repo.search(
          query: any(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).thenAnswer((_) async => PbPage(items: [_event(requestId: 'req7')]));
      when(() => repo.forRequest('req7')).thenAnswer(
        (_) async => [
          _event(requestId: 'req7'),
          _event(
            id: 'audt2',
            action: AuditAction.animalUpdated,
            requestId: 'req7',
          ),
        ],
      );

      await _pump(tester, role: UserRole.supervisor, repo: repo);
      await open(tester);

      expect(
        find.text('1 more entry from the same action'),
        findsOneWidget,
        reason: 'the event being read is not one of its own siblings',
      );
      expect(find.textContaining('Bird updated'), findsOneWidget);
    });

    testWidgets('a failed sibling read leaves the sheet standing', (
      tester,
    ) async {
      when(
        () => repo.search(
          query: any(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).thenAnswer((_) async => PbPage(items: [_event(requestId: 'req7')]));
      when(() => repo.forRequest(any())).thenThrow(Exception('boom'));

      await _pump(tester, role: UserRole.supervisor, repo: repo);
      await open(tester);

      expect(find.text('Case handed over'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late _MockService service;
  late PbAuditEventsRepository repo;

  /// The captured arguments of the last getList call.
  var lastCall = <Symbol, dynamic>{};

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    when(() => pb.collection('audit_events')).thenReturn(service);
    // Stand in for PocketBase's parameter binding: splice the params into the
    // expression so assertions can see what would have been sent.
    when(() => pb.filter(any(), any())).thenAnswer((i) {
      var expr = i.positionalArguments.first as String;
      final params = i.positionalArguments[1] as Map<String, dynamic>? ?? {};
      for (final param in params.entries) {
        expr = expr.replaceAll('{:${param.key}}', "'${param.value}'");
      }
      return expr;
    });
    repo = PbAuditEventsRepository(pb);
    lastCall = {};
  });

  RecordModel row(
    String id,
    String created, {
    String action = 'case.updated',
  }) => RecordModel({
    'id': id,
    'action': action,
    'created': created,
    'actor_kind': 'user',
    'severity': 'info',
  });

  void stub(List<RecordModel> Function(Map<Symbol, dynamic> args) answer) {
    when(
      () => service.getList(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        skipTotal: any(named: 'skipTotal'),
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((i) async {
      lastCall = i.namedArguments;
      return ResultList(items: answer(i.namedArguments));
    });
  }

  group('keyset paging', () {
    test('sorts newest first by the composite key', () async {
      stub((_) => [row('e1', '2026-08-04 10:00:00.000Z')]);

      await repo.search();

      expect(lastCall[#sort], '-created,-id');
      expect(lastCall[#skipTotal], isTrue);
    });

    test('a full page hands back the last row as the cursor', () async {
      stub(
        (_) => [
          row('e1', '2026-08-04 10:00:02.000Z'),
          row('e2', '2026-08-04 10:00:01.000Z'),
        ],
      );

      final page = await repo.search(perPage: 2);

      expect(page.items, hasLength(2));
      expect(page.hasMore, isTrue);
      expect(
        page.cursor,
        const PbCursor(value: '2026-08-04 10:00:01.000Z', id: 'e2'),
      );
    });

    test('a short page is the end of the feed', () async {
      stub((_) => [row('e1', '2026-08-04 10:00:02.000Z')]);

      final page = await repo.search();

      expect(page.hasMore, isFalse);
      expect(page.cursor, isNull);
    });

    test('an empty page is the end too', () async {
      stub((_) => []);

      final page = await repo.search();

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('resuming asks for rows strictly older than the cursor', () async {
      stub((_) => []);

      await repo.search(
        after: const PbCursor(value: '2026-08-04 10:00:01.000Z', id: 'e2'),
      );

      final filter = lastCall[#filter] as String;
      // The id tie-break is what keeps two rows written in the same
      // millisecond from being skipped or repeated forever.
      expect(filter, contains("created < '2026-08-04 10:00:01.000Z'"));
      expect(filter, contains("created = '2026-08-04 10:00:01.000Z'"));
      expect(filter, contains("id < 'e2'"));
    });

    test('a cursor combines with the query instead of replacing it', () async {
      stub((_) => []);

      await repo.search(
        query: const AuditQuery(caseId: 'case1'),
        after: const PbCursor(value: '2026-08-04 10:00:01.000Z', id: 'e2'),
      );

      final filter = lastCall[#filter] as String;
      expect(filter, contains("case_id = 'case1'"));
      expect(filter, contains('created <'));
      // The keyset OR must not swallow the case clause.
      expect(filter, startsWith("(case_id = 'case1') &&"));
    });

    test('a projection always gets the sort key back', () async {
      stub((_) => []);

      await repo.page(fields: 'action');

      final fields = (lastCall[#fields] as String).split(',');
      expect(fields, containsAll(['action', 'id', 'created']));
    });
  });

  group('AuditQuery → filter', () {
    test('an empty query filters nothing', () {
      expect(repo.filterFor(const AuditQuery()), isNull);
    });

    test('narrows by actor, case, subject and severity', () {
      final f = repo.filterFor(
        const AuditQuery(
          actorId: 'user1',
          caseId: 'case1',
          subjectId: 'anml1',
          subjectCollection: 'animals',
          severity: AuditSeverity.security,
        ),
      );

      expect(f!.expression, contains("actor_id = 'user1'"));
      expect(f.expression, contains("case_id = 'case1'"));
      expect(f.expression, contains("subject_id = 'anml1'"));
      expect(f.expression, contains("subject_collection = 'animals'"));
      // The wire value, not the Dart name.
      expect(f.expression, contains("severity = 'security'"));
    });

    test('several actions become one parenthesised OR group', () {
      final f = repo.filterFor(
        const AuditQuery(
          actions: [AuditAction.caseHandoff, AuditAction.caseIntake],
          caseId: 'case1',
        ),
      );

      expect(
        f!.expression,
        contains("(action = 'case.handoff' || action = 'case.intake')"),
      );
      expect(f.expression, contains("case_id = 'case1'"));
    });

    test('a time range is half-open and in UTC', () {
      final f = repo.filterFor(
        AuditQuery(
          from: DateTime.utc(2026, 8),
          to: DateTime.utc(2026, 9),
        ),
      );

      expect(f!.expression, contains('created >='));
      expect(f.expression, contains('created <'));
      expect(f.expression, isNot(contains('created <=')));
    });

    test('a local time is converted, not sent as written', () {
      final local = DateTime(2026, 8, 4, 2).toLocal();
      final f = repo.filterFor(AuditQuery(from: local));

      expect(f!.expression, contains(local.toUtc().toString()));
    });
  });

  test("the request id narrows to one action's rows", () {
    final f = repo.filterFor(const AuditQuery(requestId: 'req7'));

    expect(f!.expression, contains("request_id = 'req7'"));
  });

  test('forRequest reads a whole action in the order it was written', () async {
    stub((_) => [row('e1', '2026-08-04 10:00:00.000Z')]);

    await repo.forRequest('req7');

    expect(lastCall[#filter] as String, contains("request_id = 'req7'"));
    // Ascending, unlike the feed: these are read as a sequence. The keyset
    // cursor the feed needs would be the wrong tool and the wrong order.
    expect(lastCall[#sort], 'created,id');
  });

  test('forCase narrows to one case', () async {
    stub((_) => [row('e1', '2026-08-04 10:00:00.000Z')]);

    await repo.forCase('case42');

    expect(lastCall[#filter] as String, contains("case_id = 'case42'"));
  });

  test('maps rows through AuditEvent.fromRecord', () async {
    stub(
      (_) => [row('e1', '2026-08-04 10:00:00.000Z', action: 'case.handoff')],
    );

    final page = await repo.search();

    expect(page.items.single.action, AuditAction.caseHandoff);
    expect(page.items.single.id, 'e1');
  });
}

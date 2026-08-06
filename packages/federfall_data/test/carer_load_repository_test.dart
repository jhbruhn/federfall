import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late _MockService service;
  late PbCarerLoadRepository repo;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    when(() => pb.collection('case_carer_load')).thenReturn(service);
    repo = PbCarerLoadRepository(pb);
  });

  void stubRows(List<RecordModel> items) {
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
    ).thenAnswer((_) async => ResultList<RecordModel>(items: items));
  }

  test('maps a row to the carer and their open caseload', () async {
    stubRows([
      RecordModel({
        'id': 'org1:anna',
        'carer': 'anna',
        'org': 'org1',
        'open_cases': 4,
      }),
    ]);

    final rows = await repo.all();

    expect(rows.single.carer, 'anna');
    expect(rows.single.openCases, 4);
    expect(rows.single.org, 'org1');
    // The composite view key, not a record id — a member carrying cases in two
    // orgs has one row per org.
    expect(rows.single.id, 'org1:anna');
  });

  test('reads open_cases whether it arrives as a number or a string', () async {
    // `open_cases` is `COUNT(...)`, which PocketBase cannot trace back to a
    // real column and therefore types as `json` (CLAUDE.md). REST decodes that
    // on the way out, so a number is the normal case — but the mapper must not
    // depend on which of the two it gets.
    stubRows([
      RecordModel({'id': 'org1:bert', 'carer': 'bert', 'open_cases': '7'}),
    ]);

    expect((await repo.all()).single.openCases, 7);
  });

  test('a carer reading the view gets an empty list, not a failure', () async {
    // The list rule admits coordinators/supervisors only, and a list request
    // applies it as a filter — so "no rows" is the rules answering.
    stubRows([]);

    expect(await repo.all(), isEmpty);
  });

  test('asks for every row, unsorted — the roster does the ordering', () async {
    stubRows([]);

    await repo.all();

    final query = verify(
      () => service.getList(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        skipTotal: any(named: 'skipTotal'),
        filter: captureAny(named: 'filter'),
        sort: captureAny(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    ).captured;
    expect(query, [null, null]);
  });
}

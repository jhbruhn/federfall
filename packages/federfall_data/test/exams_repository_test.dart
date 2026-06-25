import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late _MockService service;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    when(() => pb.filter(any(), any()))
        .thenAnswer((i) => 'BOUND:${i.positionalArguments[0]}');
    when(
      () => service.getFullList(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => []);
  });

  group('PbExamsRepository', () {
    late PbExamsRepository repo;
    setUp(() {
      when(() => pb.collection('exams')).thenReturn(service);
      repo = PbExamsRepository(pb);
    });

    test('forCase() filters by case, newest exam first', () async {
      await repo.forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      final sort = verify(
        () => service.getFullList(
          filter: any(named: 'filter'),
          sort: captureAny(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      ).captured.single;
      expect(sort, '-examined_at');
    });

    test('forAnimal() filters by the animal relation', () async {
      await repo.forAnimal('anml1');
      verify(() => pb.filter('animal = {:a}', {'a': 'anml1'})).called(1);
    });
  });

  group('PbExamFindingsRepository', () {
    late PbExamFindingsRepository repo;
    setUp(() {
      when(() => pb.collection('exam_findings')).thenReturn(service);
      repo = PbExamFindingsRepository(pb);
    });

    test('forExam() filters by the parent exam', () async {
      await repo.forExam('exam1');
      verify(() => pb.filter('exam = {:e}', {'e': 'exam1'})).called(1);
    });

    test('forCase() traverses the grandparent exam.case', () async {
      await repo.forCase('case1');
      verify(() => pb.filter('exam.case = {:c}', {'c': 'case1'})).called(1);
    });
  });
}

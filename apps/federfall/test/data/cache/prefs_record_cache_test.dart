import 'package:federfall/data/cache/prefs_record_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> rec(String id) => {'id': id, 'name': 'n$id'};

  test('round-trips a single record', () async {
    final cache = PrefsRecordCache();
    await cache.putRecord('cases', 'c1', rec('c1'));

    expect(await cache.getRecord('cases', 'c1'), rec('c1'));
    expect(await cache.getRecord('cases', 'missing'), isNull);
  });

  test('round-trips a list result by query key', () async {
    final cache = PrefsRecordCache();
    await cache.putList('cases', 'k', [rec('c1'), rec('c2')]);

    final got = await cache.getList('cases', 'k');
    expect(got, hasLength(2));
    expect(got!.first['id'], 'c1');
  });

  test('persists across instances (shared key)', () async {
    await PrefsRecordCache().putRecord('cases', 'c1', rec('c1'));
    expect(await PrefsRecordCache().getRecord('cases', 'c1'), isNotNull);
  });

  test('bounds records per collection, dropping oldest', () async {
    final cache = PrefsRecordCache(maxRecordsPerCollection: 2);
    await cache.putRecord('cases', 'c1', rec('c1'));
    await cache.putRecord('cases', 'c2', rec('c2'));
    await cache.putRecord('cases', 'c3', rec('c3'));

    expect(await cache.getRecord('cases', 'c1'), isNull, reason: 'evicted');
    expect(await cache.getRecord('cases', 'c2'), isNotNull);
    expect(await cache.getRecord('cases', 'c3'), isNotNull);
  });

  test('evictLists drops only that collection', () async {
    final cache = PrefsRecordCache();
    await cache.putList('cases', 'k', [rec('c1')]);
    await cache.putList('animals', 'k', [rec('a1')]);

    await cache.evictLists('cases');

    expect(await cache.getList('cases', 'k'), isNull);
    expect(await cache.getList('animals', 'k'), isNotNull);
  });

  test('clear empties everything', () async {
    final cache = PrefsRecordCache();
    await cache.putRecord('cases', 'c1', rec('c1'));
    await cache.clear();
    expect(await cache.getRecord('cases', 'c1'), isNull);
  });
}

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockStatsRepo extends Mock implements PbStatsRepository {}

void main() {
  test('the period defaults to the year in progress', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(statisticsPeriodProvider).year, DateTime.now().year);
    expect(container.read(statisticsPeriodProvider).month, isNull);

    container
        .read(statisticsPeriodProvider.notifier)
        .select(StatsPeriod.allTime);
    expect(container.read(statisticsPeriodProvider).isAllTime, isTrue);
  });

  test('the provider asks the server for the selected period', () async {
    // federfall-nmwi: the aggregation is server-side now, so what is left to
    // assert here is that the request carries the period AND this device's UTC
    // offset — the offset is what makes "2026" mean the same thing here as in
    // the annual report (see stats.pb.js / lib_stats.js).
    final repo = MockStatsRepo();
    const stats = OrgStatistics(year: 2025, intakes: 7);
    when(
      () => repo.fetch(
        year: any(named: 'year'),
        month: any(named: 'month'),
        tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
      ),
    ).thenAnswer((_) async => stats);

    final container = ProviderContainer(
      overrides: [statsRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      statisticsProvider(year: 2025).future,
    );

    expect(result.intakes, 7);
    verify(
      () => repo.fetch(
        year: 2025,
        tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      ),
    ).called(1);
  });

  test('an all-time period sends no year at all', () async {
    final repo = MockStatsRepo();
    when(
      () => repo.fetch(
        year: any(named: 'year'),
        month: any(named: 'month'),
        tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
      ),
    ).thenAnswer((_) async => const OrgStatistics());

    final container = ProviderContainer(
      overrides: [statsRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(container.dispose);

    await container.read(statisticsProvider().future);

    verify(
      () => repo.fetch(tzOffsetMinutes: any(named: 'tzOffsetMinutes')),
    ).called(1);
  });

  test('a month period is sent alongside its year', () async {
    final repo = MockStatsRepo();
    when(
      () => repo.fetch(
        year: any(named: 'year'),
        month: any(named: 'month'),
        tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
      ),
    ).thenAnswer((_) async => const OrgStatistics(year: 2026, month: 3));

    final container = ProviderContainer(
      overrides: [statsRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(container.dispose);

    await container.read(statisticsProvider(year: 2026, month: 3).future);

    verify(
      () => repo.fetch(
        year: 2026,
        month: 3,
        tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
      ),
    ).called(1);
  });
}

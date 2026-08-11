import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

/// A full-ish body of the shape `pb_hooks/stats.pb.js` emits.
Map<String, dynamic> _body({
  Object? year = 2026,
  Object? series,
  List<Object?>? outcomes,
}) => {
  'period': {'year': year},
  'totals': {
    'intakes': 12,
    'closed': 8,
    'inCare': 4,
    'avgDaysInCare': 15.5,
    'releaseRate': 0.625,
    'mortalityRate': 0.25,
  },
  'series':
      series ??
      {
        'kind': 'month',
        'points': [
          {'key': 1, 'count': 3},
          {'key': 2, 'count': 0},
        ],
        'previous': {
          'year': 2025,
          'points': [
            {'key': 1, 'count': 5},
          ],
        },
      },
  'outcomes':
      outcomes ??
      [
        {'type': 'released', 'count': 5},
        {'type': 'died', 'count': 3},
      ],
  'species': [
    {'label': 'Stadttaube', 'count': 9},
  ],
  'conditions': [
    {'label': 'Trichomoniasis', 'count': 6},
  ],
  'intakeYears': [2026, 2025],
};

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late _MockPb pb;
  late PbStatsRepository repo;

  void stub(Map<String, dynamic> body) {
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenAnswer((_) async => body);
  }

  setUp(() {
    pb = _MockPb();
    repo = PbStatsRepository(pb);
  });

  test('parses totals, breakdowns and the series', () async {
    stub(_body());

    final stats = await repo.fetch(year: 2026, tzOffsetMinutes: 120);

    expect(stats.year, 2026);
    expect(stats.intakes, 12);
    expect(stats.closed, 8);
    expect(stats.inCare, 4);
    expect(stats.avgTimeInCareDays, 15.5);
    expect(stats.releaseRate, 0.625);
    expect(stats.mortalityRate, 0.25);
    expect(stats.outcomes.first.type, DispositionType.released);
    expect(stats.outcomes.first.count, 5);
    expect(stats.bySpecies.single.label, 'Stadttaube');
    expect(stats.byCondition.single.label, 'Trichomoniasis');
    expect(stats.intakeYears, [2026, 2025]);
    expect(stats.series.kind, SeriesBucket.month);
    expect(stats.series.points.map((p) => p.key), [1, 2]);
    expect(stats.series.points.map((p) => p.count), [3, 0]);
    expect(stats.series.previousYear, 2025);
    expect(stats.series.previousPoints.single.count, 5);
  });

  test('sends the period and the caller offset, and nothing else', () async {
    stub(_body());

    await repo.fetch(year: 2026, tzOffsetMinutes: 120);

    final query =
        verify(
              () => pb.send<Map<String, dynamic>>(
                '/api/federfall/stats',
                query: captureAny(named: 'query'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(query, {'year': '2026', 'tzOffsetMinutes': '120'});
  });

  test('an all-time period omits ?year= entirely', () async {
    // Not `year=0` and not an empty string: the route reads an absent param as
    // "every case on record", and `.get()` yields "" for both.
    stub(_body(year: null));

    await repo.fetch(tzOffsetMinutes: 120);

    final query =
        verify(
              () => pb.send<Map<String, dynamic>>(
                any(),
                query: captureAny(named: 'query'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(query.containsKey('year'), isFalse);
  });

  test('an outcome type this build cannot name is counted, not dropped', () {
    // The server emits "" for a disposition whose type is unknown to the
    // reader; it still has to add up on screen, so it parses to a null type
    // rather than disappearing.
    final stats = OrgStatistics.fromJson(
      _body(
        outcomes: [
          {'type': 'released', 'count': 1},
          {'type': '', 'count': 2},
        ],
      ),
    );

    expect(stats.outcomes, hasLength(2));
    expect(stats.outcomes.last.type, isNull);
    expect(stats.outcomes.last.count, 2);
  });

  test('a body missing keys parses to zeros rather than throwing', () {
    // A server one minor version older simply omits a key: a screen showing 0
    // for a figure it was not sent beats a screen that fails to build.
    final stats = OrgStatistics.fromJson(const {});

    expect(stats.year, isNull);
    expect(stats.intakes, 0);
    expect(stats.releaseRate, isNull);
    expect(stats.series.points, isEmpty);
    expect(stats.series.previousYear, isNull);
    expect(stats.intakeYears, isEmpty);
  });

  test('a month period parses its day series and comparison month', () {
    final stats = OrgStatistics.fromJson({
      ..._body(),
      'period': const {'year': 2026, 'month': 3},
      'series': const {
        'kind': 'day',
        'points': [
          {'key': 1, 'count': 2},
        ],
        'previous': {
          'year': 2025,
          'month': 3,
          'points': [
            {'key': 1, 'count': 4},
          ],
        },
      },
    });

    expect(stats.month, 3);
    expect(stats.series.kind, SeriesBucket.day);
    expect(stats.series.previousYear, 2025);
    // The comparison is the SAME month a year earlier, and says so.
    expect(stats.series.previousMonth, 3);
  });

  test('a month is only sent alongside its year', () async {
    stub(_body());

    await repo.fetch(month: 3, tzOffsetMinutes: 0);

    final query =
        verify(
              () => pb.send<Map<String, dynamic>>(
                any(),
                query: captureAny(named: 'query'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(query.containsKey('month'), isFalse);
  });

  test('an unknown bucket kind falls back to a year series', () {
    final stats = OrgStatistics.fromJson(
      _body(
        series: {
          'kind': 'week',
          'points': [
            {'key': 2024, 'count': 4},
          ],
        },
      ),
    );

    expect(stats.series.kind, SeriesBucket.year);
    expect(stats.series.points.single.key, 2024);
    expect(stats.series.previousYear, isNull);
  });

  group('sponsorships block (federfall-ys7z)', () {
    test('parses the standing patronage figures', () {
      final stats = OrgStatistics.fromJson({
        ..._body(),
        'sponsorships': const {
          'total': 9,
          'active': 7,
          'monthlyCents': 4250,
          'oneTimeCents': 10000,
          'noIntervalCents': 500,
        },
      });

      expect(stats.sponsorships.total, 9);
      expect(stats.sponsorships.active, 7);
      expect(stats.sponsorships.monthlyCents, 4250);
      // The three sums stay separate: a one-off donation divided into a month
      // is an invented number, and an amount with no interval has no rhythm to
      // normalise. Neither may be folded into the monthly figure.
      expect(stats.sponsorships.oneTimeCents, 10000);
      expect(stats.sponsorships.noIntervalCents, 500);
      expect(stats.sponsorships.isEmpty, isFalse);
    });

    test('a server that does not send the block zeroes it', () {
      // Minor-version skew in either direction: the app must render nothing
      // rather than throw, and „no patronages" is the safe reading.
      final stats = OrgStatistics.fromJson(_body());

      expect(stats.sponsorships.total, 0);
      expect(stats.sponsorships.isEmpty, isTrue);
    });

    test('an org whose patronages have all ENDED is not empty', () {
      // This is why `total` exists at all: without it the app could not tell
      // an archive worth opening from an org that never had a patronage, and
      // would hide the rows a Zuwendungsbestätigung is written from.
      final stats = OrgStatistics.fromJson({
        ..._body(),
        'sponsorships': const {'total': 4, 'active': 0},
      });

      expect(stats.sponsorships.isEmpty, isFalse);
      expect(stats.sponsorships.active, 0);
      expect(stats.sponsorships.monthlyCents, 0);
    });
  });

  test('a transport failure arrives as a RepositoryException', () async {
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenThrow(ClientException(statusCode: 403));

    expect(
      () => repo.fetch(year: 2026),
      throwsA(
        isA<RepositoryException>().having(
          (e) => e.kind,
          'kind',
          RepositoryErrorKind.unauthorized,
        ),
      ),
    );
  });
}

import 'dart:async';

import 'package:federfall_data/src/repository_exception.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:meta/meta.dart';
import 'package:pocketbase/pocketbase.dart';

/// One labelled count in a breakdown (species, diagnosis).
@immutable
class StatCount {
  const StatCount(this.label, this.count);

  final String label;
  final int count;
}

/// A terminal-outcome count, keyed by type so the UI resolves the label.
/// A null [type] bucket counts dispositions whose wire value this app version
/// does not know — it can be counted, but not named and not filtered for.
@immutable
class OutcomeStat {
  const OutcomeStat(this.type, this.count);

  final DispositionType? type;
  final int count;
}

/// What one point of an [IntakeSeries] counts: a month of the selected year,
/// or a whole calendar year when the period is "all time".
enum SeriesBucket {
  month('month'),
  year('year');

  const SeriesBucket(this.wire);

  final String wire;

  static SeriesBucket? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// One bar: [key] is the month (1–12) or the calendar year, per
/// [IntakeSeries.kind].
@immutable
class IntakePoint {
  const IntakePoint(this.key, this.count);

  final int key;
  final int count;
}

/// Intakes over time (federfall-nmwi), plus the year before for comparison.
///
/// The server emits every bucket of the period, zeros included, so the series
/// reads as a period rather than as a list of the buckets that happened to
/// have intakes — a January with no admissions is a fact about the year.
@immutable
class IntakeSeries {
  const IntakeSeries({
    required this.kind,
    this.points = const [],
    this.previousYear,
    this.previousPoints = const [],
  });

  final SeriesBucket kind;
  final List<IntakePoint> points;

  /// The comparison year, or null when there is nothing to compare against —
  /// an all-time period, or a previous year with no intakes at all (an
  /// all-zero series is noise, not a comparison).
  final int? previousYear;

  /// The comparison year's buckets, aligned with [points] by key.
  final List<IntakePoint> previousPoints;
}

/// The org's reporting figures for one period, as computed by
/// `GET /api/federfall/stats` (`pb_hooks/stats.pb.js`).
///
/// Everything here is server-side aggregate: the app does not see the case
/// rows behind it. That is the point — a monthly series with a comparison year
/// behind it spans more history than a handset should be pulling, and it is
/// the same rows the annual report prints, so the screen and the PDF agree by
/// construction rather than by two implementations staying in step.
@immutable
class OrgStatistics {
  const OrgStatistics({
    this.year,
    this.intakes = 0,
    this.closed = 0,
    this.inCare = 0,
    this.avgTimeInCareDays,
    this.releaseRate,
    this.mortalityRate,
    this.series = const IntakeSeries(kind: SeriesBucket.year),
    this.outcomes = const [],
    this.bySpecies = const [],
    this.byCondition = const [],
    this.intakeYears = const [],
  });

  /// Parses the route's body. Every field is defaulted rather than required:
  /// a server one minor version older simply omits a key, and a screen that
  /// renders "0" for a figure it was not sent is a better failure than one
  /// that throws.
  factory OrgStatistics.fromJson(Map<String, dynamic> json) {
    final period = json['period'];
    final totals = json['totals'];
    final t = totals is Map ? totals : const {};

    List<StatCount> counts(Object? raw) => [
      for (final e in raw is List ? raw : const [])
        if (e is Map && e['label'] is String)
          StatCount(e['label'] as String, _int(e['count'])),
    ];

    return OrgStatistics(
      year: period is Map ? _intOrNull(period['year']) : null,
      intakes: _int(t['intakes']),
      closed: _int(t['closed']),
      inCare: _int(t['inCare']),
      avgTimeInCareDays: _doubleOrNull(t['avgDaysInCare']),
      releaseRate: _doubleOrNull(t['releaseRate']),
      mortalityRate: _doubleOrNull(t['mortalityRate']),
      series: _series(json['series']),
      outcomes: [
        for (final e
            in json['outcomes'] is List ? json['outcomes'] as List : const [])
          if (e is Map)
            OutcomeStat(
              DispositionType.fromWire(e['type']),
              _int(e['count']),
            ),
      ],
      bySpecies: counts(json['species']),
      byCondition: counts(json['conditions']),
      intakeYears: [
        for (final e
            in json['intakeYears'] is List
                ? json['intakeYears'] as List
                : const [])
          if (_intOrNull(e) case final y?) y,
      ],
    );
  }

  static IntakeSeries _series(Object? raw) {
    if (raw is! Map) return const IntakeSeries(kind: SeriesBucket.year);
    final previous = raw['previous'];
    return IntakeSeries(
      // An unknown bucket kind reads as a year series: the chart then labels
      // its keys as the numbers they are instead of as month names it guessed.
      kind: SeriesBucket.fromWire(raw['kind']) ?? SeriesBucket.year,
      points: _points(raw['points']),
      previousYear: previous is Map ? _intOrNull(previous['year']) : null,
      previousPoints: previous is Map ? _points(previous['points']) : const [],
    );
  }

  static List<IntakePoint> _points(Object? raw) => [
    for (final e in raw is List ? raw : const [])
      if (e is Map)
        if (_intOrNull(e['key']) case final key?)
          IntakePoint(key, _int(e['count'])),
  ];

  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
  static double? _doubleOrNull(Object? v) => v is num ? v.toDouble() : null;

  /// The selected calendar year, or null for every case on record.
  final int? year;

  /// Cases ADMITTED in the period — the intake cohort the annual report uses,
  /// so two consecutive periods can be added up without double-counting.
  final int intakes;

  /// Cases of that cohort that have reached a terminal disposition.
  final int closed;

  /// Cases of that cohort still in care ([intakes] − [closed]).
  final int inCare;

  /// Mean days from admission to terminal disposition, or null if none — a
  /// fractional count, not the whole days a per-case report column shows.
  final double? avgTimeInCareDays;

  /// Share of ENDED cases released, 0–1, or null while nothing has ended.
  ///
  /// Over ended cases, never over intakes: a rate whose denominator is
  /// admissions sags every time admissions rise, which is exactly when it must
  /// not (that is the count breakdown's job, not the rate's).
  final double? releaseRate;

  /// Share of ended cases that died or were euthanized, 0–1, or null while
  /// nothing has ended. The two are one figure on purpose — a bird that was
  /// put down did not survive.
  final double? mortalityRate;

  /// Intakes over time, with the previous year behind it where there is one.
  final IntakeSeries series;

  /// Terminal disposition type → count, over the period's ended cases.
  final List<OutcomeStat> outcomes;

  /// Species → intake count, most common first.
  final List<StatCount> bySpecies;

  /// Diagnosis → number of the period's cases recording it, most common first.
  final List<StatCount> byCondition;

  /// Every calendar year with at least one intake, newest first — org-wide
  /// regardless of the selected period, because it is what the period picker
  /// (here and on the annual-report sheet) offers.
  ///
  /// Only years that actually have intakes: a fixed "last ten years" range
  /// would invite reporting on a year the org did not exist. Years are the
  /// caller's LOCAL ones, matching how the period's boundaries are resolved —
  /// a case admitted at 00:30 on New Year's Day belongs to the year the carer
  /// was living in.
  final List<int> intakeYears;
}

/// Reads the org's reporting figures off `GET /api/federfall/stats`
/// (federfall-nmwi).
///
/// A single-method class rather than the usual interface + `Pb`-prefixed impl
/// split (like `PbCaseReportRepository`) — one member would just trip the
/// `one_member_abstracts` lint; mock this concrete class directly in tests.
class PbStatsRepository {
  PbStatsRepository(
    this.pb, {
    this.networkTimeout = const Duration(seconds: 30),
  });

  final PocketBase pb;

  /// Longer than a plain collection read: the server aggregates the org's
  /// whole case history for the comparison series.
  final Duration networkTimeout;

  /// The figures for [year] (null = every case on record).
  ///
  /// [tzOffsetMinutes] is the caller's own UTC offset (e.g.
  /// `DateTime.now().timeZoneOffset.inMinutes`) — the server has no timezone
  /// database to resolve a zone name against, so it asks the client to state
  /// its offset rather than guessing a zone. It decides which side of New Year
  /// a late-evening admission falls on, and passing it is what makes this
  /// screen and the annual report agree on what a year is.
  Future<OrgStatistics> fetch({int? year, int? tzOffsetMinutes}) async {
    return _guard(() async {
      final res = await pb.send<Map<String, dynamic>>(
        '/api/federfall/stats',
        query: {
          if (year != null) 'year': '$year',
          if (tzOffsetMinutes != null) 'tzOffsetMinutes': '$tzOffsetMinutes',
        },
      );
      return OrgStatistics.fromJson(res);
    });
  }

  /// Mirrors `PbRepository._guard`: timeout → network, SDK errors →
  /// [RepositoryException], and any other failure (e.g. an unexpected response
  /// shape) wrapped so the UI error states get a stable type.
  Future<R> _guard<R>(Future<R> Function() op) async {
    try {
      return await op().timeout(networkTimeout);
    } on TimeoutException {
      throw const RepositoryException(
        'Could not reach the server',
        kind: RepositoryErrorKind.network,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    } on RepositoryException {
      rethrow;
    } on Object catch (e) {
      throw RepositoryException('Unexpected repository failure: $e', cause: e);
    }
  }
}

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'statistics_providers.g.dart';

/// A reporting period: a calendar year, one month of it, or everything on
/// record.
///
/// A [month] without a [year] names no period at all — "March" is not a date —
/// so it can only be set alongside one, which is also what the server enforces
/// (`?month=` requires `?year=`).
@immutable
class StatsPeriod {
  const StatsPeriod({this.year, this.month});

  /// Every case on record.
  static const allTime = StatsPeriod();

  final int? year;
  final int? month;

  bool get isAllTime => year == null;

  /// Same year, different month (null = the whole year). All time keeps no
  /// month, so switching to it and back cannot leave a stray one behind.
  StatsPeriod withMonth(int? month) =>
      StatsPeriod(year: year, month: year == null ? null : month);

  StatsPeriod withYear(int? year) =>
      StatsPeriod(year: year, month: year == null ? null : month);

  @override
  bool operator ==(Object other) =>
      other is StatsPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// The reporting period the statistics screen is showing. Defaults to the year
/// in progress.
///
/// Held in a provider rather than in the screen's state because the annual
/// report is exported from the same screen and must offer the same period
/// (federfall-nmwi): a user who has just read the 2025 figures and taps
/// "export" is asking for the 2025 report, not for whatever year the sheet
/// would have defaulted to.
@riverpod
class StatisticsPeriod extends _$StatisticsPeriod {
  @override
  StatsPeriod build() => StatsPeriod(year: DateTime.now().year);

  /// A named action rather than a setter: `select(...)` says what the tap
  /// meant, where an assignment would only say what changed.
  // ignore: use_setters_to_change_properties
  void select(StatsPeriod period) => state = period;
}

/// The org's reporting figures for the period — [year] (null = all time),
/// optionally narrowed to one [month] of it — computed server-side by
/// `pb_hooks/stats.pb.js` (federfall-nmwi).
///
/// The aggregation used to run here, over `cases` + `dispositions` + `animals`
/// pulled unpaginated to the device. It moved to the server for two reasons:
/// intakes over time need more history than a handset should be carrying (the
/// same mistake federfall-80tc fixed for the CSV export), and the annual
/// report already aggregates those very rows — one implementation is the only
/// way the printed report and this screen can be relied on to agree.
///
/// **Coordinators and supervisors only** — the screen gates on
/// `canViewReports`, and the route enforces it: the figures are org-wide by
/// construction, so a carer gets a 403 rather than a narrower answer.
///
/// The device's own UTC offset goes with the request: the server has no
/// timezone database, and the offset is what decides whether a New Year's Eve
/// admission counts to the closing year or the opening one — the same
/// question the annual report asks (`annual_report_sheet.dart`).
@riverpod
Future<OrgStatistics> statistics(Ref ref, {int? year, int? month}) async {
  final repo = await ref.watch(statsRepositoryProvider.future);
  return repo.fetch(
    year: year,
    month: month,
    tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
  );
}

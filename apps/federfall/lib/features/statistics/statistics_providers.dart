import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'statistics_providers.g.dart';

/// The reporting period the statistics screen is showing: a calendar year, or
/// null for every case on record. Defaults to the year in progress.
///
/// Held in a provider rather than in the screen's state because the annual
/// report is exported from the same screen and must offer the same period
/// (federfall-nmwi): a user who has just read the 2025 figures and taps
/// "export" is asking for the 2025 report, not for whatever year the sheet
/// would have defaulted to.
@riverpod
class StatisticsPeriod extends _$StatisticsPeriod {
  @override
  int? build() => DateTime.now().year;

  /// A named action rather than a setter: `select(2025)` says what the tap
  /// meant, where `period = 2025` would only say what changed.
  // ignore: use_setters_to_change_properties
  void select(int? year) => state = year;
}

/// The org's reporting figures for [year] (null = all time), computed
/// server-side by `pb_hooks/stats.pb.js` (federfall-nmwi).
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
Future<OrgStatistics> statistics(Ref ref, {int? year}) async {
  final repo = await ref.watch(statsRepositoryProvider.future);
  return repo.fetch(
    year: year,
    tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
  );
}

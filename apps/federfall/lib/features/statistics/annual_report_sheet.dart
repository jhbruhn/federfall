import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The years offered behind the export sheet's "earlier years" picker: every
/// year with a recorded intake, newest first, minus the two the segmented
/// control already shows as buttons.
///
/// Only years that actually have intakes ([intakeYears], off `Statistics`) —
/// a fixed "last ten years" range would invite printing a report for a year
/// the org did not exist. A gap year with no admissions is likewise not
/// offered: there is nothing in it to report.
List<int> earlierReportYears(List<int> intakeYears, DateTime now) {
  final shown = {now.year, now.year - 1};
  return [
    for (final year in intakeYears)
      if (!shown.contains(year)) year,
  ];
}

/// Opens the annual-report export sheet (federfall-dk0c): pick a period, then
/// take the report as a PDF or its case table as a CSV.
Future<void> showAnnualReportSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const AnnualReportSheet());

/// Period picker plus one button per format. Both formats come off the same
/// server route (`pb_hooks/annual_report.pb.js`) over the same rows, so they
/// are two renderings of one report rather than two features — which is why
/// they share a sheet instead of sitting in the app bar as two icons.
class AnnualReportSheet extends ConsumerStatefulWidget {
  const AnnualReportSheet({super.key});

  @override
  ConsumerState<AnnualReportSheet> createState() => _AnnualReportSheetState();
}

class _AnnualReportSheetState extends ConsumerState<AnnualReportSheet> {
  /// Resolved once, in `initState`: the sheet's own labels and its default
  /// selection must not shift if it happens to be open across midnight on New
  /// Year's Eve, and the year sent to the server has to be the one the button
  /// said.
  late final DateTime _now = DateTime.now();

  /// The selected period: a calendar year, or null for every case on record.
  /// Defaults to the year in progress.
  late int? _year = _now.year;

  /// A year chosen from the picker, which then joins the segmented control as
  /// its own button — so the selection stays a single value with a single
  /// visible state instead of a segment plus a competing dropdown.
  int? _pickedYear;

  /// Which format is currently being fetched, so only the tapped button shows
  /// a spinner (and neither can be tapped twice into two share sheets).
  bool? _busyCsv;

  Future<void> _export({required bool csv}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Captured before the first await, like the case report's share button:
    // the report follows the app's own UI language, and the server has no
    // timezone database (see case_report.pb.js), so this device states its own
    // offset — which is what decides whether a New Year's Eve admission counts
    // to the closing year or the opening one.
    final lang = Localizations.localeOf(context).languageCode;
    final tzOffsetMinutes = _now.timeZoneOffset.inMinutes;
    final year = _year;
    final filename =
        '${l10n.statsExportFileName('${year ?? l10n.statsExportFileAllTime}')}'
        '.${csv ? 'csv' : 'pdf'}';

    setState(() => _busyCsv = csv);
    try {
      final repo = await ref.read(caseReportRepositoryProvider.future);
      final bytes = await repo.fetchAnnualReport(
        year: year,
        csv: csv,
        lang: lang,
        tzOffsetMinutes: tzOffsetMinutes,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: csv ? 'text/csv' : 'application/pdf',
              name: filename,
            ),
          ],
          fileNameOverrides: [filename],
        ),
      );
      // The sheet has done its job; leaving it up over the share result reads
      // as if the export were still pending.
      if (navigator.mounted) unawaited(navigator.maybePop());
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } finally {
      if (mounted) setState(() => _busyCsv = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final busy = _busyCsv != null;

    // The years on record come off the statistics the screen behind this sheet
    // has already loaded — the same org-wide, coordinator/supervisor scope the
    // report itself runs in, so there is nothing extra to fetch. Until it
    // lands (or if it fails) the two recent years and "all time" still work;
    // only the picker waits.
    final earlierYears = earlierReportYears(
      ref.watch(statisticsProvider).value?.intakeYears ?? const [],
      _now,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.statsExportAction, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.statsExportPeriod,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Labelled with the years themselves rather than "this"/"last": in
          // January the difference matters, and a concrete number leaves
          // nothing to work out. A year taken from the picker becomes a fourth
          // button here.
          SegmentedButton<int?>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _now.year, label: Text('${_now.year}')),
              ButtonSegment(
                value: _now.year - 1,
                label: Text('${_now.year - 1}'),
              ),
              if (_pickedYear != null)
                ButtonSegment(
                  value: _pickedYear,
                  label: Text('$_pickedYear'),
                ),
              ButtonSegment(
                value: null,
                label: Text(l10n.statsExportAllTime),
              ),
            ],
            selected: {_year},
            onSelectionChanged: busy
                ? null
                : (s) => setState(() => _year = s.single),
          ),
          if (earlierYears.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<int>(
                enabled: !busy,
                // Selecting from the picker also selects the period: opening
                // the menu to choose a year and then having to press the
                // resulting button as well would be a second step for a
                // decision already made.
                onSelected: (year) => setState(() {
                  _pickedYear = year;
                  _year = year;
                }),
                itemBuilder: (context) => [
                  for (final year in earlierYears)
                    PopupMenuItem(value: year, child: Text('$year')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.statsExportEarlierYears,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: l10n.statsExportPdf,
            icon: Icons.picture_as_pdf_outlined,
            isLoading: _busyCsv == false,
            onPressed: busy ? null : () => _export(csv: false),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            icon: _busyCsv == true
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view_outlined),
            label: Text(l10n.statsExportCsv),
            onPressed: busy ? null : () => _export(csv: true),
          ),
        ],
      ),
    );
  }
}

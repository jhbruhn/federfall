import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/period_selector.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

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
  /// Resolved once: the sheet's own labels and its default selection must not
  /// shift if it happens to be open across midnight on New Year's Eve, and the
  /// year sent to the server has to be the one the button said.
  late final DateTime _now = DateTime.now();

  /// The selected period: a calendar year, or null for every case on record.
  ///
  /// Seeded from the period the statistics screen behind this sheet is showing
  /// (federfall-nmwi) — someone who has just read the 2025 figures and taps
  /// "export" is asking for the 2025 report. It stays sheet-local from there:
  /// exporting a different year should not quietly re-scope the screen under
  /// the sheet.
  late StatsPeriod _period = ref.read(statisticsPeriodProvider);

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
    final year = _period.year;
    final month = _period.month;
    final filename =
        '${l10n.statsExportFileName('${year ?? l10n.statsExportFileAllTime}')}'
        '.${csv ? 'csv' : 'pdf'}';

    setState(() => _busyCsv = csv);
    try {
      final repo = await ref.read(caseReportRepositoryProvider.future);
      final bytes = await repo.fetchAnnualReport(
        year: year,
        month: month,
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
    // report itself runs in, and org-wide regardless of the period shown, so
    // there is nothing extra to fetch. Until it lands (or if it fails) the two
    // recent years and "all time" still work; only the picker waits.
    final screenPeriod = ref.watch(statisticsPeriodProvider);
    final intakeYears =
        ref
            .watch(
              statisticsProvider(
                year: screenPeriod.year,
                month: screenPeriod.month,
              ),
            )
            .value
            ?.intakeYears ??
        const <int>[];

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
          // The same control the statistics screen uses, so "2026" cannot mean
          // one thing on screen and another in the exported file.
          PeriodSelector(
            selected: _period,
            intakeYears: intakeYears,
            now: _now,
            enabled: !busy,
            onChanged: (picked) => setState(() => _period = picked),
          ),
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

import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The period an annual report covers. Both bounded options resolve to a
/// calendar YEAR rather than a rolling window (unlike the intake map's
/// `_Period`): an annual report is filed for a year, and "the last 12 months"
/// is not a period any authority asks about.
enum ReportPeriod {
  /// The year in progress — a mid-year interim figure.
  thisYear,

  /// The year just gone. This is the one that gets filed, and the reason the
  /// export offers a year at all: the report is written in January.
  lastYear,

  /// Every case on record, for a founding-to-date total.
  allTime;

  /// The `year` the report route wants, or null for [allTime].
  int? yearAt(DateTime now) => switch (this) {
    ReportPeriod.thisYear => now.year,
    ReportPeriod.lastYear => now.year - 1,
    ReportPeriod.allTime => null,
  };
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
  /// Defaults to the year just ended — the one an annual report is for.
  ReportPeriod _period = ReportPeriod.lastYear;

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
    final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final year = _period.yearAt(DateTime.now());
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
    final now = DateTime.now();
    final busy = _busyCsv != null;

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
          // The two year options are labelled with the year itself rather than
          // "this"/"last": in January the difference matters and a concrete
          // number leaves nothing to work out.
          SegmentedButton<ReportPeriod>(
            segments: [
              ButtonSegment(
                value: ReportPeriod.lastYear,
                label: Text('${now.year - 1}'),
              ),
              ButtonSegment(
                value: ReportPeriod.thisYear,
                label: Text('${now.year}'),
              ),
              ButtonSegment(
                value: ReportPeriod.allTime,
                label: Text(l10n.statsExportAllTime),
              ),
            ],
            selected: {_period},
            onSelectionChanged: busy
                ? null
                : (s) => setState(() => _period = s.single),
          ),
          const SizedBox(height: AppSpacing.lg),
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

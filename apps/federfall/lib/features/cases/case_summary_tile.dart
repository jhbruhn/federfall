import 'package:federfall/features/cases/carer_line.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A terse, tappable row for one [CaseSummary] (number · status · date). Shared
/// by the animal lifetime record (FED-7.6) and the case overview's prior-cases
/// list (blp.3). When [accessible] the row opens the full case; otherwise it is
/// a non-tappable stub carrying a "no access" badge.
///
/// It keeps the status and the dates that the case BROWSER's row dropped
/// (federfall-78k6.5), and the divergence is deliberate: there the default
/// caseload is the active split, so "In Pflege" printed on nearly every row and
/// distinguished nothing. Here every case is a past chapter of one bird's life
/// and how each ended is the whole question — so do not "fix" this one to
/// match. It also reads `case_summaries`, which is deliberately free of
/// clinical detail (1700000016) and could not name a diagnosis even if this
/// row wanted to.
class CaseSummaryTile extends StatelessWidget {
  const CaseSummaryTile({
    required this.summary,
    required this.accessible,
    super.key,
  });

  final CaseSummary summary;
  final bool accessible;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    final status = summary.status;
    final start = summary.admittedAt ?? summary.foundAt;
    final end = summary.endedAt;
    final span = switch ((start, end)) {
      (final s?, final e?) =>
        '${formatLocalDate(materialL10n, s)} – '
            '${formatLocalDate(materialL10n, e)}',
      (final s?, null) => formatLocalDate(materialL10n, s),
      (null, final e?) => formatLocalDate(materialL10n, e),
      (null, null) => null,
    };
    final subtitle = [
      if (status != null) caseStatusLabel(l10n, status),
      ?span,
      if (!accessible) l10n.animalCaseNoAccess,
    ].join(' · ');
    final carerId = summary.activeCarer;
    final hasCarer = carerId != null && carerId.isNotEmpty;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      isThreeLine: hasCarer,
      leading: Icon(
        accessible ? Icons.medical_information_outlined : Icons.lock_outline,
      ),
      title: Text(summary.caseNumber ?? l10n.caseNewTitle),
      subtitle: subtitle.isEmpty && !hasCarer
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle.isNotEmpty) Text(subtitle),
                if (hasCarer) CarerLine(carerId),
              ],
            ),
      trailing: accessible ? const Icon(Icons.chevron_right) : null,
      enabled: accessible,
      onTap: accessible
          ? () => context.go(AppRoutes.caseDetail(summary.id))
          : null,
    );
  }
}

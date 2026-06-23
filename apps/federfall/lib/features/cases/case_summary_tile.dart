import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A terse, tappable row for one [CaseSummary] (number · status · date). Shared
/// by the animal lifetime record (FED-7.6) and the case overview's prior-cases
/// list (blp.3). When [accessible] the row opens the full case; otherwise it is
/// a non-tappable stub carrying a "no access" badge.
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
        '${materialL10n.formatMediumDate(s)} – '
            '${materialL10n.formatMediumDate(e)}',
      (final s?, null) => materialL10n.formatMediumDate(s),
      (null, final e?) => materialL10n.formatMediumDate(e),
      (null, null) => null,
    };
    final subtitle = [
      if (status != null) caseStatusLabel(l10n, status),
      ?span,
      if (!accessible) l10n.animalCaseNoAccess,
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        accessible ? Icons.medical_information_outlined : Icons.lock_outline,
      ),
      title: Text(summary.caseNumber ?? l10n.caseNewTitle),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: accessible ? const Icon(Icons.chevron_right) : null,
      enabled: accessible,
      onTap: accessible
          ? () => context.go(AppRoutes.caseDetail(summary.id))
          : null,
    );
  }
}

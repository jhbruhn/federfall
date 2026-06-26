import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/disposition/disposition_sheet.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';

/// A case outcome as a chronology event (FED-4.11): the terminal disposition,
/// shown with an icon matched to the outcome and its key details.
class DispositionTile extends StatelessWidget {
  const DispositionTile({
    required this.disposition,
    this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Disposition disposition;

  /// When set, the tile offers an edit action that opens the disposition sheet
  /// (where the outcome can be corrected or deleted, re-opening the case).
  final String? caseId;
  final bool canEdit;
  final bool isLast;

  IconData get _icon => switch (disposition.type) {
    DispositionType.released => Icons.flight_takeoff,
    DispositionType.placedInAviary => Icons.holiday_village_outlined,
    DispositionType.died => Icons.sentiment_very_dissatisfied_outlined,
    DispositionType.euthanized => Icons.medical_services_outlined,
    DispositionType.transferred => Icons.local_shipping_outlined,
    DispositionType.returnedToOwner => Icons.home_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final d = disposition;
    final date = d.disposedAt ?? d.created;

    final detail = [
      if (d.releaseLocation case final r? when r.isNotEmpty) r,
      if (d.releaseType case final r? when r.isNotEmpty) r,
      if (d.transferDestination case final t? when t.isNotEmpty) t,
      if (d.transferType case final t? when t.isNotEmpty) t,
    ].join(' · ');

    final caseId = this.caseId;
    return TimelineItem(
      icon: _icon,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: (caseId == null || !canEdit)
          ? null
          : IconButton(
              icon: const Icon(Icons.edit_outlined),
              iconSize: 20,
              padding: EdgeInsets.zero,
              tooltip: l10n.dispositionEditTitle,
              onPressed: () => showDispositionSheet(
                context,
                caseId: caseId,
                disposition: d,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dispositionTypeLabel(l10n, d.type),
            style: theme.textTheme.bodyLarge,
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (d.vet case final v? when v.isNotEmpty)
            Text(
              l10n.dispositionVetLine(v),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (d.reason case final r? when r.isNotEmpty)
            Text(r, style: theme.textTheme.bodyMedium),
          if (d.vetSignedOff) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.dispositionVetSignedOff,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

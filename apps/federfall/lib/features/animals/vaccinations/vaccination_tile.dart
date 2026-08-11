import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_sheet.dart';
import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One vaccination as a chronology event (1700000087): the product and what it
/// protects against, the batch number, dose and route, whether a booster is
/// planned — and an overdue badge when that date has passed.
///
/// [caseId] is only the timeline to refresh after a write; it is never stored
/// on the record.
class VaccinationTile extends ConsumerWidget {
  const VaccinationTile({
    required this.vaccination,
    this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Vaccination vaccination;
  final String? caseId;
  final bool canEdit;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final notes = vaccination.notes;
    final batch = vaccination.batch;
    final vet = vaccination.vet;

    final routeLabel = (ref.watch(medicationRoutesProvider).value ?? const [])
        .where((r) => r.id == vaccination.route)
        .map((r) => r.label)
        .firstOrNull;

    final detail = [
      if (vaccination.dose case final d?)
        formatDose(l10n, d, vaccination.doseUnit),
      ?routeLabel,
      if (vaccination.series case final s?) vaccinationSeriesLabel(l10n, s),
    ].join(' · ');

    return TimelineItem(
      icon: Icons.vaccines_outlined,
      date: formatLocalDate(materialL10n, vaccination.at),
      isLast: isLast,
      trailing: canEdit
          ? VaccinationMenu(vaccination: vaccination, caseId: caseId)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  vaccination.vaccine,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (vaccination.isDue()) ...[
                const SizedBox(width: AppSpacing.sm),
                TagChip(
                  label: l10n.vaccinationDueChip,
                  color: theme.colorScheme.error,
                ),
              ],
            ],
          ),
          if (vaccination.target case final t? when t.isNotEmpty)
            Text(t, style: theme.textTheme.bodyMedium),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (batch != null && batch.isNotEmpty)
            Text(
              l10n.vaccinationBatchLine(batch),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (vet != null && vet.isNotEmpty)
            Text(
              vet,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (vaccination.nextDueAt case final due?)
            Text(
              l10n.vaccinationNextDueLine(
                formatLocalDate(materialL10n, due),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: vaccination.isDue()
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (notes != null && notes.isNotEmpty)
            Text(notes, style: theme.textTheme.bodyMedium),
          if (vaccination.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            VaccinationImageStrip(vaccination: vaccination),
          ],
        ],
      ),
    );
  }
}

/// The overflow menu shared by the case-timeline tile and the animal detail's
/// vaccination rows: edit and delete.
///
/// Delete only appears for the record's author or a supervisor, mirroring the
/// server rule (1700000087). There is no "move to another bird": `animal` is
/// frozen server-side, so a shot recorded on the wrong bird is deleted and
/// re-entered rather than re-pointed.
///
/// Every action writes the record, which requires holding the BIRD — so the
/// whole menu is custody-gated here rather than at each call site.
class VaccinationMenu extends ConsumerWidget {
  const VaccinationMenu({required this.vaccination, this.caseId, super.key});

  final Vaccination vaccination;
  final String? caseId;

  void _invalidate(WidgetRef ref) {
    ref
      ..invalidate(vaccinationsForAnimalProvider(vaccination.animal))
      ..invalidate(vaccineLabelsProvider);
    if (caseId case final id?) ref.invalidate(caseBundleProvider(id));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.vaccinationDeleteTitle,
      message: l10n.vaccinationDeleteConfirm,
      confirmLabel: l10n.vaccinationDeleteAction,
      action: () async {
        final repo = await ref.read(vaccinationsRepositoryProvider.future);
        await repo.delete(vaccination.id);
        _invalidate(ref);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final me = ref.watch(currentUserProvider).value;
    if (!(ref.watch(canWriteAnimalProvider(vaccination.animal)).value ??
        false)) {
      return const SizedBox.shrink();
    }

    return TimelineEntryMenu(
      editLabel: l10n.vaccinationEditAction,
      onEdit: () => unawaited(
        showVaccinationSheet(
          context,
          animalId: vaccination.animal,
          vaccination: vaccination,
        ),
      ),
      deleteLabel: l10n.vaccinationDeleteAction,
      onDelete: vaccinationDeletableBy(vaccination, me)
          ? () => _delete(context, ref)
          : null,
    );
  }
}

/// Thumbnails of a vaccination's images — a vial label, or a paper Impfausweis
/// that came with the bird. Tapping one opens it full-size.
class VaccinationImageStrip extends ConsumerWidget {
  const VaccinationImageStrip({required this.vaccination, super.key});

  final Vaccination vaccination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(vaccinationsRepositoryProvider).value;
    if (repo == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // `attachments` is a protected file field (1700000087), but the access
    // token is appended at download time (ProtectedFileCacheManager), so these
    // URLs stay token-free and cached thumbnails render without minting one.
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: vaccination.attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => Semantics(
          button: true,
          label: context.l10n.photoViewLabel(
            i + 1,
            vaccination.attachments.length,
          ),
          child: GestureDetector(
            onTap: () => unawaited(
              showImageViewer(
                context,
                imageUrls: [
                  for (final f in vaccination.attachments)
                    repo.fileUrl(vaccination.id, f).toString(),
                ],
                initialIndex: i,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedFileImage(
                url: repo.fileUrl(
                  vaccination.id,
                  vaccination.attachments[i],
                  thumb: '200x200',
                ),
                width: 96,
                height: 96,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

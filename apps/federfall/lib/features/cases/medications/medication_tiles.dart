import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A prescription (medication plan) as a chronology event (FED-4.6): drug,
/// dose, route and frequency, a controlled-drug badge, and a menu to log a
/// dose against it, edit or delete it.
class PrescriptionTile extends ConsumerWidget {
  const PrescriptionTile({
    required this.plan,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Medication plan;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.prescriptionDeleteTitle,
      message: l10n.prescriptionDeleteConfirm,
      confirmLabel: l10n.medDeleteAction,
      action: () async {
        final repo = await ref.read(medicationsRepositoryProvider.future);
        await repo.delete(plan.id);
        ref.invalidate(caseBundleProvider(caseId));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final date = plan.startedAt ?? plan.created;
    // A plan still being given gets a direct "log dose" action inline — the
    // most contextual home for dosing (xc8.5). Ended plans don't.
    final isActive =
        plan.endedAt == null || plan.endedAt!.isAfter(DateTime.now());

    final frequency = medicationFrequencyLabel(
      l10n,
      plan.frequencyKind,
      plan.intervalHours,
    );
    final routesById =
        ref.watch(medicationRoutesByIdProvider).value ?? const {};
    final detail = [
      if (formatDose(plan.dose, plan.doseUnit) case final d when d.isNotEmpty)
        d,
      ?routesById[plan.route]?.label,
      if (frequency.isNotEmpty) frequency,
      if (plan.frequency case final f? when f.isNotEmpty) f,
    ].join(' · ');

    return TimelineItem(
      icon: Icons.medication_outlined,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit
          ? TimelineEntryMenu(
              tooltip: l10n.medMenuTooltip,
              leadingItems: [
                PopupMenuItem(
                  onTap: () => showAdministrationSheet(
                    context,
                    caseId: caseId,
                    plan: plan,
                  ),
                  child: Text(l10n.medLogDose),
                ),
              ],
              editLabel: l10n.medEditAction,
              onEdit: () => showPrescriptionSheet(
                context,
                caseId: caseId,
                plan: plan,
              ),
              deleteLabel: l10n.medDeleteAction,
              onDelete: () => _confirmDelete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.prescriptionEventLabel(plan.drug),
            style: theme.textTheme.bodyLarge,
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (plan.isControlled)
                TagChip(
                  label: l10n.medControlledBadge,
                  color: theme.colorScheme.errorContainer,
                  onColor: theme.colorScheme.onErrorContainer,
                ),
              if (plan.endedAt case final e?)
                Text(
                  l10n.medUntil(materialL10n.formatMediumDate(e)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (plan.instructions case final i? when i.isNotEmpty)
            Text(i, style: theme.textTheme.bodyMedium),
          if (plan.prescribedBy case final p? when p.isNotEmpty)
            Text(
              l10n.medPrescribedByLine(p),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (isActive && canEdit)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => showAdministrationSheet(
                    context,
                    caseId: caseId,
                    plan: plan,
                  ),
                  icon: const Icon(Icons.vaccines_outlined, size: 18),
                  label: Text(l10n.medLogDose),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single administered dose as a chronology event (FED-4.6).
class AdministrationTile extends ConsumerWidget {
  const AdministrationTile({
    required this.administration,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final MedicationAdministration administration;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.doseDeleteTitle,
      message: l10n.doseDeleteConfirm,
      confirmLabel: l10n.medDeleteAction,
      action: () async {
        final repo = await ref.read(
          medicationAdministrationsRepositoryProvider.future,
        );
        await repo.delete(administration.id);
        ref.invalidate(caseBundleProvider(caseId));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final a = administration;
    final date = a.administeredAt ?? a.created;

    final dose = formatDose(a.dose, a.doseUnit);
    final drugDose = dose.isEmpty ? a.drug : '${a.drug} $dose';
    final routesById =
        ref.watch(medicationRoutesByIdProvider).value ?? const {};
    final route = routesById[a.route]?.label;

    return TimelineItem(
      icon: Icons.vaccines_outlined,
      date: formatEventDate(materialL10n, date, withTime: true),
      isLast: isLast,
      trailing: canEdit
          ? TimelineEntryMenu(
              editLabel: l10n.medEditAction,
              tooltip: l10n.medMenuTooltip,
              onEdit: () => showAdministrationSheet(
                context,
                caseId: caseId,
                administration: a,
              ),
              deleteLabel: l10n.medDeleteAction,
              onDelete: () => _confirmDelete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.doseEventLabel(drugDose),
            style: theme.textTheme.bodyLarge,
          ),
          if (route != null)
            Text(
              route,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (a.notes case final n? when n.isNotEmpty)
            Text(n, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

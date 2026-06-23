import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
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
    this.isLast = false,
    super.key,
  });

  final Medication plan;
  final String caseId;
  final bool isLast;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.prescriptionDeleteTitle),
        content: Text(l10n.prescriptionDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.medDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(medicationsRepositoryProvider.future);
    await repo.delete(plan.id);
    ref.invalidate(medicationsForCaseProvider(caseId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final date = plan.startedAt ?? plan.created;

    final frequency = medicationFrequencyLabel(
      l10n,
      plan.frequencyKind,
      plan.intervalHours,
    );
    final detail = [
      if (formatDose(plan.dose, plan.doseUnit) case final d when d.isNotEmpty)
        d,
      if (plan.route case final r?) medicationRouteLabel(l10n, r),
      if (frequency.isNotEmpty) frequency,
      if (plan.frequency case final f? when f.isNotEmpty) f,
    ].join(' · ');

    return TimelineItem(
      icon: Icons.medication_outlined,
      date: date == null ? '' : materialL10n.formatMediumDate(date),
      isLast: isLast,
      trailing: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        iconSize: 20,
        padding: EdgeInsets.zero,
        tooltip: l10n.medMenuTooltip,
        itemBuilder: (context) => [
          PopupMenuItem(
            onTap: () =>
                showAdministrationSheet(context, caseId: caseId, plan: plan),
            child: Text(l10n.medLogDose),
          ),
          PopupMenuItem(
            onTap: () =>
                showPrescriptionSheet(context, caseId: caseId, plan: plan),
            child: Text(l10n.medEditAction),
          ),
          PopupMenuItem(
            onTap: () => _confirmDelete(context, ref),
            child: Text(l10n.medDeleteAction),
          ),
        ],
      ),
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
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (plan.isControlled)
                _Tag(
                  label: l10n.medControlledBadge,
                  color: theme.colorScheme.errorContainer,
                  onColor: theme.colorScheme.onErrorContainer,
                ),
              if (plan.endedAt case final e?)
                Text(
                  l10n.medUntil(materialL10n.formatMediumDate(e)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          if (plan.instructions case final i? when i.isNotEmpty)
            Text(i, style: theme.textTheme.bodyMedium),
          if (plan.prescribedBy case final p? when p.isNotEmpty)
            Text(
              l10n.medPrescribedByLine(p),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    this.isLast = false,
    super.key,
  });

  final MedicationAdministration administration;
  final String caseId;
  final bool isLast;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.doseDeleteTitle),
        content: Text(l10n.doseDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.medDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo =
        await ref.read(medicationAdministrationsRepositoryProvider.future);
    await repo.delete(administration.id);
    ref.invalidate(administrationsForCaseProvider(caseId));
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
    final route = a.route == null ? null : medicationRouteLabel(l10n, a.route!);

    return TimelineItem(
      icon: Icons.vaccines_outlined,
      date: date == null ? '' : materialL10n.formatMediumDate(date),
      isLast: isLast,
      trailing: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        iconSize: 20,
        padding: EdgeInsets.zero,
        tooltip: l10n.medMenuTooltip,
        itemBuilder: (context) => [
          PopupMenuItem(
            onTap: () => showAdministrationSheet(
              context,
              caseId: caseId,
              administration: a,
            ),
            child: Text(l10n.medEditAction),
          ),
          PopupMenuItem(
            onTap: () => _confirmDelete(context, ref),
            child: Text(l10n.medDeleteAction),
          ),
        ],
      ),
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
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (a.notes case final n? when n.isNotEmpty)
            Text(n, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A small rounded tag (controlled-drug badge).
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, required this.onColor});

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: onColor),
      ),
    );
  }
}

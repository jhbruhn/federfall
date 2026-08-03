import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/features/cases/vet_appointments/vet_appointment_sheet.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One vet appointment as a chronology event (federfall-fnpo): the practice and
/// the reason, the outcome once written, and a status chip — how long until the
/// visit, how long it has been missed, or that it was attended or cancelled.
class VetAppointmentTile extends ConsumerWidget {
  const VetAppointmentTile({
    required this.appointment,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final VetAppointment appointment;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  /// Sets or clears one of the two resolution stamps. Both are plain stamps, so
  /// attending and cancelling are the same write with a different field.
  Future<void> _stamp(
    BuildContext context,
    WidgetRef ref, {
    required String field,
    required bool set,
  }) => runQuickAction(context, () async {
    final repo = await ref.read(vetAppointmentsRepositoryProvider.future);
    await repo.update(appointment.id, {
      field: set ? DateTime.now().toUtc().toIso8601String() : '',
    });
    ref
      ..invalidate(caseBundleProvider(caseId))
      ..invalidate(worklistSourceProvider);
  });

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.vetAppointmentDeleteTitle,
      message: l10n.vetAppointmentDeleteConfirm,
      confirmLabel: l10n.vetAppointmentDeleteAction,
      action: () async {
        final repo = await ref.read(vetAppointmentsRepositoryProvider.future);
        await repo.delete(appointment.id);
        ref
          ..invalidate(caseBundleProvider(caseId))
          ..invalidate(worklistSourceProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final startsAt = appointment.startsAt;
    final attended = appointment.attendedAt != null;
    final cancelled = appointment.cancelledAt != null;
    final outcome = appointment.outcome;
    final reason = appointment.reason;
    final vet = appointment.vet;

    return TimelineItem(
      icon: switch ((attended, cancelled)) {
        (true, _) => Icons.event_available_outlined,
        (_, true) => Icons.event_busy_outlined,
        _ => Icons.medical_services_outlined,
      },
      date: formatEventDate(
        materialL10n,
        startsAt ?? appointment.created,
        withTime: startsAt != null,
      ),
      isLast: isLast,
      trailing: canEdit
          ? TimelineEntryMenu(
              editLabel: l10n.vetAppointmentEditAction,
              onEdit: () => showVetAppointmentSheet(
                context,
                caseId: caseId,
                appointment: appointment,
              ),
              middleActions: [
                MenuAction(
                  icon: attended
                      ? Icons.replay_outlined
                      : Icons.check_circle_outline,
                  label: attended
                      ? l10n.vetAppointmentReopen
                      : l10n.vetAppointmentMarkAttended,
                  onTap: () => _stamp(
                    context,
                    ref,
                    field: 'attended_at',
                    set: !attended,
                  ),
                ),
                // The common after-the-visit move is "write down what they
                // said", so it gets its own entry straight into the outcome
                // field rather than making the carer open the editor and hunt.
                MenuAction(
                  icon: Icons.notes_outlined,
                  label: l10n.vetAppointmentAddOutcome,
                  onTap: () => showVetAppointmentSheet(
                    context,
                    caseId: caseId,
                    appointment: appointment,
                    focusOutcome: true,
                  ),
                ),
                MenuAction(
                  icon: cancelled
                      ? Icons.event_repeat_outlined
                      : Icons.event_busy_outlined,
                  label: cancelled
                      ? l10n.vetAppointmentUncancel
                      : l10n.vetAppointmentCancel,
                  onTap: () => _stamp(
                    context,
                    ref,
                    field: 'cancelled_at',
                    set: !cancelled,
                  ),
                ),
              ],
              deleteLabel: l10n.vetAppointmentDeleteAction,
              onDelete: () => _delete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vet?.isNotEmpty ?? false ? vet! : l10n.vetAppointmentDefaultLabel,
            style: theme.textTheme.bodyLarge,
          ),
          if (reason != null && reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(reason, style: theme.textTheme.bodyMedium),
            ),
          if (outcome != null && outcome.isNotEmpty)
            _OutcomeBox(
              outcome: outcome,
              label: l10n.vetAppointmentOutcomeLabel,
            ),
          _StatusChip(
            appointment: appointment,
            attended: attended,
            cancelled: cancelled,
          ),
        ],
      ),
    );
  }
}

/// The outcome, set apart from the reason so "what we went for" and "what came
/// of it" don't read as one paragraph months later.
class _OutcomeBox extends StatelessWidget {
  const _OutcomeBox({required this.outcome, required this.label});

  final String outcome;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(outcome, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Attended / cancelled / how far off — the one line that says whether this
/// appointment still needs anything from the carer.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.appointment,
    required this.attended,
    required this.cancelled,
  });

  final VetAppointment appointment;
  final bool attended;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final startsAt = appointment.startsAt?.toLocal();
    final now = DateTime.now();

    final (label, color, onColor) = switch (null) {
      _ when attended => (
        l10n.vetAppointmentAttended,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _ when cancelled => (
        l10n.vetAppointmentCancelled,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      // Unresolved and in the past: it needs marking attended or cancelled, so
      // it reads like the open loop it is.
      _ when startsAt != null && startsAt.isBefore(now) => (
        l10n.worklistOverdueDays(
          DateUtils.dateOnly(
            now,
          ).difference(DateUtils.dateOnly(startsAt)).inDays,
        ),
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      _ when startsAt != null => (
        l10n.worklistDueInDays(startsAt.difference(now).inDays),
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _ => (null, scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    if (label == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: onColor),
        ),
      ),
    );
  }
}

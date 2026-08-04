import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/admin/audit/audit_labels.dart';
import 'package:federfall/features/admin/audit/audit_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Opens the full record of one audit event.
///
/// The feed line is a summary — it names how many fields changed and shows the
/// first few. On an append-only log that is not enough on its own: what the
/// summary leaves out was previously unreachable, so this sheet is where
/// EVERYTHING the row holds is legible (federfall-ybua.5). Read-only by nature;
/// there is nothing here to edit.
Future<void> showAuditDetailSheet(BuildContext context, AuditEvent event) =>
    showAppSheet<void>(
      context,
      builder: (_) => _AuditDetailSheet(event: event),
    );

class _AuditDetailSheet extends ConsumerWidget {
  const _AuditDetailSheet({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final line = auditLine(l10n, event);
    final when = DateFormat.yMMMEd(
      l10n.localeName,
    ).add_Hms().format(event.at.toLocal());

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: AppSpacing.md,
              children: [
                Icon(
                  line.icon,
                  color: event.severity == AuditSeverity.security
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                Expanded(
                  child: Text(line.title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Who and when, in full. The role is a snapshot too, and saying
            // „Anna Karin (Betreuerin)" is the point of having stored it.
            _Row(
              label: l10n.auditDetailActor,
              value: [
                auditActorName(l10n, event),
                if (event.actorRole case final role?)
                  '(${userRoleLabel(l10n, role)})',
              ].join(' '),
            ),
            _Row(label: l10n.auditDetailWhen, value: when),
            if (line.subtitle case final subject?)
              _Row(label: l10n.auditDetailSubject, value: subject),
            if (event.caseLabel.isNotEmpty)
              _Row(label: l10n.auditFactCase, value: event.caseLabel),
            _Row(
              label: l10n.auditDetailSeverity,
              value: auditSeverityLabel(l10n, event.severity),
            ),

            for (final fact in line.facts)
              if (fact.label != l10n.auditFactCase)
                _Row(
                  label: fact.value.isEmpty ? '' : fact.label,
                  value: fact.value.isEmpty ? fact.label : fact.value,
                ),

            // EVERY change, not the first three. A row that can never be
            // edited or deleted should not be summarised into unreachability.
            if (event.changes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.auditDetailChanges,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final change in event.changes)
                _ChangeRow(change: change, collection: event.subjectCollection),
            ],

            // Only ever present when the organisation opted in.
            if (event.ip?.isNotEmpty ?? false)
              _Row(label: l10n.auditFactIp, value: event.ip!),
            if (event.userAgent?.isNotEmpty ?? false)
              _Row(label: l10n.auditDetailUserAgent, value: event.userAgent!),

            _RequestSiblings(event: event),
          ],
        ),
      ),
    );
  }
}

/// One labelled line. An empty [label] renders the value alone, for a fact that
/// IS its own statement.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          if (label.isNotEmpty)
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// One field change, with its truncation stated rather than implied.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.collection});

  final AuditFieldChange change;
  final String collection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(
            label: auditFieldLabel(l10n, collection, change.field),
            value: auditChangeText(l10n, collection, change),
          ),
          // A value the emitter clamped for storage. Saying so is the honest
          // reading: without it a shortened note looks like the whole note.
          if (change.truncated)
            Padding(
              padding: const EdgeInsets.only(left: 138),
              child: Text(
                l10n.auditDetailTruncated,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What else the same action wrote.
///
/// Silent when there is nothing to add — one row is the common case, and a
/// section headed "the rest of this action" listing only the event already on
/// screen would be noise. Equally silent on a failed read: this is context, not
/// part of the record.
class _RequestSiblings extends ConsumerWidget {
  const _RequestSiblings({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (event.requestId.isEmpty) return const SizedBox.shrink();

    final siblings = ref.watch(auditRequestSiblingsProvider(event.requestId));
    return siblings.maybeWhen(
      data: (all) {
        final others = all.where((e) => e.id != event.id).toList();
        if (others.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.auditDetailSameAction(others.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final other in others)
              _Row(
                label: '',
                value: [
                  auditActionTitle(l10n, other.action, other.rawAction),
                  ?auditLine(l10n, other).subtitle,
                ].join(' · '),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

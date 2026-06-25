import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/exams/exam_sheet.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One structured exam as a chronology event (FED-4.8): a [TimelineItem] on its
/// exam date showing the top-line vitals, any abnormal body-system findings,
/// and a menu to edit or delete. [findings] are the rows already fetched for
/// this exam by the timeline.
class ExamTile extends ConsumerWidget {
  const ExamTile({
    required this.exam,
    required this.findings,
    required this.caseId,
    required this.animalId,
    this.isLast = false,
    super.key,
  });

  final Exam exam;
  final List<ExamFinding> findings;
  final String caseId;
  final String animalId;
  final bool isLast;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.examDeleteTitle),
        content: Text(l10n.examDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.examDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Deleting the exam cascades its findings server-side (cascadeDelete).
    final repo = await ref.read(examsRepositoryProvider.future);
    await repo.delete(exam.id);
    ref
      ..invalidate(examsForCaseProvider(caseId))
      ..invalidate(examFindingsForCaseProvider(caseId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final at = exam.examinedAt ?? exam.created;
    final abnormal = [
      for (final f in findings)
        if (f.status == FindingStatus.abnormal) f,
    ];
    final normalCount =
        findings.where((f) => f.status == FindingStatus.normal).length;

    final vitals = <String>[
      if (exam.bodyCondition case final bc?)
        l10n.examBodyConditionShort(bc),
      if (exam.hydration case final h?) hydrationLabel(l10n, h),
      if (exam.mentation case final m?) mentationLabel(l10n, m),
    ];

    return TimelineItem(
      icon: Icons.monitor_heart_outlined,
      date: at == null ? '' : materialL10n.formatMediumDate(at.toLocal()),
      isLast: isLast,
      trailing: _Menu(
        onEdit: () => showExamSheet(
          context,
          caseId: caseId,
          animalId: animalId,
          exam: exam,
          findings: findings,
        ),
        onDelete: () => _delete(context, ref),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.examTitle, style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            vitals.isEmpty ? l10n.examNoVitals : vitals.join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final f in abnormal)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                f.note?.isNotEmpty ?? false
                    ? '${bodySystemLabel(l10n, f.system!)}: ${f.note}'
                    : bodySystemLabel(l10n, f.system!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (normalCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l10n.examNormalCount(normalCount),
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

class _Menu extends StatelessWidget {
  const _Menu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      iconSize: 20,
      padding: EdgeInsets.zero,
      tooltip: l10n.examEditAction,
      itemBuilder: (context) => [
        PopupMenuItem(onTap: onEdit, child: Text(l10n.examEditAction)),
        PopupMenuItem(onTap: onDelete, child: Text(l10n.examDeleteAction)),
      ],
    );
  }
}

import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/exams/exam_sheet.dart';
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
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Exam exam;
  final List<ExamFinding> findings;
  final String caseId;
  final String animalId;
  final bool canEdit;
  final bool isLast;

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Deleting the exam cascades its findings server-side (cascadeDelete).
    return confirmAndDelete(
      context,
      title: l10n.examDeleteTitle,
      message: l10n.examDeleteConfirm,
      confirmLabel: l10n.examDeleteAction,
      action: () async {
        final repo = await ref.read(examsRepositoryProvider.future);
        await repo.delete(exam.id);
        ref.invalidate(caseBundleProvider(caseId));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final at = exam.examinedAt ?? exam.created;

    // Top-line vitals as labelled facts so each value is readable at a glance
    // rather than crammed into a single dot-separated line.
    // Body condition (1–5) and temperature default to 0 in PocketBase when not
    // recorded, so treat 0 as "unset" and omit it rather than showing 0/5 or
    // 0.0 °C.
    final vitals = <(String, String)>[
      if (exam.bodyCondition case final bc? when bc != 0)
        (l10n.examBodyConditionLabel, '$bc/5'),
      if (exam.temperature case final t? when t != 0)
        (l10n.examTemperatureLabel, t.toStringAsFixed(1)),
      if (exam.hydration case final h?)
        (l10n.examHydrationLabel, hydrationLabel(l10n, h)),
      if (exam.mentation case final m?)
        (l10n.examMentationLabel, mentationLabel(l10n, m)),
      if (exam.mmColor case final c?)
        (l10n.examMmColorLabel, mmColorLabel(l10n, c)),
      if (exam.mmTexture case final tx?)
        (l10n.examMmTextureLabel, mmTextureLabel(l10n, tx)),
    ];

    // Abnormal findings first (with their note), then a single muted line
    // naming the systems that were assessed and found normal.
    final abnormal = [
      for (final f in findings)
        if (f.status == FindingStatus.abnormal && f.system != null) f,
    ];
    final normalSystems = [
      for (final f in findings)
        if (f.status == FindingStatus.normal && f.system != null)
          bodySystemLabel(l10n, f.system!),
    ];
    final notes = exam.notes;

    return TimelineItem(
      icon: Icons.monitor_heart_outlined,
      date: formatEventDate(materialL10n, at),
      isLast: isLast,
      trailing: canEdit
          ? TimelineEntryMenu(
              editLabel: l10n.examEditAction,
              onEdit: () => showExamSheet(
                context,
                caseId: caseId,
                animalId: animalId,
                exam: exam,
                findings: findings,
              ),
              deleteLabel: l10n.examDeleteAction,
              onDelete: () => _delete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.examTitle, style: theme.textTheme.bodyLarge),
          if (vitals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l10n.examNoVitals,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final (label, value) in vitals)
              _Fact(label: label, value: value),
          for (final f in abnormal)
            _Fact(
              label: bodySystemLabel(l10n, f.system!),
              value: f.note?.isNotEmpty ?? false
                  ? f.note!
                  : findingStatusLabel(l10n, FindingStatus.abnormal),
              emphasis: theme.colorScheme.error,
            ),
          if (normalSystems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${findingStatusLabel(l10n, FindingStatus.normal)}: '
                '${normalSystems.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(notes, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// One labelled fact line — a muted "label:" followed by its value, wrapping
/// freely so long values are never clipped. [emphasis] colours the value (e.g.
/// red for an abnormal finding); the label stays muted.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.emphasis});

  final String label;
  final String value;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: emphasis,
                fontWeight: emphasis == null ? null : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

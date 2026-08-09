import 'dart:async';

import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/conditions/condition_entry_sheet.dart';
import 'package:federfall/features/cases/microscopy/microscopy_attachment.dart';
import 'package:federfall/features/cases/microscopy/microscopy_providers.dart';
import 'package:federfall/features/cases/microscopy/microscopy_sheet.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One microscopy sample as a chronology event: what was examined, what it
/// showed (worst finding first), and who looked.
///
/// [findings] are the rows the timeline already fetched for this sample.
class MicroscopyTile extends ConsumerWidget {
  const MicroscopyTile({
    required this.sample,
    required this.findings,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final MicroscopySample sample;
  final List<MicroscopyFinding> findings;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Deleting the sample cascades its findings server-side (cascadeDelete).
    return confirmAndDelete(
      context,
      title: l10n.microscopyDeleteTitle,
      message: l10n.microscopyDeleteConfirm,
      confirmLabel: l10n.microscopyDeleteAction,
      action: () async {
        final repo = await ref.read(
          microscopySamplesRepositoryProvider.future,
        );
        await repo.delete(sample.id);
        ref.invalidate(caseBundleProvider(caseId));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final typesById =
        ref.watch(microscopyFindingTypesByIdProvider).value ??
        const <String, MicroscopyFindingType>{};

    // Strongest grade first — that is what anybody reads this row for.
    final graded =
        [
          for (final f in findings)
            if (f.severity != null) f,
        ]..sort(
          (a, b) => b.severity!.index.compareTo(a.severity!.index),
        );
    final findingText = [
      for (final f in graded)
        '${_nameOf(f, typesById)} ${microscopySeverityLabel(f.severity!)}',
    ].join(', ');

    // "Kotprobe · Flotation" — the preparation only qualifies a faecal sample.
    final header = [
      if (sample.sampleType case final t?) microscopySampleTypeLabel(l10n, t),
      if (sample.method case final m?) microscopyMethodLabel(l10n, m),
    ].join(' · ');

    // Who looked: the practice or lab by name where there is one, else the
    // plain statement of who did it.
    final lab = sample.externalLab ?? '';
    final by = switch (sample.examinedBy) {
      null => null,
      MicroscopyExaminedBy.inHouse => microscopyExaminedByLabel(
        l10n,
        MicroscopyExaminedBy.inHouse,
      ),
      final b => lab.isNotEmpty ? lab : microscopyExaminedByLabel(l10n, b),
    };

    final notes = sample.notes;

    return TimelineItem(
      icon: Icons.biotech_outlined,
      date: formatLocalDate(
        materialL10n,
        sample.examinedAt ?? sample.created,
        withTime: true,
      ),
      isLast: isLast,
      trailing: canEdit
          ? TimelineEntryMenu(
              editLabel: l10n.microscopyEditAction,
              onEdit: () => showMicroscopySheet(
                context,
                caseId: caseId,
                sample: sample,
                findings: findings,
              ),
              deleteLabel: l10n.microscopyDeleteAction,
              onDelete: () => _delete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header.isEmpty ? l10n.microscopyTitle : header,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          // The three states, kept apart: graded findings, a clean result, or
          // a sample nobody has read yet. Collapsing the last into "ohne
          // Befund" would assert a result no one has seen.
          if (graded.isNotEmpty)
            Text(
              findingText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              sample.noFindings
                  ? l10n.microscopyFieldNoFindings
                  : l10n.microscopyResultPending,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (by != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                by,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(notes, style: theme.textTheme.bodyMedium),
          ],
          if (sample.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _AttachmentStrip(sample: sample),
          ],
          // An OFFER, never a side effect: a positive finding is evidence, the
          // diagnosis is a human call, and the seeded conditions list already
          // holds "Trichomonadose".
          //
          // One per finding, because a sample carrying Trichomonaden AND
          // Spulwurmeier is two diagnoses, not one: a single button could only
          // ever pre-fill one of them, and which one it picked would be
          // arbitrary from the reader's side.
          if (canEdit)
            for (final f in graded)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.coronavirus_outlined, size: 18),
                  label: Text(
                    graded.length == 1
                        ? l10n.microscopyCreateDiagnosis
                        : l10n.microscopyCreateDiagnosisFor(
                            _nameOf(f, typesById),
                          ),
                  ),
                  onPressed: () => unawaited(
                    showConditionEntrySheet(
                      context,
                      caseId: caseId,
                      initialLabel: _nameOf(f, typesById),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// A finding names itself either through the vocabulary or in its own words.
  String _nameOf(
    MicroscopyFinding f,
    Map<String, MicroscopyFindingType> typesById,
  ) {
    final type = f.findingType;
    if (type != null && type.isNotEmpty) {
      return typesById[type]?.label ?? '';
    }
    return f.freeText ?? '';
  }
}

/// Thumbnails of a sample's attachments. A video gets an icon placeholder and
/// opens externally — see [openMicroscopyAttachment].
class _AttachmentStrip extends ConsumerWidget {
  const _AttachmentStrip({required this.sample});

  final MicroscopySample sample;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(microscopySamplesRepositoryProvider).value;
    if (repo == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sample.attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final filename = sample.attachments[i];
          final isVideo = isVideoAttachment(filename);
          return Semantics(
            button: true,
            label: context.l10n.photoViewLabel(
              i + 1,
              sample.attachments.length,
            ),
            child: GestureDetector(
              // Opaque, not deferToChild: the thumbnail only reports a hit
              // once it has decoded a frame, so a tap while loading would be
              // swallowed (federfall-ltfw).
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(
                openMicroscopyAttachment(
                  context,
                  ref,
                  sampleId: sample.id,
                  attachments: sample.attachments,
                  index: i,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                // Never a thumbnail request for a video: `?thumb=` on a
                // non-image serves the ORIGINAL, i.e. the whole clip.
                child: isVideo
                    ? const VideoAttachmentThumb(size: 96)
                    : CachedFileImage(
                        url: repo.fileUrl(
                          sample.id,
                          filename,
                          thumb: '200x200',
                        ),
                        width: 96,
                        height: 96,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

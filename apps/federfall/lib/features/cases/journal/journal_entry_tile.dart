import 'dart:async';

import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One journal entry as a chronology event (FED-4.7): a [TimelineItem] showing
/// the entry's date, free-text note, photo thumbnails and an edit/delete menu.
/// Dual-parent since federfall-d5co.2 — exactly one of [caseId] / [aviaryId]
/// is set, matching the entry's own parent.
class JournalEntryTile extends ConsumerWidget {
  const JournalEntryTile({
    required this.entry,
    this.caseId,
    this.aviaryId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  }) : assert(
         (caseId == null) != (aviaryId == null),
         'Exactly one of caseId / aviaryId must be set.',
       );

  final JournalEntry entry;
  final String? caseId;
  final String? aviaryId;
  final bool canEdit;
  final bool isLast;

  Future<void> _edit(BuildContext context) => showJournalEntrySheet(
    context,
    caseId: caseId,
    aviaryId: aviaryId,
    entry: entry,
  );

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.journalDeleteTitle,
      message: l10n.journalDeleteConfirm,
      confirmLabel: l10n.journalDeleteAction,
      action: () async {
        final repo = await ref.read(journalRepositoryProvider.future);
        await repo.delete(entry.id);
        final id = caseId;
        if (id != null) ref.invalidate(caseBundleProvider(id));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final date = entry.entryAt ?? entry.created;

    return TimelineItem(
      icon: Icons.sticky_note_2_outlined,
      date: formatEventDate(materialL10n, date, withTime: true),
      isLast: isLast,
      trailing: canEdit
          ? TimelineEntryMenu(
              editLabel: l10n.journalEditAction,
              onEdit: () => _edit(context),
              deleteLabel: l10n.journalDeleteAction,
              onDelete: () => _delete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.text, style: theme.textTheme.bodyLarge),
          if (entry.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _AttachmentStrip(entry: entry),
          ],
        ],
      ),
    );
  }
}

/// Thumbnails of an entry's photo attachments; tapping one opens it full-size.
class _AttachmentStrip extends ConsumerWidget {
  const _AttachmentStrip({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(journalRepositoryProvider).value;
    if (repo == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Attachments are a Protected file field (FED-8.1), but the access token is
    // appended at download time (ProtectedFileCacheManager), so the URLs here
    // stay token-free and cached thumbnails render without a token mint.
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entry.attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final filename = entry.attachments[i];
          final thumb = repo.fileUrl(entry.id, filename, thumb: '200x200');
          return Semantics(
            button: true,
            label: context.l10n.photoViewLabel(i + 1, entry.attachments.length),
            child: GestureDetector(
              onTap: () => unawaited(
                showImageViewer(
                  context,
                  imageUrls: [
                    for (final f in entry.attachments)
                      repo.fileUrl(entry.id, f).toString(),
                  ],
                  initialIndex: i,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedFileImage(url: thumb, width: 96, height: 96),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One journal entry as a chronology event (FED-4.7): a [TimelineItem] showing
/// the entry's date, free-text note, photo thumbnails and an edit/delete menu.
class JournalEntryTile extends ConsumerWidget {
  const JournalEntryTile({
    required this.entry,
    required this.caseId,
    this.isLast = false,
    super.key,
  });

  final JournalEntry entry;
  final String caseId;
  final bool isLast;

  Future<void> _edit(BuildContext context) =>
      showJournalEntrySheet(context, caseId: caseId, entry: entry);

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.journalDeleteTitle),
        content: Text(l10n.journalDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.journalDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = await ref.read(journalRepositoryProvider.future);
    await repo.delete(entry.id);
    ref.invalidate(journalForCaseProvider(caseId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final date = entry.entryAt ?? entry.created;

    return TimelineItem(
      icon: Icons.sticky_note_2_outlined,
      date: formatEventDate(materialL10n, date, withTime: true),
      isLast: isLast,
      trailing: _EntryMenu(
        onEdit: () => _edit(context),
        onDelete: () => _delete(context, ref),
      ),
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

/// Compact overflow menu on a journal entry: edit or delete.
class _EntryMenu extends StatelessWidget {
  const _EntryMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      iconSize: 20,
      padding: EdgeInsets.zero,
      tooltip: l10n.journalEditAction,
      itemBuilder: (context) => [
        PopupMenuItem(onTap: onEdit, child: Text(l10n.journalEditAction)),
        PopupMenuItem(onTap: onDelete, child: Text(l10n.journalDeleteAction)),
      ],
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
    // Attachments are a Protected file field (FED-8.1): URLs need a token.
    final token = ref.watch(fileTokenProvider).value;
    if (repo == null || token == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entry.attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final filename = entry.attachments[i];
          final thumb = repo.fileUrl(
            entry.id,
            filename,
            thumb: '200x200',
            token: token,
          );
          return GestureDetector(
            onTap: () => unawaited(
              showImageViewer(
                context,
                imageUrls: [
                  for (final f in entry.attachments)
                    repo.fileUrl(entry.id, f, token: token).toString(),
                ],
                initialIndex: i,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedFileImage(url: thumb, width: 96, height: 96),
            ),
          );
        },
      ),
    );
  }

}

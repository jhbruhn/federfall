import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Case-detail journal: a dated free-text log with photo attachments (FED-4.7).
/// Entries are newest-first; the add button opens the entry sheet.
class JournalSection extends ConsumerWidget {
  const JournalSection({required this.caseId, super.key});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final entries = ref.watch(journalForCaseProvider(caseId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.caseJournalTitle,
                  style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => showJournalEntrySheet(context, caseId: caseId),
              icon: const Icon(Icons.add),
              label: Text(l10n.journalAddAction),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        entries.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(
            errorMessage(l10n, e),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
          data: (list) => list.isEmpty
              ? Text(l10n.journalEmpty, style: theme.textTheme.bodyMedium)
              : Column(
                  children: [
                    for (final entry in list)
                      _JournalTile(entry: entry, caseId: caseId),
                  ],
                ),
        ),
      ],
    );
  }
}

class _JournalTile extends ConsumerWidget {
  const _JournalTile({required this.entry, required this.caseId});

  final JournalEntry entry;
  final String caseId;

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

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: date == null
                      ? const SizedBox.shrink()
                      : Text(
                          materialL10n.formatMediumDate(date),
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                ),
                _EntryMenu(
                  onEdit: () => _edit(context),
                  onDelete: () => _delete(context, ref),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(entry.text, style: theme.textTheme.bodyLarge),
            if (entry.attachments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _AttachmentStrip(entry: entry),
            ],
          ],
        ),
      ),
    );
  }
}

/// Overflow menu on a journal entry: edit or delete.
class _EntryMenu extends StatelessWidget {
  const _EntryMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: onEdit,
          child: Text(l10n.journalEditAction),
        ),
        PopupMenuItem(
          onTap: onDelete,
          child: Text(l10n.journalDeleteAction),
        ),
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
    if (repo == null) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entry.attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final filename = entry.attachments[i];
          final thumb = repo.fileUrl(entry.id, filename, thumb: '200x200');
          final full = repo.fileUrl(entry.id, filename);
          return GestureDetector(
            onTap: () => _openFull(context, full),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                thumb.toString(),
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 96,
                  height: 96,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openFull(BuildContext context, Uri url) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(
            child: Image.network(url.toString(), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

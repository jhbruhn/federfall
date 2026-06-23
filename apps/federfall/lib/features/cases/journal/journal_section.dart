import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/journal/new_journal_entry_sheet.dart';
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
              onPressed: () =>
                  showNewJournalEntrySheet(context, caseId: caseId),
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
                  children: [for (final entry in list) _JournalTile(entry)],
                ),
        ),
      ],
    );
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile(this.entry);

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
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
            if (date != null)
              Text(
                materialL10n.formatMediumDate(date),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
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

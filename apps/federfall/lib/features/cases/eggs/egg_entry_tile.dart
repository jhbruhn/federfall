import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/eggs/egg_entry_sheet.dart';
import 'package:federfall/features/cases/eggs/egg_reassign_sheet.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One egg-laying event as a chronology event (federfall-4agw): how many eggs,
/// their fertility and outcome, a "presumed" badge when the layer is only
/// guessed, any photos, and an edit/delete menu.
///
/// No "attributed to X" line is needed on a case timeline: an egg shown there
/// belongs to that case's animal by construction. [caseId] is only the timeline
/// to refresh after a write — it is never stored on the record.
class EggEntryTile extends ConsumerWidget {
  const EggEntryTile({
    required this.egg,
    this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final EggRecord egg;

  /// The case timeline this tile sits on, if any — the animal detail shows the
  /// same tile with no case in play.
  final String? caseId;
  final bool canEdit;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final notes = egg.notes;

    final detail = [
      if (egg.fertility case final f? when f != EggFertility.unknown)
        eggFertilityLabel(l10n, f),
      if (egg.fate case final f? when f != EggFate.unknown)
        eggFateLabel(l10n, f),
    ].join(' · ');

    return TimelineItem(
      icon: Icons.egg_outlined,
      date: formatEventDate(materialL10n, egg.laidAt ?? egg.created),
      isLast: isLast,
      trailing: canEdit ? EggEntryMenu(egg: egg, caseId: caseId) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  detail.isEmpty
                      ? l10n.eggCountLabel(egg.count)
                      : '${l10n.eggCountLabel(egg.count)} · $detail',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (egg.attribution == EggAttribution.presumed) ...[
                const SizedBox(width: AppSpacing.sm),
                TagChip(label: l10n.eggPresumedChip),
              ],
            ],
          ),
          if (notes != null && notes.isNotEmpty)
            Text(notes, style: theme.textTheme.bodyMedium),
          if (egg.photos.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            EggPhotoStrip(egg: egg),
          ],
        ],
      ),
    );
  }
}

/// The overflow menu shared by the case-timeline tile and the animal detail's
/// egg rows: edit, confirm a presumed layer, re-attribute, delete.
///
/// Delete only appears for the record's author or a supervisor, mirroring the
/// server rule (1700000056).
class EggEntryMenu extends ConsumerWidget {
  const EggEntryMenu({required this.egg, this.caseId, super.key});

  final EggRecord egg;

  /// The case timeline this menu was opened from, if any — invalidated after a
  /// write so the timeline reflects it. Never stored on the record.
  final String? caseId;

  void _invalidate(WidgetRef ref) {
    ref.invalidate(eggsForAnimalProvider(egg.animal));
    if (caseId case final id?) ref.invalidate(caseBundleProvider(id));
  }

  /// Promotes a presumed record to confirmed — the one-field version of a
  /// re-attribution, for when the recorded layer turns out to be right.
  Future<void> _confirm(BuildContext context, WidgetRef ref) {
    return runQuickAction(context, () async {
      final repo = await ref.read(eggRecordsRepositoryProvider.future);
      await repo.update(egg.id, {
        'attribution': EggAttribution.confirmed.wire,
      });
      _invalidate(ref);
    });
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.eggDeleteTitle,
      message: l10n.eggDeleteConfirm,
      confirmLabel: l10n.eggDeleteAction,
      action: () async {
        final repo = await ref.read(eggRecordsRepositoryProvider.future);
        await repo.delete(egg.id);
        _invalidate(ref);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final me = ref.watch(currentUserProvider).value;

    return TimelineEntryMenu(
      editLabel: l10n.eggEditAction,
      onEdit: () => unawaited(
        showEggEntrySheet(context, animalId: egg.animal, egg: egg),
      ),
      middleActions: [
        if (egg.attribution == EggAttribution.presumed)
          MenuAction(
            icon: Icons.verified_outlined,
            label: l10n.eggConfirmAction,
            onTap: () => _confirm(context, ref),
          ),
        MenuAction(
          icon: Icons.swap_horiz_outlined,
          label: l10n.eggReassignAction,
          onTap: () => unawaited(
            showEggReassignSheet(context, egg: egg, caseId: caseId),
          ),
        ),
      ],
      deleteLabel: l10n.eggDeleteAction,
      onDelete: eggDeletableBy(egg, me) ? () => _delete(context, ref) : null,
    );
  }
}

/// Thumbnails of an egg record's photos; tapping one opens it full-size.
class EggPhotoStrip extends ConsumerWidget {
  const EggPhotoStrip({required this.egg, super.key});

  final EggRecord egg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(eggRecordsRepositoryProvider).value;
    if (repo == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // `photos` is a Protected file field (1700000056), but the access token is
    // appended at download time (ProtectedFileCacheManager), so the URLs here
    // stay token-free and cached thumbnails render without minting one.
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: egg.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => Semantics(
          button: true,
          label: context.l10n.photoViewLabel(i + 1, egg.photos.length),
          child: GestureDetector(
            onTap: () => unawaited(
              showImageViewer(
                context,
                imageUrls: [
                  for (final f in egg.photos)
                    repo.fileUrl(egg.id, f).toString(),
                ],
                initialIndex: i,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedFileImage(
                url: repo.fileUrl(egg.id, egg.photos[i], thumb: '200x200'),
                width: 96,
                height: 96,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

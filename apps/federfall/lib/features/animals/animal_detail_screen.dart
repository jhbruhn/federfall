import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/animals/delete_record_dialogs.dart';
import 'package:federfall/features/animals/edit_animal_sheet.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/sponsorship_detail_sheet.dart';
import 'package:federfall/features/aviaries/sponsorship_providers.dart';
import 'package:federfall/features/aviaries/sponsorship_sheet.dart';
import 'package:federfall/features/cases/case_summary_tile.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/eggs/egg_clutch_list.dart';
import 'package:federfall/features/cases/eggs/egg_entry_sheet.dart';
import 'package:federfall/features/cases/eggs/egg_month_chart.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/marking_sheet.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/weights/weight_entry_sheet.dart';
import 'package:federfall/features/cases/weights/weight_trend_chart.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Animal lifetime detail (FED-7.6): one animal's full record — identity,
/// markings (active + historic) and every case newest-first. Cases the user
/// cannot open render as a non-tappable stub (number / status / dates only).
///
/// Every write control here is gated on CUSTODY (`canWriteAnimal`, the mirror
/// of 1700000077/79) rather than on a role: the record is org-wide readable, but
/// writing about a bird requires holding it. A viewer who does not gets the
/// read-only badge in the header instead of controls that would 403.
///
/// State-restoration note (federfall-7ev8): the route's restoration id is
/// pattern-scoped (`/animals/:id`), not per-[animalId]. If this screen ever
/// adds a `RestorationMixin`, fold [animalId] into its restoration id so state
/// doesn't bleed across different animals.
class AnimalDetailScreen extends ConsumerWidget {
  const AnimalDetailScreen({required this.animalId, super.key});

  final String animalId;

  /// Deletes the animal this screen is showing and leaves for the registry —
  /// the subject is gone, so staying on a detail view of it makes no sense.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Animal? animal,
  ) async {
    if (animal == null) return;
    final deleted = await confirmDeleteAnimal(context, ref, animal);
    if (deleted && context.mounted) context.go(AppRoutes.animals);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    ref.liveRefresh(
      const [
        'animals',
        'cases',
        // A case shared with the signed-in user joins this animal's history
        // without changing the case record itself — only case_shares fires.
        'case_shares',
        // Reassigning an enclosure's keeper moves custody of every resident at
        // once, and nothing about the animal changes when it does.
        'aviaries',
        'markings',
        'weights',
        'egg_records',
        'exams',
        'exam_findings',
        // Only the keeper of the bird's enclosure and coord/sup are subscribed
        // to these at all — the rule scopes the realtime stream the same way it
        // scopes a list.
        'sponsorships',
      ],
      () {
        // Invalidate the leaf list providers, not just animalLifetime:
        // animalLifetime watches these via .future, so invalidating it alone
        // would re-read their still-cached values. Touching the leaves cascades
        // up to animalLifetime, refreshing the case history + accessibility.
        //
        // Custody has leaves of its own for the same reason: its enclosure and
        // its share branch, neither of which is reachable from this animal's
        // record. The enclosure is invalidated by id — invalidating custody
        // alone would re-read the cached aviary and learn nothing.
        final aviaryId = ref
            .read(animalByIdProvider(animalId))
            .value
            ?.currentAviary;
        ref
          ..invalidate(animalByIdProvider(animalId))
          ..invalidate(myEditSharedCaseIdsProvider)
          ..invalidate(casesForAnimalProvider(animalId))
          ..invalidate(caseSummariesForAnimalProvider(animalId))
          ..invalidate(markingsForAnimalProvider(animalId))
          ..invalidate(weightsForAnimalProvider(animalId))
          ..invalidate(eggsForAnimalProvider(animalId))
          ..invalidate(examsForAnimalProvider(animalId))
          // The access predicate reads the enclosure, so a keeper change has to
          // re-resolve it — invalidating the list alone would keep showing (or
          // keep hiding) the section on a stale answer.
          ..invalidate(sponsorshipAccessProvider(animalId))
          ..invalidate(sponsorshipsForAnimalProvider(animalId))
          ..invalidate(sponsorshipCountForAnimalProvider(animalId));
        if (aviaryId != null && aviaryId.isNotEmpty) {
          ref.invalidate(aviaryByIdProvider(aviaryId));
        }
      },
    );
    final lifetime = ref.watch(animalLifetimeProvider(animalId));
    final role = ref.watch(currentUserProvider).value?.role;
    // One source of truth for every write control on this screen, exactly as
    // `canEditCase` is on the case detail.
    final canWrite = ref.watch(canWriteAnimalProvider(animalId)).value ?? false;

    return Scaffold(
      appBar: AppBar(
        // No up arrow in the two-pane right pane (see case detail).
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.animalDetailTitle),
        actions: [
          if (lifetime.value case final data? when canWrite)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.animalEditTitle,
              onPressed: () => showEditAnimalSheet(context, data.animal),
            ),
          // Merge used to be a direct icon, on the reasoning that a one-item
          // overflow is just chrome around a single action. Delete makes two
          // supervisor actions, which flips that — and keeps an irreversible
          // one out of thumb's reach of the edit icon.
          if (canDeleteRecords(role))
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => buildMenuItems([
                MenuAction(
                  icon: Icons.merge_outlined,
                  label: l10n.animalMergeAction,
                  onTap: () => context.push(AppRoutes.mergeAnimal(animalId)),
                ),
                MenuAction(
                  icon: Icons.delete_outline,
                  label: l10n.animalDeleteAction,
                  onTap: () => _delete(context, ref, lifetime.value?.animal),
                  // Cascades to every case and its whole timeline.
                  destructive: true,
                ),
              ]),
            ),
        ],
      ),
      body: AsyncValueView<AnimalLifetime>(
        value: lifetime,
        onRetry: () => ref.invalidate(animalLifetimeProvider(animalId)),
        // Top progress bar rather than a centred spinner, so the header doesn't
        // appear to jump from centre to its final top-left position on load.
        loading: const LinearProgressIndicator(),
        data: (data) => ContentBounds(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _Identity(data.animal, canWrite: canWrite),
              const SizedBox(height: AppSpacing.md),
              _WeightSection(animalId: data.animal.id, canWrite: canWrite),
              const SizedBox(height: AppSpacing.md),
              _EggSection(animalId: data.animal.id, canWrite: canWrite),
              const SizedBox(height: AppSpacing.md),
              _ExamsSection(animalId: data.animal.id),
              const SizedBox(height: AppSpacing.md),
              _MarkingsSection(
                animalId: data.animal.id,
                markings: data.markings,
                canWrite: canWrite,
              ),
              const SizedBox(height: AppSpacing.md),
              // Renders NOTHING at all unless the viewer is the current
              // enclosure's keeper or a coordinator/supervisor — not an empty
              // card. See _SponsorshipSection.
              _SponsorshipSection(animalId: data.animal.id),
              _CasesSection(
                animalId: data.animal.id,
                cases: data.cases,
                accessibleIds: data.accessibleCaseIds,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name-first identity header — the exact same shared [DetailHeader] (avatar +
/// name + species/sex + lifetime-status chip) the case detail screen uses, so
/// the two headers look identical.
class _Identity extends StatelessWidget {
  const _Identity(this.animal, {required this.canWrite});

  final Animal animal;

  /// Whether the viewer holds this bird. False turns the avatar's photo edit
  /// off and adds the read-only badge, the same way the case header explains
  /// its own missing controls rather than leaving their absence a mystery.
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = animal.name;
    final hasName = name != null && name.isNotEmpty;
    final sub = [
      if (hasName) animal.species,
      if (animal.sex != null) sexLabel(l10n, animal.sex!),
    ].join(' · ');
    final status = animal.lifetimeStatus;

    return DetailHeader(
      title: hasName ? name : animal.species,
      subtitle: sub,
      chipLabel: status == null ? null : lifetimeStatusLabel(l10n, status),
      leading: AnimalAvatar(animalId: animal.id, editable: canWrite),
      trailing: canWrite
          ? null
          : Tooltip(
              message: l10n.animalReadOnlyTooltip,
              child: Chip(
                avatar: const Icon(Icons.lock_outline, size: 16),
                label: Text(l10n.animalReadOnly),
                visualDensity: VisualDensity.compact,
              ),
            ),
    );
  }
}

/// Life-long weight: the latest reading, a record action (no case needed), and
/// the whole-life trend (5yg.5).
class _WeightSection extends ConsumerWidget {
  const _WeightSection({required this.animalId, required this.canWrite});

  final String animalId;

  /// A weight is animal-scoped and follows custody since 1700000079.
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final weights = ref.watch(weightsForAnimalProvider(animalId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.animalSectionWeight,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (canWrite)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l10n.timelineAddWeight,
                    onPressed: () =>
                        showWeightEntrySheet(context, animalId: animalId),
                  ),
              ],
            ),
            // A load failure must not render as "no weight recorded" — route
            // through the standard error state with a retry (federfall-5cle).
            AsyncValueView<List<Weight>>(
              value: weights,
              onRetry: () => ref.invalidate(weightsForAnimalProvider(animalId)),
              loading: const LinearProgressIndicator(),
              data: (weights) {
                // weightsForAnimal is sorted oldest-first, so the last is the
                // latest.
                final latest = weights.isEmpty ? null : weights.last;
                if (latest == null) {
                  return Text(
                    l10n.animalNoWeight,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.monitor_weight_outlined),
                      title: Text(formatWeightG(l10n, latest.weightG)),
                      subtitle: switch (latest.measuredAt ?? latest.created) {
                        final at? => Text(formatLocalDate(materialL10n, at)),
                        _ => null,
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    WeightTrendChart.forAnimal(animalId),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Life-long egg laying (federfall-4agw): the totals, the most recent clutches
/// and a per-month chart. Available with or without an open case — chronic
/// laying is the input to calcium-depletion / egg-binding risk, and the history
/// belongs to the bird as it moves between carers and aviaries.
class _EggSection extends ConsumerWidget {
  const _EggSection({required this.animalId, required this.canWrite});

  final String animalId;

  /// An egg record is animal-scoped and follows custody since 1700000079. The
  /// per-record menu gates itself (see `EggEntryMenu`), so this is only the
  /// card's own "log eggs" action.
  final bool canWrite;

  /// How many clutches the card lists before it stops; the rest stay in the
  /// counts and the chart.
  static const int _recentClutches = 3;

  /// Hard cap on the record rows the card renders. A clutch is derived
  /// (anything within [kClutchGapDays] of the previous egg joins it), so a hen
  /// laying every few days for weeks would otherwise grow one clutch — and this
  /// card — without bound. Three normal two-egg clutches still fit.
  static const int _maxRows = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final eggs = ref.watch(eggsForAnimalProvider(animalId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.animalSectionEggs,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                // Only when the card's caps actually hide something —
                // otherwise the sheet would just repeat what is already here.
                if (eggs.value case final all? when all.length > _maxRows)
                  TextButton(
                    onPressed: () =>
                        showEggHistorySheet(context, animalId: animalId),
                    child: Text(l10n.eggShowAllAction(all.length)),
                  ),
                if (canWrite)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l10n.timelineAddEgg,
                    onPressed: () =>
                        showEggEntrySheet(context, animalId: animalId),
                  ),
              ],
            ),
            // A load failure must not render as "no eggs" — route through the
            // standard error state with a retry (federfall-5cle).
            AsyncValueView<List<EggRecord>>(
              value: eggs,
              onRetry: () => ref.invalidate(eggsForAnimalProvider(animalId)),
              loading: const LinearProgressIndicator(),
              data: (eggs) {
                final summary = EggLayingSummary.from(eggs);
                if (summary.isEmpty) {
                  return Text(
                    l10n.animalNoEggs,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.animalEggsSummary(
                        summary.eggsLast12Months,
                        summary.totalEggs,
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    // Guesses stay visible as guesses rather than hardening
                    // into the totals above them unremarked.
                    if (summary.presumedEggs > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      TagChip(
                        label: l10n.animalEggsPresumed(summary.presumedEggs),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    EggClutchList(
                      eggs: eggs,
                      maxClutches: _recentClutches,
                      maxRows: _maxRows,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    EggMonthChart(eggs: eggs),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Life-long exams: every structured exam across the animal's cases, newest
/// first, each tapping through to the case it belongs to (blp.5). Read-only
/// roll-up — exams are created/edited on the case timeline.
class _ExamsSection extends ConsumerWidget {
  const _ExamsSection({required this.animalId});

  final String animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final exams = ref.watch(examsForAnimalProvider(animalId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.animalSectionExams, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            // A load failure must not render as "no exams" — route through the
            // standard error state with a retry (federfall-5cle).
            AsyncValueView<List<Exam>>(
              value: exams,
              onRetry: () => ref.invalidate(examsForAnimalProvider(animalId)),
              loading: const LinearProgressIndicator(),
              data: (exams) {
                if (exams.isEmpty) {
                  return Text(
                    l10n.animalNoExams,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final exam in exams)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.monitor_heart_outlined),
                        title: Text(
                          switch (exam.examinedAt ?? exam.created) {
                            final at? => formatLocalDate(materialL10n, at),
                            _ => l10n.examTitle,
                          },
                        ),
                        subtitle: Text(_vitalsSummary(l10n, exam)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.go(AppRoutes.caseDetail(exam.caseId)),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _vitalsSummary(AppLocalizations l10n, Exam e) {
    final parts = <String>[
      if (e.bodyCondition case final bc?) l10n.examBodyConditionShort(bc),
      if (e.hydration case final h?) hydrationLabel(l10n, h),
      if (e.mentation case final m?) mentationLabel(l10n, m),
      if (e.temperature case final t?) '$t °C',
    ];
    return parts.isEmpty ? l10n.examNoVitals : parts.join(' · ');
  }
}

class _MarkingsSection extends ConsumerWidget {
  const _MarkingsSection({
    required this.animalId,
    required this.markings,
    required this.canWrite,
  });

  final String animalId;
  final List<Marking> markings;

  /// A marking is animal-scoped and follows custody since 1700000079 — applying
  /// a ring to a bird you do not hold is somebody else's business.
  final bool canWrite;

  Future<void> _remove(BuildContext context, WidgetRef ref, Marking m) =>
      runQuickAction(context, () async {
        final repo = await ref.read(markingsRepositoryProvider.future);
        await repo.update(m.id, {
          'is_active': false,
          'removed_at': DateTime.now().toUtc().toIso8601String(),
        });
        ref.invalidate(markingsForAnimalProvider(animalId));
      });

  Future<void> _delete(BuildContext context, WidgetRef ref, Marking m) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.markingDeleteAction),
        content: Text(l10n.markingDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          DestructiveActionButton(
            label: l10n.markingDeleteAction,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runQuickAction(context, () async {
      final repo = await ref.read(markingsRepositoryProvider.future);
      await repo.delete(m.id);
      ref.invalidate(markingsForAnimalProvider(animalId));
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final typesById = ref.watch(markingTypesByIdProvider).value ?? const {};
    // `markings.delete` is supervisor-only (1700000010) and 1700000079 left it
    // exactly as it was, so custody alone is not enough to offer it.
    final role = ref.watch(currentUserProvider).value?.role;
    final canDelete = canWrite && canDeleteRecords(role);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.animalSectionMarkings,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (canWrite)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l10n.markingNewTitle,
                    onPressed: () =>
                        showMarkingSheet(context, animalId: animalId),
                  ),
              ],
            ),
            if (markings.isEmpty)
              Text(
                l10n.animalNoMarkings,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final m in markings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.sell_outlined,
                    color: m.isActive ? null : theme.colorScheme.outline,
                  ),
                  title: Row(
                    children: [
                      Flexible(child: Text(_markingTitle(typesById, m))),
                      // Same badge the case timeline shows: the bird arrived
                      // wearing this one.
                      if (m.presentAtFind) ...[
                        const SizedBox(width: AppSpacing.sm),
                        TagChip(label: l10n.markingPresentAtFind),
                      ],
                    ],
                  ),
                  subtitle: m.isActive
                      ? null
                      : Text(
                          m.removedAt == null
                              ? l10n.markingRemoved
                              : l10n.markingRemovedOn(
                                  formatLocalDate(materialL10n, m.removedAt),
                                ),
                        ),
                  trailing: canWrite
                      ? PopupMenuButton<void>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: l10n.markingMenuTooltip,
                          itemBuilder: (_) => buildMenuItems([
                            MenuAction(
                              icon: Icons.edit_outlined,
                              label: l10n.markingEditAction,
                              onTap: () => showMarkingSheet(
                                context,
                                animalId: animalId,
                                marking: m,
                              ),
                            ),
                            // Recording that the ring came off — the record
                            // stays.
                            if (m.isActive)
                              MenuAction(
                                icon: Icons.remove_circle_outline,
                                label: l10n.markingRemoveAction,
                                onTap: () => _remove(context, ref, m),
                              ),
                            if (canDelete)
                              MenuAction(
                                icon: Icons.delete_outline,
                                label: l10n.markingDeleteAction,
                                onTap: () => _delete(context, ref, m),
                                destructive: true,
                              ),
                          ]),
                        )
                      : null,
                ),
          ],
        ),
      ),
    );
  }

  String _markingTitle(Map<String, MarkingType> typesById, Marking m) {
    final code = m.code;
    final label = typesById[m.type]?.label ?? '';
    return code != null && code.isNotEmpty ? '$label · $code' : label;
  }
}

/// Patenschaften on this bird (federfall-5s5j) — the sponsor, what they give,
/// and for how long.
///
/// **Absent, not empty, for anyone who may not read them.** The section returns
/// a zero-size box unless the viewer keeps the enclosure the bird lives in (or
/// is a coordinator/supervisor): an always-present „Patenschaften" card would
/// tell the whole org that this bird has a sponsor, which is a leak with no
/// values in it. The server would return an empty list to them anyway — this is
/// about not asking the question out loud.
///
/// It follows the bird by itself. Access resolves through the CURRENT
/// enclosure, so a move hands the whole section to the new keeper and takes it
/// from the old one, with nothing on the row to re-point.
class _SponsorshipSection extends ConsumerWidget {
  const _SponsorshipSection({required this.animalId});

  final String animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value ?? none` — an unresolved or failed access state shows nothing
    // rather than briefly showing PII to whoever is looking.
    final access =
        ref.watch(sponsorshipAccessProvider(animalId)).value ??
        SponsorshipAccess.none;
    if (!access.canRead) return const SizedBox.shrink();
    final sponsorships = ref.watch(sponsorshipsForAnimalProvider(animalId));

    // This is the only OPTIONAL card in a fixed list of siblings separated by
    // explicit AppSpacing.md gaps, so it owns the gap BELOW it rather than
    // having one sit in the list: a standalone SizedBox there would double up
    // for a viewer this section renders nothing for.
    return Column(
      children: [
        _card(context, ref, sponsorships, access),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Sponsorship>> sponsorships,
    SponsorshipAccess access,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.animalSectionSponsorships,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                // canWrite is narrower than canRead by exactly one clause: a
                // coordinator still READS the patronages of a bird that has
                // left aviary care (that is who winds them down), but nobody
                // may record a new one there.
                if (access.canWrite)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l10n.sponsorshipNewTitle,
                    onPressed: () =>
                        showSponsorshipSheet(context, animalId: animalId),
                  ),
              ],
            ),
            AsyncValueView<List<Sponsorship>>(
              value: sponsorships,
              onRetry: () =>
                  ref.invalidate(sponsorshipsForAnimalProvider(animalId)),
              loading: const LinearProgressIndicator(),
              data: (rows) {
                if (rows.isEmpty) {
                  return Text(
                    l10n.animalNoSponsorships,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.volunteer_activism_outlined,
                          color: s.isActive ? null : theme.colorScheme.outline,
                        ),
                        title: Text(s.sponsorName),
                        subtitle: Text(
                          _subtitle(l10n, materialL10n, s),
                        ),
                        // The row is a summary; the address, the mobile and
                        // the notes live in the detail sheet. Tapping opens
                        // THAT and not the form, because reading is the common
                        // act and a reader who may not write still needs it.
                        onTap: () => showSponsorshipDetailSheet(
                          context,
                          animalId: animalId,
                          sponsorship: s,
                        ),
                        trailing: access.canWrite
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: l10n.sponsorshipEditTitle,
                                onPressed: () => showSponsorshipSheet(
                                  context,
                                  animalId: animalId,
                                  sponsorship: s,
                                ),
                              )
                            : null,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// „12,50 € monatlich · seit 4. Aug. 2026" — whichever of the three parts the
  /// row carries. Dates go through [formatLocalDate], the only thing in `lib/`
  /// allowed to turn a DateTime into a date string.
  String _subtitle(
    AppLocalizations l10n,
    MaterialLocalizations materialL10n,
    Sponsorship s,
  ) {
    final amount = switch (s.amountCents) {
      final cents? => formatAmountCents(l10n, cents),
      _ => null,
    };
    final interval = switch (s.interval) {
      final i? => sponsorshipIntervalLabel(l10n, i),
      _ => null,
    };
    String short(DateTime at) =>
        formatLocalDate(materialL10n, at, style: DateStyle.short);
    final period = switch ((s.startedAt, s.endedAt)) {
      (final from?, final to?) => '${short(from)} – ${short(to)}',
      (final from?, null) => l10n.sponsorshipSince(short(from)),
      (null, final to?) => l10n.sponsorshipUntil(short(to)),
      _ => null,
    };
    final money = [?amount, ?interval].join(' ');
    return [
      if (money.isNotEmpty) money,
      ?period,
    ].join(' · ');
  }
}

class _CasesSection extends ConsumerWidget {
  const _CasesSection({
    required this.animalId,
    required this.cases,
    required this.accessibleIds,
  });

  final String animalId;
  final List<CaseSummary> cases;
  final Set<String> accessibleIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Admissibility, not write custody: a bird nobody holds is anyone's to
    // admit, while one in another carer's care is not — mirrors
    // `lib_custody.js`'s requireAdmissible(), which is what
    // `POST /api/federfall/intake` actually enforces.
    final canOpenCase =
        ref.watch(canOpenCaseOnAnimalProvider(animalId)).value ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.animalSectionCases,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (canOpenCase)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l10n.animalNewCase,
                    onPressed: () => context.push(
                      AppRoutes.newCaseForAnimal(animalId),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (cases.isEmpty)
              Text(
                l10n.animalNoCases,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final c in cases)
                CaseSummaryTile(
                  summary: c,
                  accessible: accessibleIds.contains(c.id),
                ),
          ],
        ),
      ),
    );
  }
}

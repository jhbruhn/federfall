import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/animals/add_animal_sheet.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/vaccinations/batch_vaccination_sheet.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/aviary_flock_providers.dart';
import 'package:federfall/features/aviaries/aviary_flock_timeline.dart';
import 'package:federfall/features/aviaries/aviary_form_sheet.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart' show LiveRefresh;

/// Aviary detail (FED-6.2 + federfall-d5co.3): the aviary's identity over two
/// tabs — **Bestand** (occupancy: current residents) and **Pflege** (the
/// flock-care chronology: aviary journal entries + a health rollup).
/// Coordinators/supervisors can edit the aviary; placing a bird into it is the
/// KEEPER's call as well as theirs, which is what `animals.createRule` says
/// since 1700000077 (federfall-q7ks.6) and what the FAB was refusing while the
/// server allowed it.
///
/// **Pflege is not for the whole org** (1700000089): the flock log is the
/// enclosure's own care record, so the tab is absent — not empty — for anyone
/// but its keeper and the coordinators/supervisors, and its keeper writes it.
/// What 1700000089 actually enforces is the JOURNAL half; the condition rollup
/// beside it is built on the device from collections that stay org-wide, so
/// hiding the tab does not put that half out of reach of the API — see
/// [aviaryFlockCareVisibleBy]. Bestand stays org-wide too, as animal reads
/// deliberately are: re-identifying a returning bird depends on them.
///
/// State-restoration note (federfall-7ev8): the route's restoration id is
/// pattern-scoped (`/aviaries/:id`), not per-[aviaryId]. If this screen ever
/// adds a `RestorationMixin`, fold [aviaryId] into its restoration id so state
/// doesn't bleed across different aviaries.
class AviaryDetailScreen extends ConsumerWidget {
  const AviaryDetailScreen({required this.aviaryId, super.key});

  final String aviaryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Same live-sync sources as the registry list, plus the flock-care
    // sources (a journal edit, a new diagnosis on a resident's case, or a
    // residency change all affect the Pflege tab).
    ref.liveRefresh(
      const [
        'aviaries',
        'dispositions',
        'animals',
        'journal_entries',
        'case_conditions',
        'aviary_stays',
      ],
      () => ref
        ..invalidate(aviaryByIdProvider(aviaryId))
        ..invalidate(aviaryResidentsProvider(aviaryId))
        ..invalidate(aviaryJournalProvider(aviaryId))
        ..invalidate(aviaryHealthRollupProvider(aviaryId)),
    );
    final aviary = ref.watch(aviaryByIdProvider(aviaryId));
    final me = ref.watch(currentUserProvider).value;
    // Every capability here needs the loaded record to say so: the enclosure's
    // own keeper may correct it (1700000086) and reads its log (1700000089).
    // Absent while it is still loading rather than shown-then-withdrawn.
    final editable = aviary.value;

    return Scaffold(
      appBar: AppBar(
        // No up arrow in the two-pane right pane (see case detail).
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.aviaryDetailTitle),
        actions: [
          if (editable != null && aviaryEditableBy(editable, me))
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.aviaryEditTitle,
              onPressed: () =>
                  unawaited(showAviaryFormSheet(context, aviary: editable)),
            ),
        ],
      ),
      body: AsyncValueView<Aviary>(
        value: aviary,
        onRetry: () => ref.invalidate(aviaryByIdProvider(aviaryId)),
        loading: const LinearProgressIndicator(),
        data: (av) => _AviaryDetail(aviaryId: aviaryId, aviary: av, me: me),
      ),
    );
  }
}

class _AviaryDetail extends StatelessWidget {
  const _AviaryDetail({
    required this.aviaryId,
    required this.aviary,
    required this.me,
  });

  final String aviaryId;
  final Aviary aviary;
  final AppUser? me;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bestand = _BestandTab(aviaryId: aviaryId, aviary: aviary);
    // Not a reader: the screen is Bestand alone — no tab bar, no second column
    // and no request for a journal the server would answer with nothing.
    if (!aviaryFlockCareVisibleBy(aviary, me)) return bestand;
    final pflege = _PflegeTab(
      aviaryId: aviaryId,
      canEdit: aviaryJournalWritableBy(aviary, me),
    );

    // Wide detail panes show Bestand and Pflege side-by-side; narrow ones
    // keep them behind tabs — same pane-width-keyed split as case detail.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kCaseDetailTwoColumnMin) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: bestand),
              const VerticalDivider(width: 1),
              Expanded(child: pflege),
            ],
          );
        }
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: l10n.aviaryTabBestand),
                  Tab(text: l10n.aviaryTabPflege),
                ],
              ),
              Expanded(child: TabBarView(children: [bestand, pflege])),
            ],
          ),
        );
      },
    );
  }
}

/// Bestand: the aviary's identity header plus its current residents, with the
/// "add resident" FAB (the pre-existing single-scroll body).
class _BestandTab extends ConsumerWidget {
  const _BestandTab({required this.aviaryId, required this.aviary});

  final String aviaryId;
  final Aviary aviary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final residents = ref.watch(aviaryResidentsProvider(aviaryId));
    // Wider than the managing roles on purpose: the enclosure's keeper holds
    // every bird in it, so putting one there is theirs to do.
    final canAddResident = aviaryStockableBy(
      aviary,
      ref.watch(currentUserProvider).value,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canAddResident
          ? FloatingActionButton.extended(
              onPressed: () => showAddAnimalSheet(context, aviaryId: aviaryId),
              icon: const Icon(Icons.add),
              label: Text(l10n.aviaryAddResident),
            )
          : null,
      body: ContentBounds(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Header(aviary: aviary, residentCount: residents.value?.length),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.aviaryResidentsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                // Vaccinating a flock is one act (federfall-s63u), so it is one
                // control here rather than N visits to N animal screens. Gated
                // on the same predicate as "add resident": the keeper holds
                // every bird in their enclosure.
                if (canAddResident && (residents.value?.isNotEmpty ?? false))
                  TextButton.icon(
                    onPressed: () => unawaited(
                      showBatchVaccinationSheet(context, aviaryId: aviaryId),
                    ),
                    icon: const Icon(Icons.vaccines_outlined),
                    label: Text(l10n.vaccinationBatchAction),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // A load failure must not render as "no residents" — route
            // through the standard error state with a retry (federfall-5cle).
            AsyncValueView<List<Animal>>(
              value: residents,
              onRetry: () => ref.invalidate(aviaryResidentsProvider(aviaryId)),
              loading: const LinearProgressIndicator(),
              data: (residents) => residents.isEmpty
                  ? EmptyView(
                      icon: Icons.pets_outlined,
                      message: l10n.aviaryNoResidents,
                    )
                  : Column(
                      children: [
                        for (final animal in residents) _ResidentTile(animal),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pflege: the flock-care chronology, with the "add journal entry" FAB.
class _PflegeTab extends StatelessWidget {
  const _PflegeTab({required this.aviaryId, required this.canEdit});

  final String aviaryId;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () =>
                  showJournalEntrySheet(context, aviaryId: aviaryId),
              icon: const Icon(Icons.add),
              label: Text(l10n.timelineAddEntry),
            )
          : null,
      body: AviaryFlockTimeline(
        aviaryId: aviaryId,
        canEdit: canEdit,
        padding: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.aviary, required this.residentCount});

  final Aviary aviary;

  /// Null while the residents are still loading (or failed to load) — the
  /// occupancy chip is omitted rather than asserting a wrong count of 0.
  final int? residentCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // As in the registry: an empty keeper predates 1700000076 and just misses.
    final keeper = ref.watch(orgMembersByIdProvider).value?[aviary.keeper];
    final subtitle = [
      if (keeper != null) memberLabel(keeper),
      ?aviary.location,
    ].join(' · ');
    final capacity = aviary.capacity;
    final count = residentCount;
    final occupancy = count == null
        ? null
        : capacity != null
        ? l10n.aviaryOccupancyOfCapacity(count, capacity)
        : l10n.aviaryOccupancy(count);

    return DetailHeader(
      title: aviary.name,
      subtitle: subtitle,
      chipLabel: occupancy,
      // Flag over-capacity so a coordinator spots it (federfall-kml).
      chipAlert: capacity != null && count != null && count > capacity,
    );
  }
}

class _ResidentTile extends StatelessWidget {
  const _ResidentTile(this.animal);

  final Animal animal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasName = animal.name != null && animal.name!.isNotEmpty;
    final status = animal.lifetimeStatus;
    final subtitle = [
      if (hasName) animal.species,
      if (status != null) lifetimeStatusLabel(l10n, status),
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AnimalAvatar(animalId: animal.id, radius: 20),
      title: Text(hasName ? animal.name! : animal.species),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.animalDetail(animal.id)),
    );
  }
}

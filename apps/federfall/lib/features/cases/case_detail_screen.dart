import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/add_entry_sheet.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/carer_line.dart';
import 'package:federfall/features/cases/case_realtime.dart';
import 'package:federfall/features/cases/case_summary_tile.dart';
import 'package:federfall/features/cases/case_timeline.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/edit_case_intake_sheet.dart';
import 'package:federfall/features/cases/placements/placement_sheet.dart';
import 'package:federfall/features/cases/sharing/case_share_sheet.dart';
import 'package:federfall/features/cases/weights/weight_trend_chart.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

/// Case detail (FED-4.3): a persistent name-first identity header over two
/// tabs — **Overview** (intake summary + weight trend) and **History** (the
/// unified chronology where journal, weights and other records live).
class CaseDetailScreen extends ConsumerWidget {
  const CaseDetailScreen({required this.caseId, super.key});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final caseAsync = ref.watch(caseByIdProvider(caseId));
    final medicalCase = caseAsync.value;

    return Scaffold(
      appBar: AppBar(
        // No up arrow when this is the right pane of a two-pane layout — the
        // list is right there; the arrow only makes sense for a full-screen
        // (compact / medium) detail.
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.caseDetailTitle),
        actions: [
          // Edit / share / status moved into the Overview actions card; the
          // app bar keeps only navigation to the animal.
          if (medicalCase != null)
            IconButton(
              icon: const Icon(Icons.pets_outlined),
              tooltip: l10n.caseOpenAnimal,
              onPressed: () =>
                  context.go(AppRoutes.animalDetail(medicalCase.animal)),
            ),
        ],
      ),
      body: AsyncValueView<Case>(
        value: caseAsync,
        onRetry: () => ref.invalidate(caseByIdProvider(caseId)),
        errorMessage: (e) => errorMessage(l10n, e),
        // Top progress bar rather than a centred spinner, so the header doesn't
        // appear to jump from centre to its final top-left position on load.
        loading: const LinearProgressIndicator(),
        data: _CaseDetail.new,
      ),
    );
  }
}

class _CaseDetail extends ConsumerWidget {
  const _CaseDetail(this.medicalCase);

  final Case medicalCase;

  /// Pull-to-refresh: delegate to the case-live notifier so refresh and
  /// realtime share one source list (and one [Ref]).
  Future<void> _refresh(WidgetRef ref) => ref
      .read(caseLiveProvider(medicalCase.id, medicalCase.animal).notifier)
      .refresh();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final animal = ref.watch(animalByIdProvider(medicalCase.animal)).value;
    // One source of truth for every write control on this screen (server rule
    // mirror): the add-entry FAB, the actions card, the timeline edit/delete
    // menus, and the read-only badge all derive from this.
    final canEdit =
        ref.watch(canEditCaseProvider(medicalCase.id)).value ?? false;
    ref
      // Live-sync: re-fetch the timeline when a teammate changes this case.
      ..watch(caseLiveProvider(medicalCase.id, medicalCase.animal))
      // Live-sync the "prior cases" card. CaseLive only reacts to events for
      // THIS case, but a sibling case being shared/unshared changes which prior
      // cases are visible/tappable — and that flows through case_shares (the
      // case record is untouched). Invalidate the leaf list providers
      // (animalLifetime watches them, so it recomputes); invalidating
      // animalLifetime alone would re-read their still-cached values.
      ..liveRefresh(const ['cases', 'case_shares'], () {
        ref
          ..invalidate(casesForAnimalProvider(medicalCase.animal))
          ..invalidate(caseSummariesForAnimalProvider(medicalCase.animal));
      });

    final overview = _OverviewTab(
      medicalCase: medicalCase,
      animal: animal,
      onRefresh: () => _refresh(ref),
    );
    final history = _HistoryTab(
      medicalCase: medicalCase,
      canEdit: canEdit,
      onRefresh: () => _refresh(ref),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: _Header(
            medicalCase: medicalCase,
            animal: animal,
            readOnly: !canEdit,
          ),
        ),
        // Wide detail panes show Overview and History side-by-side; narrow
        // ones keep them behind tabs. Keyed on the pane width (not the window)
        // so the split only triggers when the detail itself is roomy — a
        // 840-wide window whose detail pane is ~480 keeps the tabs.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= kCaseDetailTwoColumnMin) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: overview),
                    const VerticalDivider(width: 1),
                    Expanded(child: history),
                  ],
                );
              }
              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: l10n.caseTabOverview),
                        Tab(text: l10n.caseTabHistory),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(children: [overview, history]),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The History tab: the unified chronology with its add-entry FAB. The FAB
/// lives here (not on Overview) because the timeline is what it acts on. Shared
/// by the tabbed (compact) and side-by-side (wide) case-detail layouts.
class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.medicalCase,
    required this.canEdit,
    required this.onRefresh,
  });

  final Case medicalCase;
  final bool canEdit;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () =>
                  showAddEntrySheet(context, medicalCase: medicalCase),
              icon: const Icon(Icons.add),
              label: Text(l10n.timelineAddEntry),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            CaseTimeline(
              medicalCase: medicalCase,
              canEdit: canEdit,
              showTitle: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Overview tab: structured intake summary and the weight trend.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.medicalCase,
    required this.animal,
    required this.onRefresh,
  });

  final Case medicalCase;
  final Animal? animal;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          WeightTrendChart.forCase(medicalCase.id),
          _IntakeSection(medicalCase: medicalCase, animal: animal),
          _PriorCasesSection(medicalCase: medicalCase),
          _CaseActions(medicalCase: medicalCase),
        ],
      ),
    );
  }
}

/// Actions for the case, grouped in one card at the bottom of the Overview
/// (UX Phase C / C.1): advance the lifecycle status (in_care ->
/// ready_for_release; disposed is terminal, set by the disposition hook),
/// edit the intake, and manage sharing. Shown only to the active carer or a
/// supervisor — mirrors the server update/share rules; read-only viewers see
/// nothing here.
class _CaseActions extends ConsumerStatefulWidget {
  const _CaseActions({required this.medicalCase});

  final Case medicalCase;

  @override
  ConsumerState<_CaseActions> createState() => _CaseActionsState();
}

class _CaseActionsState extends ConsumerState<_CaseActions> {
  bool _busy = false;

  Future<void> _setStatus(CaseStatus status) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final repo = await ref.read(casesRepositoryProvider.future);
      await repo.update(widget.medicalCase.id, {'status': status.wire});
      ref
        ..invalidate(caseByIdProvider(widget.medicalCase.id))
        ..invalidate(casesBrowserDataProvider)
        ..invalidate(dashboardSummaryProvider);
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final medicalCase = widget.medicalCase;
    final status = medicalCase.status;
    final canEdit =
        ref.watch(canEditCaseProvider(medicalCase.id)).value ?? false;

    if (!canEdit) return const SizedBox.shrink();

    final showStatusToggle = status != CaseStatus.disposed;
    final (statusLabel, statusTarget) = switch (status) {
      CaseStatus.inCare => (
        l10n.caseMarkReadyForRelease,
        CaseStatus.readyForRelease,
      ),
      _ => (l10n.caseMarkBackToCare, CaseStatus.inCare),
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.caseActionsTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (showStatusToggle)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _setStatus(statusTarget),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.flag_outlined),
                  label: Text(statusLabel),
                ),
              const SizedBox(height: AppSpacing.sm),
              if (showStatusToggle)
                OutlinedButton.icon(
                  onPressed: () => showPlacementSheet(
                    context,
                    medicalCase: medicalCase,
                    mode: PlacementMode.handoff,
                  ),
                  icon: const Icon(Icons.swap_horiz_outlined),
                  label: Text(l10n.placementHandoffTitle),
                ),
              if (showStatusToggle) const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => showEditCaseIntakeSheet(context, medicalCase),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.caseEditIntakeTitle),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => showCaseShareSheet(
                  context,
                  caseId: medicalCase.id,
                  activeCarer: medicalCase.activeCarer,
                ),
                icon: const Icon(Icons.share_outlined),
                label: Text(l10n.caseShareAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The animal's OTHER cases (current one excluded), newest-first (blp.3).
/// Reuses the org-wide lifetime view (FED-7.6) so cases the user can't open
/// still appear as non-tappable stubs. Renders nothing until loaded and when
/// there are no other cases.
class _PriorCasesSection extends ConsumerWidget {
  const _PriorCasesSection({required this.medicalCase});

  final Case medicalCase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lifetime =
        ref.watch(animalLifetimeProvider(medicalCase.animal)).value;
    if (lifetime == null) return const SizedBox.shrink();

    final others =
        lifetime.cases.where((c) => c.id != medicalCase.id).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.casePriorCasesTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final c in others)
                CaseSummaryTile(
                  summary: c,
                  accessible: lifetime.accessibleCaseIds.contains(c.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name-first case header: the animal's name dominates, with species and case
/// number beneath and the case status as a chip. Built on the shared
/// [DetailHeader] (also used by the animal lifetime screen).
class _Header extends StatelessWidget {
  const _Header({
    required this.medicalCase,
    required this.animal,
    this.readOnly = false,
  });

  final Case medicalCase;
  final Animal? animal;

  /// When true the user can only view this case; surfaced as a header badge so
  /// the absence of write controls is explained rather than mysterious.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final name = animal?.name;
    final hasName = name != null && name.isNotEmpty;
    final title = hasName ? name : (animal?.species ?? l10n.caseAnimalLabel);

    final subtitle = [
      if (hasName && animal != null) animal!.species,
      if (medicalCase.caseNumber != null) medicalCase.caseNumber!,
    ].join(' · ');
    final status = medicalCase.status;
    final carerId = medicalCase.activeCarer;
    final hasCarer = carerId != null && carerId.isNotEmpty;

    return DetailHeader(
      title: title,
      subtitle: subtitle,
      footer: hasCarer ? CarerLine(carerId) : null,
      chipLabel: status == null ? null : caseStatusLabel(l10n, status),
      // The avatar only needs the animal id, which the case always carries —
      // rendering it unconditionally keeps the header left-aligned instead of
      // briefly centring while the Animal record loads.
      leading: AnimalAvatar(animalId: medicalCase.animal, editable: true),
      trailing: readOnly
          ? Tooltip(
              message: l10n.caseReadOnlyTooltip,
              child: Chip(
                avatar: const Icon(Icons.lock_outline, size: 16),
                label: Text(l10n.caseReadOnly),
                visualDensity: VisualDensity.compact,
              ),
            )
          : null,
    );
  }
}

/// The structured intake summary, rendered as a card of labelled rows. Empty
/// fields are skipped so the card stays as terse as the record allows.
class _IntakeSection extends ConsumerWidget {
  const _IntakeSection({required this.medicalCase, required this.animal});

  final Case medicalCase;
  final Animal? animal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);

    String? date(DateTime? d) =>
        d == null ? null : materialL10n.formatMediumDate(d);

    final reasonsById =
        ref.watch(admissionReasonsByIdProvider).value ?? const {};
    final reasons = medicalCase.admissionReasons
        .map((id) => reasonsById[id]?.label)
        .nonNulls
        .join(', ');
    final sex = animal?.sex;
    final ageClass = medicalCase.ageClass;

    final rows = <_DetailRow>[
      if (sex != null)
        _DetailRow(Icons.transgender_outlined, l10n.caseFieldSex,
            sexLabel(l10n, sex)),
      if (ageClass != null)
        _DetailRow(Icons.cake_outlined, l10n.caseFieldAgeClass,
            ageClassLabel(l10n, ageClass)),
      if (reasons.isNotEmpty)
        _DetailRow(Icons.report_outlined, l10n.caseReasonsFieldLabel, reasons),
      if (date(medicalCase.foundAt) case final d?)
        _DetailRow(Icons.event_outlined, l10n.caseFieldFoundAt, d),
      if (date(medicalCase.admittedAt) case final d?)
        _DetailRow(Icons.event_available_outlined, l10n.caseFieldAdmittedAt, d),
      // Quarantine moved to the case timeline (History tab) as its own record
      // kind — federfall-uvm. It is no longer a static field on the case.
      if (medicalCase.findLocation case final loc?)
        _DetailRow(Icons.place_outlined, l10n.caseFieldFindLocation, loc),
      if (medicalCase.intakeNotes case final notes?)
        _DetailRow(Icons.notes_outlined, l10n.caseFieldIntakeNotes, notes),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.caseSectionIntake,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (rows.isEmpty)
              Text(l10n.emptyGeneric,
                  style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final row in rows) row,
            if (medicalCase.finder case final finderId?)
              _FinderRow(finderId),
            if (medicalCase.intakePhotos.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _IntakePhotos(
                caseId: medicalCase.id,
                filenames: medicalCase.intakePhotos,
              ),
            ],
            if (medicalCase.findGeo case final geo?) ...[
              const SizedBox(height: AppSpacing.sm),
              _FindMap(geo: geo),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small, non-interactive map preview of the case's find location (FED-4.2).
class _FindMap extends StatelessWidget {
  const _FindMap({required this.geo});

  final GeoPoint geo;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(geo.lat, geo.lon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 160,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 14,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            const MapTileLayer(),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: Icon(
                    Icons.location_on,
                    size: 40,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
            const MapAttribution(),
          ],
        ),
      ),
    );
  }
}

/// Thumbnails of a case's intake photos; tapping one opens it full-size.
class _IntakePhotos extends ConsumerWidget {
  const _IntakePhotos({required this.caseId, required this.filenames});

  final String caseId;
  final List<String> filenames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(casesRepositoryProvider).value;
    if (repo == null) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Intake photos are a Protected file field (FED-8.1), but the access token
    // is appended at download time (ProtectedFileCacheManager), so the URLs
    // here stay token-free and cached thumbnails render without a token mint.
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filenames.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final thumb = repo.fileUrl(caseId, filenames[i], thumb: '200x200');
          return GestureDetector(
            onTap: () => unawaited(
              showImageViewer(
                context,
                imageUrls: [
                  for (final f in filenames)
                    repo.fileUrl(caseId, f).toString(),
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

/// One labelled value inside the intake card.
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves and renders the linked finder's contact details, when present.
class _FinderRow extends ConsumerWidget {
  const _FinderRow(this.finderId);

  final String finderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final finder = ref.watch(finderByIdProvider(finderId)).value;
    if (finder == null) return const SizedBox.shrink();

    final name = [finder.firstName, finder.lastName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    final value = [
      if (name.isNotEmpty) name,
      ?finder.phone,
      ?finder.email,
      ?finder.city,
    ].join(' · ');
    if (value.isEmpty) return const SizedBox.shrink();

    return _DetailRow(
      Icons.person_pin_circle_outlined,
      l10n.caseFinderLabel,
      value,
    );
  }
}

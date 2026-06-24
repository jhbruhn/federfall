import 'dart:async';

import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/case_summary_tile.dart';
import 'package:federfall/features/cases/case_timeline.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/sharing/case_share_sheet.dart';
import 'package:federfall/features/cases/weights/weight_trend_chart.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final me = ref.watch(currentUserProvider).value;
    // Only the active carer or a supervisor may share (the server create rule
    // enforces this too).
    final canShare =
        medicalCase != null &&
        me != null &&
        (medicalCase.activeCarer == me.id || me.role == UserRole.supervisor);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.caseDetailTitle),
        actions: [
          if (canShare)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l10n.caseShareAction,
              onPressed: () => showCaseShareSheet(
                context,
                caseId: caseId,
                activeCarer: medicalCase.activeCarer,
              ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final animal = ref.watch(animalByIdProvider(medicalCase.animal)).value;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: _Header(medicalCase: medicalCase, animal: animal),
          ),
          TabBar(
            tabs: [
              Tab(text: l10n.caseTabOverview),
              Tab(text: l10n.caseTabHistory),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(medicalCase: medicalCase, animal: animal),
                ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    CaseTimeline(medicalCase: medicalCase, showTitle: false),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Overview tab: structured intake summary and the weight trend.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.medicalCase, required this.animal});

  final Case medicalCase;
  final Animal? animal;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        WeightTrendChart(caseId: medicalCase.id),
        _IntakeSection(medicalCase: medicalCase, animal: animal),
        _PriorCasesSection(medicalCase: medicalCase),
      ],
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
  const _Header({required this.medicalCase, required this.animal});

  final Case medicalCase;
  final Animal? animal;

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

    return DetailHeader(
      title: title,
      subtitle: subtitle,
      chipLabel: status == null ? null : caseStatusLabel(l10n, status),
      // The avatar only needs the animal id, which the case always carries —
      // rendering it unconditionally keeps the header left-aligned instead of
      // briefly centring while the Animal record loads.
      leading: AnimalAvatar(animalId: medicalCase.animal, editable: true),
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

    final reasons = medicalCase.reasonsForAdmission
        .map((r) => admissionReasonLabel(l10n, r))
        .join(', ');
    final sex = animal?.sex;
    final ageClass = medicalCase.ageClass;
    final weight = medicalCase.intakeWeightG;

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
      if (medicalCase.findLocation case final loc?)
        _DetailRow(Icons.place_outlined, l10n.caseFieldFindLocation, loc),
      if (weight != null)
        _DetailRow(Icons.monitor_weight_outlined, l10n.caseFieldIntakeWeight,
            '$weight g'),
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
            TileLayer(
              urlTemplate: AppEnvironment.mapTileUrl,
              userAgentPackageName: 'de.jhbruhn.federfall',
            ),
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
    if (repo == null) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filenames.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final thumb = repo.fileUrl(caseId, filenames[i], thumb: '200x200');
          final full = repo.fileUrl(caseId, filenames[i]);
          return GestureDetector(
            onTap: () => unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(full.toString(), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
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

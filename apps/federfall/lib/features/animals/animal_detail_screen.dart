import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/case_summary_tile.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Animal lifetime detail (FED-7.6): one animal's full record — identity,
/// markings (active + historic) and every case newest-first. Cases the user
/// cannot open render as a non-tappable stub (number / status / dates only).
class AnimalDetailScreen extends ConsumerWidget {
  const AnimalDetailScreen({required this.animalId, super.key});

  final String animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lifetime = ref.watch(animalLifetimeProvider(animalId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.animalDetailTitle)),
      body: AsyncValueView<AnimalLifetime>(
        value: lifetime,
        onRetry: () => ref.invalidate(animalLifetimeProvider(animalId)),
        errorMessage: (e) => errorMessage(l10n, e),
        // Top progress bar rather than a centred spinner, so the header doesn't
        // appear to jump from centre to its final top-left position on load.
        loading: const LinearProgressIndicator(),
        data: (data) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Identity(data.animal),
            const SizedBox(height: AppSpacing.md),
            _MarkingsSection(data.markings),
            const SizedBox(height: AppSpacing.md),
            _CasesSection(
              cases: data.cases,
              accessibleIds: data.accessibleCaseIds,
            ),
          ],
        ),
      ),
    );
  }
}

/// Name-first identity header — the exact same shared [DetailHeader] (avatar +
/// name + species/sex + lifetime-status chip) the case detail screen uses, so
/// the two headers look identical.
class _Identity extends StatelessWidget {
  const _Identity(this.animal);

  final Animal animal;

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
      leading: AnimalAvatar(animalId: animal.id, editable: true),
    );
  }
}

class _MarkingsSection extends StatelessWidget {
  const _MarkingsSection(this.markings);

  final List<Marking> markings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.animalSectionMarkings,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
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
                  title: Text(_markingTitle(l10n, m)),
                  subtitle: m.isActive
                      ? null
                      : Text(
                          m.removedAt == null
                              ? l10n.markingRemoved
                              : l10n.markingRemovedOn(
                                  materialL10n.formatMediumDate(m.removedAt!),
                                ),
                        ),
                ),
          ],
        ),
      ),
    );
  }

  String _markingTitle(AppLocalizations l10n, Marking m) {
    final code = m.code;
    final label = markingTypeLabel(l10n, m.type);
    return code != null && code.isNotEmpty ? '$label · $code' : label;
  }
}

class _CasesSection extends StatelessWidget {
  const _CasesSection({required this.cases, required this.accessibleIds});

  final List<CaseSummary> cases;
  final Set<String> accessibleIds;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.animalSectionCases, style: theme.textTheme.titleMedium),
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

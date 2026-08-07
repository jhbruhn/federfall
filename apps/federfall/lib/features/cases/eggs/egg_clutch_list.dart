import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/eggs/egg_entry_tile.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the animal's complete laying history as a scrollable sheet — the way
/// out of the animal card's deliberate caps, which would otherwise leave older
/// clutches unreachable.
Future<void> showEggHistorySheet(
  BuildContext context, {
  required String animalId,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _EggHistorySheet(animalId: animalId),
  );
}

/// An animal's laying events grouped into derived clutches, newest first.
///
/// Shared by the animal detail's card (capped via [maxClutches] / [maxRows]) and
/// the full-history sheet (uncapped), so both show the same rows, subheadings
/// and per-record menu.
class EggClutchList extends StatelessWidget {
  const EggClutchList({
    required this.eggs,
    this.maxClutches,
    this.maxRows,
    super.key,
  });

  /// The animal's ledger, in any order — grouping sorts it.
  final List<EggRecord> eggs;

  /// How many clutches to list at most; unlimited when null.
  final int? maxClutches;

  /// Hard cap on record rows, shared across the listed clutches. A clutch is
  /// derived (anything within [kClutchGapDays] of the previous egg joins it),
  /// so a hen laying every few days for weeks grows one clutch without bound.
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    // Newest clutch first — the reverse of the grouping order, newest record
    // first within each — sharing one row budget.
    final clutches = groupIntoClutches(eggs).reversed;
    final groups = <(List<EggRecord> clutch, List<EggRecord> rows)>[];
    var budget = maxRows;
    for (final clutch
        in maxClutches == null ? clutches : clutches.take(maxClutches!)) {
      if (budget == 0) break;
      final rows =
          (budget == null ? clutch.reversed : clutch.reversed.take(budget))
              .toList();
      if (budget != null) budget -= rows.length;
      groups.add((clutch, rows));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (clutch, rows) in groups) ...[
          // Only where it groups something. A one-record clutch header would
          // repeat its single row word for word — same date, same egg count.
          if (clutch.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                // Describes the whole clutch even where the row budget
                // truncated it.
                clutchHeader(l10n, materialL10n, clutch),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          for (final egg in rows) EggRow(egg: egg),
        ],
      ],
    );
  }
}

/// "CLUTCH · JUN 2, 2026 – JUN 4, 2026 · 2 EGGS" for one derived clutch, or the
/// single date when the whole clutch landed on one day. Uppercased like the
/// other group headers in the app.
///
/// [DateStyle.short] rather than the [DateStyle.medium] the rows use:
/// Material's medium form is "Wed, Jun 2" — a weekday nobody needs here and,
/// worse, no year at all, which a lifetime ledger spanning seasons has to show.
String clutchHeader(
  AppLocalizations l10n,
  MaterialLocalizations materialL10n,
  List<EggRecord> clutch,
) {
  final dates = clutch.map((e) => e.laidAt ?? e.created).nonNulls.toList();
  const short = DateStyle.short;
  final first = dates.isEmpty
      ? ''
      : formatLocalDate(materialL10n, dates.first, style: short);
  final last = dates.isEmpty
      ? ''
      : formatLocalDate(materialL10n, dates.last, style: short);
  final label = first == last ? first : '$first – $last';
  return l10n
      .eggClutchHeader(label, clutch.fold(0, (sum, e) => sum + e.count))
      .toUpperCase();
}

/// One laying event as a list row: date, count, the "presumed" badge, a single
/// leading thumb when photos exist (a full strip would fight the card layout)
/// and the same overflow menu the case-timeline tile carries.
class EggRow extends ConsumerWidget {
  const EggRow({required this.egg, super.key});

  final EggRecord egg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final repo = ref.watch(eggRecordsRepositoryProvider).value;
    final at = egg.laidAt ?? egg.created;
    final firstPhoto = egg.photos.firstOrNull;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: (firstPhoto == null || repo == null)
          ? const Icon(Icons.egg_outlined)
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedFileImage(
                url: repo.fileUrl(egg.id, firstPhoto, thumb: '200x200'),
                width: 40,
                height: 40,
              ),
            ),
      title: Row(
        children: [
          Flexible(child: Text(l10n.eggCountLabel(egg.count))),
          if (egg.attribution == EggAttribution.presumed) ...[
            const SizedBox(width: AppSpacing.sm),
            TagChip(label: l10n.eggPresumedChip),
          ],
        ],
      ),
      subtitle: switch (at) {
        final at? => Text(formatLocalDate(materialL10n, at)),
        _ => null,
      },
      trailing: EggEntryMenu(egg: egg),
      titleTextStyle: theme.textTheme.bodyLarge,
    );
  }
}

/// The whole ledger in a sheet that scrolls on its own, so a long-lived hen's
/// history never pushes the animal detail's later sections out of reach.
class _EggHistorySheet extends ConsumerWidget {
  const _EggHistorySheet({required this.animalId});

  final String animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final eggs = ref.watch(eggsForAnimalProvider(animalId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.eggHistoryTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: SingleChildScrollView(
                child: AsyncValueView<List<EggRecord>>(
                  value: eggs,
                  onRetry: () =>
                      ref.invalidate(eggsForAnimalProvider(animalId)),
                  loading: const LinearProgressIndicator(),
                  data: (eggs) => eggs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: Text(
                            l10n.animalNoEggs,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : EggClutchList(eggs: eggs),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

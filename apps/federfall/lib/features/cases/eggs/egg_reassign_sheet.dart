import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animal_search_picker.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the egg re-attribution sheet. Resolves to `true` when at least one
/// record moved, so the caller can refresh.
Future<bool?> showEggReassignSheet(
  BuildContext context, {
  required EggRecord egg,
  String? caseId,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => EggReassignSheet(egg: egg, caseId: caseId),
  );
}

/// Moves an egg record — or the whole derived clutch — to another animal
/// (federfall-4agw). The reason the feature is shaped the way it is: in a pair
/// you often only learn which hen laid a clutch later, and correcting that must
/// be a few taps rather than delete-and-retype.
///
/// The write is `{'animal': target, 'attribution': 'confirmed'}` per row, run
/// sequentially. No transaction and no custom route: nothing derived depends on
/// it, so a partial failure is harmless — the sheet reports how many moved and
/// re-running covers the rest. Photos are fields on the row, so they travel
/// with it; a JSON PATCH that omits a file field leaves it alone.
class EggReassignSheet extends ConsumerStatefulWidget {
  const EggReassignSheet({required this.egg, this.caseId, super.key});

  final EggRecord egg;

  /// The case timeline the sheet was opened from, if any — invalidated after
  /// the move so the egg leaves it.
  final String? caseId;

  @override
  ConsumerState<EggReassignSheet> createState() => _EggReassignSheetState();
}

class _EggReassignSheetState extends ConsumerState<EggReassignSheet>
    with DiscardGuard, FormSheetState {
  final _searchController = TextEditingController();

  /// Whole clutch rather than the single record.
  bool _wholeClutch = false;
  String _query = '';
  Animal? _target;

  DateTime get _laidAt =>
      widget.egg.laidAt ?? widget.egg.created ?? DateTime.now();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The records the current scope covers.
  List<EggRecord> _scopeRecords(List<EggRecord> ledger) =>
      _wholeClutch ? clutchContaining(ledger, widget.egg) : [widget.egg];

  Future<void> _submit(List<EggRecord> ledger) async {
    final target = _target;
    if (target == null) return;
    final records = _scopeRecords(ledger);

    var moved = 0;
    final ok = await runSave(() async {
      final repo = await ref.read(eggRecordsRepositoryProvider.future);
      Object? firstFailure;
      StackTrace? firstTrace;
      for (final record in records) {
        try {
          // Re-attributing IS the confirmation: someone now knows the layer.
          await repo.update(record.id, {
            'animal': target.id,
            'attribution': EggAttribution.confirmed.wire,
          });
          moved++;
        } on Object catch (error, trace) {
          firstFailure ??= error;
          firstTrace ??= trace;
        }
      }

      ref
        ..invalidate(eggsForAnimalProvider(widget.egg.animal))
        ..invalidate(eggsForAnimalProvider(target.id));
      if (widget.caseId case final id?) ref.invalidate(caseBundleProvider(id));

      // Nothing moved at all: surface the failure in the sheet's error slot
      // rather than closing as if it had worked.
      if (moved == 0) {
        if (firstFailure case final failure?) {
          Error.throwWithStackTrace(failure, firstTrace ?? StackTrace.current);
        }
      }
    });

    if (!ok || !mounted) return;
    final partial = moved < records.length;
    if (partial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.eggReassignPartial(moved, records.length),
          ),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final ledger =
        ref.watch(eggsForAnimalProvider(widget.egg.animal)).value ??
        [widget.egg];
    final clutch = clutchContaining(ledger, widget.egg);
    final records = _scopeRecords(ledger);
    final target = _target;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: l10n.eggReassignTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        saveLabel: l10n.eggReassignConfirmAction,
        onSave: target == null ? () {} : () => _submit(ledger),
        children: [
          // ── 1. scope ────────────────────────────────────────────────────
          Text(l10n.eggReassignScopeTitle, style: theme.textTheme.titleSmall),
          RadioGroup<bool>(
            groupValue: _wholeClutch,
            onChanged: (v) {
              if (isBusy) return;
              setState(() => _wholeClutch = v ?? false);
              markDirty();
            },
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: false,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.eggReassignScopeSingle),
                ),
                RadioListTile<bool>(
                  value: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.eggReassignScopeClutch(
                      clutch.fold(0, (sum, e) => sum + e.count),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── 2. the new layer: co-residents first, search second ─────────
          if (target == null) ...[
            _CoResidents(
              animalId: widget.egg.animal,
              at: _laidAt,
              enabled: !isBusy,
              onPick: (a) => unawaited(_pick(a)),
            ),
            const SizedBox(height: AppSpacing.md),
            AnimalSearchPicker(
              controller: _searchController,
              query: _query,
              label: l10n.eggReassignSearchLabel,
              excludeAnimalId: widget.egg.animal,
              enabled: !isBusy,
              onSearch: (q) => setState(() => _query = q),
              onPick: (a) => unawaited(_pick(a)),
            ),
          ] else ...[
            Text(
              l10n.eggReassignTargetTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: AnimalAvatar(animalId: target.id, radius: 20),
                title: Text(animalTitle(target)),
                trailing: TextButton(
                  onPressed: isBusy
                      ? null
                      : () => setState(() => _target = null),
                  child: Text(l10n.eggReassignChangeTarget),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── 3. what this changes, on someone else's record ────────────
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.eggReassignSummaryTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.eggReassignSummaryMoves(
                        records.length,
                        records.fold(0, (sum, e) => sum + e.count),
                        animalTitle(target),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.eggReassignSplitHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatLocalDate(materialL10n, _laidAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Selects [animal] as the target — once custody allows it to receive the
  /// record (federfall-v9ap).
  ///
  /// `animal_custody_scope.pb.js` requires custody of the INCOMING bird for a
  /// re-attribution, so the picker must not offer one the server will refuse.
  /// Checked at PICK time rather than per search result, for the reason
  /// `new_case_screen.dart`'s `_linkAnimal` gives: the picker is a result list,
  /// and resolving custody per row would put one request per candidate into it
  /// (federfall-trep). One bird, one check.
  Future<void> _pick(Animal animal) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    String? failure;
    try {
      final holds = await ref.read(canWriteAnimalProvider(animal.id).future);
      if (!holds) failure = l10n.eggReassignNotHeld;
    } on Object catch (e, stackTrace) {
      // Fail closed: an unreachable server would refuse the save a moment
      // later anyway, with the target already chosen.
      reportCaughtError(e, stackTrace);
      failure = errorMessage(l10n, e);
    }
    if (!mounted) return;
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    setState(() => _target = animal);
    markDirty();
  }
}

/// The animals that shared an enclosure with this bird on the laying date, from
/// the `aviary_stays` ledger. In a pair this is a one-tap list, which is the
/// whole ergonomic point — searching is the fallback, not the default.
class _CoResidents extends ConsumerWidget {
  const _CoResidents({
    required this.animalId,
    required this.at,
    required this.enabled,
    required this.onPick,
  });

  final String animalId;
  final DateTime at;
  final bool enabled;
  final ValueChanged<Animal> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final candidates = ref.watch(eggCoResidentsProvider(animalId, at));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.eggReassignCandidatesTitle(
            formatLocalDate(materialL10n, at),
          ),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        candidates.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          // A missing residency history is not an error worth a retry here:
          // search below still reaches every animal.
          error: (_, _) => Text(
            l10n.eggReassignNoCandidates,
            style: theme.textTheme.bodyMedium,
          ),
          data: (animals) => animals.isEmpty
              ? Text(
                  l10n.eggReassignNoCandidates,
                  style: theme.textTheme.bodyMedium,
                )
              : Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final animal in animals)
                        ListTile(
                          leading: AnimalAvatar(
                            animalId: animal.id,
                            radius: 20,
                          ),
                          title: Text(animalTitle(animal)),
                          onTap: enabled ? () => onPick(animal) : null,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

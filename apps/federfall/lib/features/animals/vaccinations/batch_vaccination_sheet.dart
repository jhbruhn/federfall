import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_form_fields.dart';
import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the batch-vaccination form for an enclosure. Resolves to the number of
/// birds vaccinated, or null if nothing was saved.
Future<int?> showBatchVaccinationSheet(
  BuildContext context, {
  required String aviaryId,
}) {
  return showAppSheet<int>(
    context,
    builder: (_) => BatchVaccinationSheet(aviaryId: aviaryId),
  );
}

/// Vaccinate a whole enclosure in one act (federfall-s63u): every current
/// resident preselected, the odd bird deselected, one shared record.
///
/// The roster comes from `aviaryResidents` and the birds are sent as a LIST —
/// the route never resolves the enclosure itself, or it would vaccinate the
/// bird the keeper had just unticked.
///
/// Custody is answered HERE, per bird, before the request: an enclosure's
/// roster can contain a bird whose open case belongs to another carer, and the
/// route refuses the whole batch over one of them (deliberately — a partial
/// flock is worse than a refusal). So those rows are shown, disabled and
/// labelled, rather than silently dropped: "this bird was not vaccinated" is
/// exactly the fact the keeper needs to leave with.
class BatchVaccinationSheet extends ConsumerStatefulWidget {
  const BatchVaccinationSheet({required this.aviaryId, super.key});

  final String aviaryId;

  @override
  ConsumerState<BatchVaccinationSheet> createState() =>
      _BatchVaccinationSheetState();
}

class _BatchVaccinationSheetState extends ConsumerState<BatchVaccinationSheet>
    with DiscardGuard, FormSheetState {
  late final VaccinationFormModel _model;

  /// The birds explicitly unticked. Kept as the exception rather than as a
  /// selection set, so a resident that arrives late (the roster is a live
  /// provider) is included by default rather than silently skipped.
  final _excluded = <String>{};

  /// Written to when the save comes back, so the sheet can pop with a count.
  int _saved = 0;

  /// One key for this sheet's whole lifetime: pressing save again after a
  /// timeout resubmits the SAME key, so the server replays the committed batch
  /// instead of vaccinating the flock twice (federfall-3ty3's guarantee, which
  /// matters more here than anywhere — a duplicate is N duplicates).
  final String _idempotencyKey = newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _model = VaccinationFormModel();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  /// The residents this user may actually write about, minus the unticked ones.
  List<Animal> _selected(List<Animal> residents) => [
    for (final a in residents)
      if (!_excluded.contains(a.id) && _holds(a.id)) a,
  ];

  bool _holds(String animalId) =>
      ref.watch(canWriteAnimalProvider(animalId)).value ?? false;

  Future<void> _save(List<Animal> residents) async {
    final chosen = _selected(residents);
    setState(
      () => _model.vaccineError = _model.vaccineText.isEmpty
          ? context.l10n.fieldRequired
          : null,
    );
    if (_model.vaccineText.isEmpty || chosen.isEmpty) return;
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final repo = await ref.read(vaccinationsRepositoryProvider.future);
      _saved = await repo.vaccinateBatch(
        [for (final a in chosen) a.id],
        _model.payload(),
        // One act, one key: a retry after a timeout replays the committed
        // batch instead of vaccinating the flock a second time.
        idempotencyKey: _idempotencyKey,
      );

      for (final animal in chosen) {
        ref.invalidate(vaccinationsForAnimalProvider(animal.id));
      }
      // The suggestion view is derived from the rows themselves.
      ref.invalidate(vaccineLabelsProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(_saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final residents = ref.watch(aviaryResidentsProvider(widget.aviaryId));
    final all = residents.value ?? const <Animal>[];
    final chosen = _selected(all);
    final blocked = [
      for (final a in all)
        if (!_holds(a.id)) a,
    ];

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: l10n.vaccinationBatchTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        // Nothing selected means the button does nothing rather than
        // disappearing: a disabled control still says the act exists.
        onSave: () {
          if (chosen.isNotEmpty) _save(all).ignore();
        },
        saveLabel: l10n.vaccinationBatchSaveAction(chosen.length),
        children: [
          Text(
            l10n.vaccinationBatchIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // A load failure must not render as "no residents" — route through
          // the standard error state with a retry (federfall-5cle).
          AsyncValueView<List<Animal>>(
            value: residents,
            onRetry: () =>
                ref.invalidate(aviaryResidentsProvider(widget.aviaryId)),
            loading: const LinearProgressIndicator(),
            data: (residents) => residents.isEmpty
                ? Text(
                    l10n.aviaryNoResidents,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final animal in residents)
                        _ResidentCheck(
                          animal: animal,
                          // Disabled rather than hidden: a bird missing from
                          // this list would read as one that got the shot.
                          enabled: !isBusy && _holds(animal.id),
                          selected:
                              _holds(animal.id) &&
                              !_excluded.contains(animal.id),
                          onChanged: (on) {
                            setState(() {
                              if (on) {
                                _excluded.remove(animal.id);
                              } else {
                                _excluded.add(animal.id);
                              }
                            });
                            markDirty();
                          },
                        ),
                    ],
                  ),
          ),
          if (blocked.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.vaccinationBatchBlocked(blocked.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          VaccinationFields(
            model: _model,
            enabled: !isBusy,
            onChanged: markDirty,
          ),
        ],
      ),
    );
  }
}

/// One resident row: tick to include. Shows why a bird cannot be ticked rather
/// than leaving the box mysteriously dead.
class _ResidentCheck extends StatelessWidget {
  const _ResidentCheck({
    required this.animal,
    required this.enabled,
    required this.selected,
    required this.onChanged,
  });

  final Animal animal;
  final bool enabled;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = animal.name?.trim();
    return CheckboxListTile(
      value: selected,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        name != null && name.isNotEmpty ? name : animal.species,
        style: enabled
            ? null
            : TextStyle(color: Theme.of(context).disabledColor),
      ),
      subtitle: enabled
          ? (name != null && name.isNotEmpty ? Text(animal.species) : null)
          : Text(l10n.vaccinationBatchNotYours),
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
    );
  }
}

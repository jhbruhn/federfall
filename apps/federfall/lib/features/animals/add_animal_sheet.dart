import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adds a new animal directly into an aviary as a permanent resident (zoi) —
/// an animal that never had an acute case. This is the *only* case-less create
/// path: a free-standing "new animal" is deliberately not offered, so the
/// normal intake flow (which creates the animal as part of opening a case)
/// isn't bypassed. Resolves to the new animal's id, or null if cancelled.
Future<String?> showAddAnimalSheet(
  BuildContext context, {
  required String aviaryId,
}) {
  return showAppSheet<String>(
    context,
    builder: (_) => AddAnimalSheet(aviaryId: aviaryId),
  );
}

class AddAnimalSheet extends ConsumerStatefulWidget {
  const AddAnimalSheet({required this.aviaryId, super.key});

  /// The aviary the new animal becomes a resident of.
  final String aviaryId;

  @override
  ConsumerState<AddAnimalSheet> createState() => _AddAnimalSheetState();
}

class _AddAnimalSheetState extends ConsumerState<AddAnimalSheet>
    with DiscardGuard, FormSheetState {
  final _name = TextEditingController();
  final _species = TextEditingController();
  Sex? _sex;

  @override
  void dispose() {
    _name.dispose();
    _species.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);

    String? createdId;
    final ok = await runSave(() async {
      final (_, org) = await requireUserOrg();
      final repo = await ref.read(animalsRepositoryProvider.future);
      final created = await repo.create({
        'species': _species.text.trim(),
        'name': ?trimToNull(_name),
        'sex': ?_sex?.wire,
        'current_aviary': widget.aviaryId,
        'lifetime_status': LifetimeStatus.inAviary.wire,
        'org': org,
      });
      createdId = created.id;

      ref
        ..invalidate(animalsRegistryProvider)
        ..invalidate(aviaryResidentsProvider(widget.aviaryId));
    });
    if (ok && mounted) navigator.pop(createdId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: l10n.aviaryAddResident,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _species,
            label: l10n.caseFieldSpecies,
            prefixIcon: Icons.pets_outlined,
            textInputAction: TextInputAction.next,
            enabled: !isBusy,
            validator: Validators.required(l10n),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _name,
            label: l10n.caseFieldName,
            prefixIcon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<Sex>(
            initialValue: _sex,
            decoration: InputDecoration(
              labelText: l10n.caseFieldSex,
              prefixIcon: const Icon(Icons.transgender_outlined),
            ),
            items: [
              for (final s in Sex.values)
                DropdownMenuItem(value: s, child: Text(sexLabel(l10n, s))),
            ],
            onChanged: isBusy ? null : (s) => setState(() => _sex = s),
          ),
        ],
      ),
    );
  }
}

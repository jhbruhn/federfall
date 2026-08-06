import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edit an animal's identity (UX Phase B): name, species and sex. These are
/// write-once at intake today; this lets a carer fix a typo'd species or fill
/// in a name later. Resolves to `true` when saved so the caller can refresh.
Future<bool?> showEditAnimalSheet(BuildContext context, Animal animal) {
  return showAppSheet<bool>(
    context,
    builder: (_) => EditAnimalSheet(animal: animal),
  );
}

class EditAnimalSheet extends ConsumerStatefulWidget {
  const EditAnimalSheet({required this.animal, super.key});

  final Animal animal;

  @override
  ConsumerState<EditAnimalSheet> createState() => _EditAnimalSheetState();
}

class _EditAnimalSheetState extends ConsumerState<EditAnimalSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _name;
  late final TextEditingController _species;
  late Sex? _sex;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.animal.name ?? '');
    _species = TextEditingController(text: widget.animal.species);
    _sex = widget.animal.sex;
  }

  @override
  void dispose() {
    _name.dispose();
    _species.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);

    final ok = await runSave(() async {
      final repo = await ref.read(animalsRepositoryProvider.future);
      // Empty strings, not omissions: this is an edit, so clearing a name or a
      // sex has to reach the server as a clear.
      await repo.update(widget.animal.id, {
        'species': _species.text.trim(),
        'name': _name.text.trim(),
        'sex': _sex?.wire ?? '',
      });
      ref
        ..invalidate(animalByIdProvider(widget.animal.id))
        ..invalidate(animalLifetimeProvider(widget.animal.id))
        ..invalidate(animalsRegistryProvider);
    });
    if (ok && mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: l10n.animalEditTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _name,
            label: l10n.caseFieldName,
            prefixIcon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _species,
            label: l10n.caseFieldSpecies,
            prefixIcon: Icons.pets_outlined,
            textInputAction: TextInputAction.next,
            enabled: !isBusy,
            validator: Validators.required(l10n),
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

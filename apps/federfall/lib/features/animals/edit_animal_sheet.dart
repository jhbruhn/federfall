import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
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

class _EditAnimalSheetState extends ConsumerState<EditAnimalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _species;
  late Sex? _sex;
  bool _busy = false;
  String? _error;

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
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(animalsRepositoryProvider.future);
      await repo.update(widget.animal.id, {
        'species': _species.text.trim(),
        'name': _name.text.trim(),
        'sex': _sex?.wire ?? '',
      });
      ref
        ..invalidate(animalByIdProvider(widget.animal.id))
        ..invalidate(animalLifetimeProvider(widget.animal.id))
        ..invalidate(animalsRegistryProvider);
      if (!mounted) return;
      navigator.pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.animalEditTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _name,
                label: l10n.caseFieldName,
                prefixIcon: Icons.badge_outlined,
                textInputAction: TextInputAction.next,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _species,
                label: l10n.caseFieldSpecies,
                prefixIcon: Icons.pets_outlined,
                textInputAction: TextInputAction.next,
                enabled: !_busy,
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
                onChanged: _busy ? null : (s) => setState(() => _sex = s),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: l10n.actionSave,
                icon: Icons.check,
                isLoading: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

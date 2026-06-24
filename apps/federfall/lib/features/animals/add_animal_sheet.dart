import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
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
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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

class _AddAnimalSheetState extends ConsumerState<AddAnimalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _species = TextEditingController();
  Sex? _sex;
  bool _busy = false;
  String? _error;

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
      final user = await ref.read(currentUserProvider.future);
      final org = user?.org;
      if (user == null || org == null) {
        throw const RepositoryException('no org for current user');
      }
      final repo = await ref.read(animalsRepositoryProvider.future);
      final name = _name.text.trim();
      final created = await repo.create({
        'species': _species.text.trim(),
        if (name.isNotEmpty) 'name': name,
        if (_sex != null) 'sex': _sex!.wire,
        'current_aviary': widget.aviaryId,
        'lifetime_status': LifetimeStatus.inAviary.wire,
        'org': org,
      });

      ref
        ..invalidate(animalsRegistryProvider)
        ..invalidate(aviaryResidentsProvider(widget.aviaryId));
      if (mounted) navigator.pop(created.id);
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
              Text(l10n.aviaryAddResident, style: theme.textTheme.titleLarge),
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
              AppTextField(
                controller: _name,
                label: l10n.caseFieldName,
                prefixIcon: Icons.badge_outlined,
                textInputAction: TextInputAction.next,
                enabled: !_busy,
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

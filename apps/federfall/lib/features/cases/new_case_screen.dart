import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Minimal create-case form (FED-3.4): an animal (name + species) and the
/// case's reason for admission. Creates the animal, then the case pointing at
/// it with the signed-in user as active carer; the backend hooks fill in the
/// case number, status and quarantine window.
class NewCaseScreen extends ConsumerStatefulWidget {
  const NewCaseScreen({super.key});

  /// Default species — the overwhelming majority of intakes are feral pigeons.
  static const defaultSpecies = 'Stadttaube';

  @override
  ConsumerState<NewCaseScreen> createState() => _NewCaseScreenState();
}

class _NewCaseScreenState extends ConsumerState<NewCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _speciesController =
      TextEditingController(text: NewCaseScreen.defaultSpecies);

  AdmissionReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _speciesController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = context.l10n;
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

      final animalsRepo = await ref.read(animalsRepositoryProvider.future);
      final casesRepo = await ref.read(casesRepositoryProvider.future);

      final name = _nameController.text.trim();
      final animal = await animalsRepo.create({
        'species': _speciesController.text.trim(),
        if (name.isNotEmpty) 'name': name,
        'org': org,
      });

      await casesRepo.create({
        'animal': animal.id,
        'org': org,
        'active_carer': user.id,
        if (_reason != null) 'reasons_for_admission': [_reason!.wire],
      });

      ref.invalidate(myCasesProvider);
      if (mounted) context.pop();
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.caseNewTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      controller: _nameController,
                      label: l10n.caseFieldName,
                      prefixIcon: Icons.badge_outlined,
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _speciesController,
                      label: l10n.caseFieldSpecies,
                      prefixIcon: Icons.pets_outlined,
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                      validator: Validators.required(l10n),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<AdmissionReason>(
                      initialValue: _reason,
                      decoration: InputDecoration(
                        labelText: l10n.caseFieldReason,
                        prefixIcon: const Icon(Icons.report_outlined),
                      ),
                      items: [
                        for (final r in AdmissionReason.values)
                          DropdownMenuItem(
                            value: r,
                            child: Text(admissionReasonLabel(l10n, r)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (r) => setState(() => _reason = r),
                      validator: (v) =>
                          v == null ? l10n.fieldRequired : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: l10n.caseCreateAction,
                      icon: Icons.check,
                      isLoading: _busy,
                      onPressed: _create,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

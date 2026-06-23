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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full intake form (FED-4.1). Captures the persistent **animal** identity
/// (species, name, sex), the **case** intake details (reasons, dates, find
/// location, weight, notes) and — optionally — the external **finder**'s
/// contact PII. On submit it creates the animal, the finder if any field was
/// filled, then the case linking them with the signed-in user as active carer;
/// the backend hooks fill in case number, status and quarantine window.
///
/// Photo attachments and map-based find-location are deferred to FED-4.7 and
/// FED-4.2 respectively.
class NewCaseScreen extends ConsumerStatefulWidget {
  const NewCaseScreen({super.key});

  /// Default species — the overwhelming majority of intakes are feral pigeons.
  static const defaultSpecies = 'Stadttaube';

  @override
  ConsumerState<NewCaseScreen> createState() => _NewCaseScreenState();
}

class _NewCaseScreenState extends ConsumerState<NewCaseScreen> {
  final _formKey = GlobalKey<FormState>();

  // Animal identity.
  final _nameController = TextEditingController();
  final _speciesController =
      TextEditingController(text: NewCaseScreen.defaultSpecies);
  Sex? _sex;

  // Case intake.
  final _findLocationController = TextEditingController();
  final _intakeWeightController = TextEditingController();
  final _intakeNotesController = TextEditingController();
  final Set<AdmissionReason> _reasons = {};
  AgeClass? _ageClass;
  DateTime? _foundAt;
  DateTime? _admittedAt;

  // Finder PII (optional).
  final _finderFirstName = TextEditingController();
  final _finderLastName = TextEditingController();
  final _finderPhone = TextEditingController();
  final _finderEmail = TextEditingController();
  final _finderCity = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _reasonsTouched = false;

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _speciesController,
      _findLocationController,
      _intakeWeightController,
      _intakeNotesController,
      _finderFirstName,
      _finderLastName,
      _finderPhone,
      _finderEmail,
      _finderCity,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trimmedOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Builds the finder body from the contact fields, or `null` when the carer
  /// left the whole section blank.
  Map<String, dynamic>? _finderBody(String org) {
    final fields = {
      'first_name': _trimmedOrNull(_finderFirstName),
      'last_name': _trimmedOrNull(_finderLastName),
      'phone': _trimmedOrNull(_finderPhone),
      'email': _trimmedOrNull(_finderEmail),
      'city': _trimmedOrNull(_finderCity),
    }..removeWhere((_, v) => v == null);
    if (fields.isEmpty) return null;
    return {...fields, 'org': org};
  }

  Future<void> _pickDate(
    DateTime? current,
    ValueChanged<DateTime> onPicked,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _create() async {
    final l10n = context.l10n;
    setState(() => _reasonsTouched = true);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || _reasons.isEmpty) return;

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

      final name = _trimmedOrNull(_nameController);
      final animal = await animalsRepo.create({
        'species': _speciesController.text.trim(),
        'name': ?name,
        if (_sex != null) 'sex': _sex!.wire,
        'org': org,
      });

      // Only touch the finders collection when contact details were entered.
      final finderBody = _finderBody(org);
      String? finderId;
      if (finderBody != null) {
        final findersRepo = await ref.read(findersRepositoryProvider.future);
        finderId = (await findersRepo.create(finderBody)).id;
      }

      final weight = int.tryParse(_intakeWeightController.text.trim());
      await casesRepo.create({
        'animal': animal.id,
        'org': org,
        'active_carer': user.id,
        'reasons_for_admission': [for (final r in _reasons) r.wire],
        if (_ageClass != null) 'age_class': _ageClass!.wire,
        if (_foundAt != null) 'found_at': _foundAt!.toUtc().toIso8601String(),
        if (_admittedAt != null)
          'admitted_at': _admittedAt!.toUtc().toIso8601String(),
        'find_location': ?_trimmedOrNull(_findLocationController),
        'intake_weight_g': ?weight,
        'intake_notes': ?_trimmedOrNull(_intakeNotesController),
        'finder': ?finderId,
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
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionHeading(l10n.caseSectionAnimal),
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
                    DropdownButtonFormField<Sex>(
                      initialValue: _sex,
                      decoration: InputDecoration(
                        labelText: l10n.caseFieldSex,
                        prefixIcon: const Icon(Icons.transgender_outlined),
                      ),
                      items: [
                        for (final s in Sex.values)
                          DropdownMenuItem(
                            value: s,
                            child: Text(sexLabel(l10n, s)),
                          ),
                      ],
                      onChanged:
                          _busy ? null : (s) => setState(() => _sex = s),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    _SectionHeading(l10n.caseSectionIntake),
                    _ReasonsField(
                      selected: _reasons,
                      enabled: !_busy,
                      error: _reasonsTouched && _reasons.isEmpty
                          ? l10n.fieldRequired
                          : null,
                      onToggle: (r) => setState(() {
                        if (!_reasons.remove(r)) _reasons.add(r);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<AgeClass>(
                      initialValue: _ageClass,
                      decoration: InputDecoration(
                        labelText: l10n.caseFieldAgeClass,
                        prefixIcon: const Icon(Icons.cake_outlined),
                      ),
                      items: [
                        for (final a in AgeClass.values)
                          DropdownMenuItem(
                            value: a,
                            child: Text(ageClassLabel(l10n, a)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (a) => setState(() => _ageClass = a),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _DateField(
                      label: l10n.caseFieldFoundAt,
                      value: _foundAt,
                      enabled: !_busy,
                      onPick: () => _pickDate(
                        _foundAt,
                        (d) => setState(() => _foundAt = d),
                      ),
                      onClear: () => setState(() => _foundAt = null),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _DateField(
                      label: l10n.caseFieldAdmittedAt,
                      value: _admittedAt,
                      enabled: !_busy,
                      onPick: () => _pickDate(
                        _admittedAt,
                        (d) => setState(() => _admittedAt = d),
                      ),
                      onClear: () => setState(() => _admittedAt = null),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _findLocationController,
                      label: l10n.caseFieldFindLocation,
                      prefixIcon: Icons.place_outlined,
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _intakeWeightController,
                      label: l10n.caseFieldIntakeWeight,
                      prefixIcon: Icons.monitor_weight_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _intakeNotesController,
                      label: l10n.caseFieldIntakeNotes,
                      prefixIcon: Icons.notes_outlined,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    _FinderSection(
                      firstName: _finderFirstName,
                      lastName: _finderLastName,
                      phone: _finderPhone,
                      email: _finderEmail,
                      city: _finderCity,
                      enabled: !_busy,
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

/// A left-aligned section title separating groups of fields.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        title,
        style: theme.textTheme.titleMedium
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// Multi-select admission reasons as filter chips, with an inline error slot
/// so "at least one" can be enforced alongside the [Form].
class _ReasonsField extends StatelessWidget {
  const _ReasonsField({
    required this.selected,
    required this.enabled,
    required this.onToggle,
    this.error,
  });

  final Set<AdmissionReason> selected;
  final bool enabled;
  final String? error;
  final void Function(AdmissionReason reason) onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.caseReasonsFieldLabel, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final r in AdmissionReason.values)
              FilterChip(
                label: Text(admissionReasonLabel(l10n, r)),
                selected: selected.contains(r),
                onSelected: enabled ? (_) => onToggle(r) : null,
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// A read-only date row: shows the chosen date (or a placeholder) with pick /
/// clear actions. Dates are optional, so a clear button appears once set.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    final text = value == null
        ? l10n.caseDateNotSet
        : materialL10n.formatMediumDate(value!);
    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: value != null && enabled
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: onClear,
                )
              : null,
        ),
        child: Text(text),
      ),
    );
  }
}

/// Collapsible finder-contact sub-form. Every field is optional; the parent
/// only persists a finder record when at least one is filled.
class _FinderSection extends StatelessWidget {
  const _FinderSection({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.city,
    required this.enabled,
  });

  final TextEditingController firstName;
  final TextEditingController lastName;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController city;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.person_pin_circle_outlined),
        title: Text(l10n.caseSectionFinder),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          AppTextField(
            controller: firstName,
            label: l10n.finderFieldFirstName,
            textInputAction: TextInputAction.next,
            enabled: enabled,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: lastName,
            label: l10n.finderFieldLastName,
            textInputAction: TextInputAction.next,
            enabled: enabled,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: phone,
            label: l10n.finderFieldPhone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            enabled: enabled,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: email,
            label: l10n.finderFieldEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: enabled,
            validator: Validators.email(l10n),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: city,
            label: l10n.finderFieldCity,
            textInputAction: TextInputAction.done,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

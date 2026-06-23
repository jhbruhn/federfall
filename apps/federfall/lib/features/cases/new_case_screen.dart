import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/location/location_picker_screen.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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

  // Re-identification (FED-4.10): when set, the case links to this existing
  // animal instead of creating a fresh one.
  final _reidController = TextEditingController();
  String _reidQuery = '';
  Animal? _linkedAnimal;

  // Case intake.
  final _findLocationController = TextEditingController();
  final _intakeWeightController = TextEditingController();
  final _intakeNotesController = TextEditingController();
  final _intakePhotos = <XFile>[];
  final Set<AdmissionReason> _reasons = {};
  AgeClass? _ageClass;
  DateTime? _foundAt;
  DateTime? _admittedAt;

  // Find location (FED-4.2): a geocoded pin + resolved city/region alongside
  // the free-text address.
  GeoPoint? _findGeo;
  String? _findCity;
  String? _findRegion;

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
      _reidController,
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

  Future<void> _pickLocation() async {
    final picked = await showLocationPicker(
      context,
      initial: _findGeo,
      initialAddress: _trimmedOrNull(_findLocationController),
    );
    if (picked == null) return;
    setState(() {
      _findGeo = picked.geo;
      _findCity = picked.city.isEmpty ? null : picked.city;
      _findRegion = picked.region.isEmpty ? null : picked.region;
      if (picked.address.isNotEmpty) {
        _findLocationController.text = picked.address;
      }
    });
  }

  Future<void> _addPhotos() async {
    final picked = await ref.read(imagePickerProvider).pickMultiImage();
    if (picked.isNotEmpty) setState(() => _intakePhotos.addAll(picked));
  }

  Future<void> _capturePhoto() async {
    final shot = await ref
        .read(imagePickerProvider)
        .pickImage(source: ImageSource.camera);
    if (shot != null) setState(() => _intakePhotos.add(shot));
  }

  /// The staged intake photos as multipart files on the `intake_photos` field.
  Future<List<http.MultipartFile>> _intakePhotoFiles() async {
    final files = <http.MultipartFile>[];
    for (final photo in _intakePhotos) {
      files.add(
        http.MultipartFile.fromBytes(
          'intake_photos',
          await photo.readAsBytes(),
          filename: photo.name,
        ),
      );
    }
    return files;
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

      final casesRepo = await ref.read(casesRepositoryProvider.future);

      // Re-identified return: reuse the existing animal; otherwise create one.
      final String animalId;
      final linked = _linkedAnimal;
      if (linked != null) {
        animalId = linked.id;
      } else {
        final animalsRepo = await ref.read(animalsRepositoryProvider.future);
        final name = _trimmedOrNull(_nameController);
        animalId = (await animalsRepo.create({
          'species': _speciesController.text.trim(),
          'name': ?name,
          if (_sex != null) 'sex': _sex!.wire,
          'org': org,
        })).id;
      }

      // Only touch the finders collection when contact details were entered.
      final finderBody = _finderBody(org);
      String? finderId;
      if (finderBody != null) {
        final findersRepo = await ref.read(findersRepositoryProvider.future);
        finderId = (await findersRepo.create(finderBody)).id;
      }

      final weight = int.tryParse(_intakeWeightController.text.trim());
      final body = <String, dynamic>{
        'animal': animalId,
        'org': org,
        'active_carer': user.id,
        'reasons_for_admission': [for (final r in _reasons) r.wire],
        if (_ageClass != null) 'age_class': _ageClass!.wire,
        if (_foundAt != null) 'found_at': _foundAt!.toUtc().toIso8601String(),
        if (_admittedAt != null)
          'admitted_at': _admittedAt!.toUtc().toIso8601String(),
        'find_location': ?_trimmedOrNull(_findLocationController),
        if (_findGeo case final geo?)
          'find_geo': {'lon': geo.lon, 'lat': geo.lat},
        'city': ?_findCity,
        'region': ?_findRegion,
        'intake_weight_g': ?weight,
        'intake_notes': ?_trimmedOrNull(_intakeNotesController),
        'finder': ?finderId,
      };

      final photos = await _intakePhotoFiles();
      if (photos.isEmpty) {
        await casesRepo.create(body);
      } else {
        await casesRepo.createWithFiles(body, photos);
      }

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
                    if (_linkedAnimal case final linked?)
                      _LinkedAnimalCard(
                        animal: linked,
                        enabled: !_busy,
                        onUnlink: () => setState(() => _linkedAnimal = null),
                      )
                    else ...[
                      _ReidSearchField(
                        controller: _reidController,
                        enabled: !_busy,
                        query: _reidQuery,
                        onSearch: (q) => setState(() => _reidQuery = q),
                        onLink: (a) => setState(() {
                          _linkedAnimal = a;
                          _reidQuery = '';
                          _reidController.clear();
                        }),
                      ),
                      const SizedBox(height: AppSpacing.md),
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
                    ],
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _findLocationController,
                            label: l10n.caseFieldFindLocation,
                            prefixIcon: Icons.place_outlined,
                            textInputAction: TextInputAction.next,
                            enabled: !_busy,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton.filledTonal(
                          icon: Icon(
                            _findGeo == null
                                ? Icons.add_location_alt_outlined
                                : Icons.edit_location_alt,
                          ),
                          tooltip: l10n.locationPickAction,
                          onPressed: _busy ? null : _pickLocation,
                        ),
                      ],
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
                    const SizedBox(height: AppSpacing.md),
                    StagedPhotos(
                      photos: _intakePhotos,
                      enabled: !_busy,
                      onAdd: _addPhotos,
                      onCapture: _capturePhoto,
                      onRemove: (i) =>
                          setState(() => _intakePhotos.removeAt(i)),
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

/// Re-identification search at intake (FED-4.10): look up an existing animal by
/// an active ring code or by name, so a returning bird's case links to it.
class _ReidSearchField extends ConsumerWidget {
  const _ReidSearchField({
    required this.controller,
    required this.enabled,
    required this.query,
    required this.onSearch,
    required this.onLink,
  });

  final TextEditingController controller;
  final bool enabled;
  final String query;
  final ValueChanged<String> onSearch;
  final ValueChanged<Animal> onLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: controller,
                label: l10n.reidSearchLabel,
                hintText: l10n.reidSearchHint,
                prefixIcon: Icons.search,
                enabled: enabled,
                onChanged: (_) {},
              ),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.search),
              onPressed:
                  enabled ? () => onSearch(controller.text.trim()) : null,
            ),
          ],
        ),
        if (query.isNotEmpty)
          ref.watch(reidSearchProvider(query)).when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const SizedBox.shrink(),
                data: (matches) => matches.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          l10n.reidNoMatches,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : Card(
                        margin: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final m in matches)
                              ListTile(
                                leading: const Icon(Icons.pets_outlined),
                                title: Text(_animalTitle(m.animal)),
                                subtitle: Text(_markingsLine(l10n, m)),
                                onTap:
                                    enabled ? () => onLink(m.animal) : null,
                              ),
                          ],
                        ),
                      ),
              ),
      ],
    );
  }

  String _animalTitle(Animal a) {
    final name = a.name;
    return name == null || name.isEmpty ? a.species : '$name · ${a.species}';
  }

  String _markingsLine(AppLocalizations l10n, ReidMatch m) {
    if (m.markings.isEmpty) return l10n.reidNoMarkings;
    return m.markings
        .map((mk) {
          final code = mk.code;
          final type = markingTypeLabel(l10n, mk.type);
          return code == null || code.isEmpty ? type : '$type $code';
        })
        .join(' · ');
  }
}

/// Summary shown once a case is linked to an existing animal, with its prior
/// case count and an unlink action.
class _LinkedAnimalCard extends ConsumerWidget {
  const _LinkedAnimalCard({
    required this.animal,
    required this.enabled,
    required this.onUnlink,
  });

  final Animal animal;
  final bool enabled;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final priorCount =
        ref.watch(casesForAnimalProvider(animal.id)).value?.length ?? 0;
    final name = animal.name;
    final title = name == null || name.isEmpty
        ? animal.species
        : '$name · ${animal.species}';

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.link),
        title: Text(title),
        subtitle: Text(l10n.reidPriorCases(priorCount)),
        trailing: TextButton(
          onPressed: enabled ? onUnlink : null,
          child: Text(l10n.reidUnlink),
        ),
      ),
    );
  }
}

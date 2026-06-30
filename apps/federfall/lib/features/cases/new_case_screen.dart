import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/org_settings_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/exams/exam_sheet.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/location/location_picker_screen.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
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
  const NewCaseScreen({this.animalId, super.key});

  /// When set, the case is pre-linked to this existing animal (e.g. opening a
  /// new case for an aviary resident) instead of starting from re-id search.
  final String? animalId;

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

  // Re-identification (FED-4.10): when set, the case links to this existing
  // animal instead of creating a fresh one.
  final _reidController = TextEditingController();
  String _reidQuery = '';
  Animal? _linkedAnimal;

  // Case intake.
  final _findLocationController = TextEditingController();
  final _intakeWeightController = TextEditingController();
  final _quarantineDaysController = TextEditingController();
  final _intakeNotesController = TextEditingController();

  // The org-wide default quarantine duration, prefilled into the field above
  // once loaded. Kept so submit can skip the per-case update when the carer
  // left the default untouched (the backend hook already applies it).
  int? _orgDefaultQuarantineDays;
  final _intakePhotos = <XFile>[];
  final Set<AdmissionReason> _reasons = {};
  AgeClass? _ageClass;
  // Default both intake dates to today (the common case); still editable and
  // clearable for a bird found earlier or an unknown find date.
  DateTime? _foundAt = DateTime.now();
  DateTime? _admittedAt = DateTime.now();

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
  bool _withExam = false;

  /// Current wizard step: 0 = animal, 1 = admission, 2 = docs & finder.
  int _step = 0;
  static const _lastStep = 2;

  @override
  void initState() {
    super.initState();
    final id = widget.animalId;
    if (id != null) {
      // Pre-link to the given animal (e.g. a resident relapse) so the carer
      // skips re-id search.
      ref
          .read(animalByIdProvider(id).future)
          .then((a) {
            if (mounted) setState(() => _linkedAnimal = a);
          })
          .ignore();
    }
    // Prefill the quarantine duration from the org-wide default; the carer can
    // override it for this case (empty falls back to the same default).
    ref
        .read(orgQuarantineDefaultDaysProvider.future)
        .then((days) {
          if (!mounted) return;
          setState(() {
            _orgDefaultQuarantineDays = days;
            if (_quarantineDaysController.text.trim().isEmpty) {
              _quarantineDaysController.text = '$days';
            }
          });
        })
        .ignore();
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _speciesController,
      _reidController,
      _findLocationController,
      _intakeWeightController,
      _quarantineDaysController,
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
        'intake_notes': ?_trimmedOrNull(_intakeNotesController),
        'finder': ?finderId,
      };

      final photos = await _intakePhotoFiles();
      final created = photos.isEmpty
          ? await casesRepo.create(body)
          : await casesRepo.createWithFiles(body, photos);

      // The intake weight is a real Weight entry (single source of truth +
      // trend), not a field on the case. Baseline measured at admission.
      if (weight != null && weight > 0) {
        final weightsRepo = await ref.read(weightsRepositoryProvider.future);
        await weightsRepo.create({
          'animal': animalId,
          'case': created.id,
          'weight_g': weight,
          'measured_at':
              (_admittedAt ?? DateTime.now()).toUtc().toIso8601String(),
          'author': user.id,
          'org': org,
        });
      }

      // Quarantine: the create hook already made the org-default record. If the
      // carer set a different duration, update that record's end rather than
      // adding a second one (one record per quarantine period).
      final quarantineDays = int.tryParse(
        _quarantineDaysController.text.trim(),
      );
      if (quarantineDays != null &&
          quarantineDays > 0 &&
          quarantineDays != _orgDefaultQuarantineDays) {
        final quarantineRepo =
            await ref.read(quarantineRepositoryProvider.future);
        final records = await quarantineRepo.forCase(created.id);
        if (records.isNotEmpty) {
          final base = _admittedAt ?? DateTime.now();
          await quarantineRepo.update(records.first.id, {
            'set_at': base.toUtc().toIso8601String(),
            'quarantine_until': base
                .add(Duration(days: quarantineDays))
                .toUtc()
                .toIso8601String(),
          });
        }
      }

      ref
        ..invalidate(casesBrowserDataProvider)
        ..invalidate(dashboardSummaryProvider);
      if (!mounted) return;
      // Optional intake exam: open the same sheet on the just-created case
      // (kept off the create path so it never blocks intake).
      if (_withExam) {
        await showExamSheet(
          context,
          caseId: created.id,
          animalId: animalId,
        );
        if (!mounted) return;
      }
      context.pop();
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

  /// Advances to the next step, validating the current one first. The two
  /// required fields are checked at the step that owns them: species on step 0
  /// (unless an existing animal is linked), at least one reason on step 1.
  void _next() {
    if (_step == 0) {
      if (_linkedAnimal == null &&
          !(_formKey.currentState?.validate() ?? false)) {
        return;
      }
    } else if (_step == 1) {
      setState(() => _reasonsTouched = true);
      if (_reasons.isEmpty) return;
    }
    setState(() => _step++);
  }

  void _back() => setState(() => _step--);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final titles = [
      l10n.caseSectionAnimal,
      l10n.caseSectionIntake,
      l10n.caseStepFinish,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.caseNewTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                _WizardHeader(
                  step: _step,
                  total: _lastStep + 1,
                  title: titles[_step],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Form(
                      key: _formKey,
                      child: switch (_step) {
                        0 => _buildAnimalStep(l10n),
                        1 => _buildIntakeStep(l10n),
                        _ => _buildFinishStep(l10n),
                      },
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                _WizardNav(
                  showBack: _step > 0,
                  busy: _busy,
                  onBack: _busy ? null : _back,
                  isLast: _step == _lastStep,
                  onNext: _busy ? null : _next,
                  onCreate: _create,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Step 0 — the animal identity: re-id search, species and name.
  Widget _buildAnimalStep(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            controller: _speciesController,
            label: l10n.caseFieldSpecies,
            prefixIcon: Icons.pets_outlined,
            textInputAction: TextInputAction.next,
            enabled: !_busy,
            validator: Validators.required(l10n),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _nameController,
            label: l10n.caseFieldName,
            prefixIcon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
            enabled: !_busy,
          ),
        ],
      ],
    );
  }

  /// Step 1 — the admission: reasons, age class, dates, find location, weight.
  Widget _buildIntakeStep(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              DropdownMenuItem(value: a, child: Text(ageClassLabel(l10n, a))),
          ],
          onChanged: _busy ? null : (a) => setState(() => _ageClass = a),
        ),
        const SizedBox(height: AppSpacing.md),
        _DateField(
          label: l10n.caseFieldFoundAt,
          value: _foundAt,
          enabled: !_busy,
          onPick: () =>
              _pickDate(_foundAt, (d) => setState(() => _foundAt = d)),
          onClear: () => setState(() => _foundAt = null),
        ),
        const SizedBox(height: AppSpacing.md),
        _DateField(
          label: l10n.caseFieldAdmittedAt,
          value: _admittedAt,
          enabled: !_busy,
          onPick: () =>
              _pickDate(_admittedAt, (d) => setState(() => _admittedAt = d)),
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
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
          enabled: !_busy,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _quarantineDaysController,
          label: l10n.caseFieldQuarantineDays,
          hintText: l10n.caseFieldQuarantineDaysHint,
          prefixIcon: Icons.shield_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !_busy,
        ),
      ],
    );
  }

  /// Step 2 — documentation and people: photos, notes, the optional finder and
  /// the create action (with the optional intake exam).
  Widget _buildFinishStep(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StagedPhotos(
          photos: _intakePhotos,
          enabled: !_busy,
          onAdd: _addPhotos,
          onCapture: _capturePhoto,
          onRemove: (i) => setState(() => _intakePhotos.removeAt(i)),
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
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _withExam,
          onChanged: _busy ? null : (v) => setState(() => _withExam = v),
          title: Text(l10n.caseIntakeWithExam),
          subtitle: Text(l10n.caseIntakeWithExamHint),
        ),
      ],
    );
  }
}

/// Wizard progress header: a "step n of total" label, the step title and a row
/// of segment bars marking progress through the intake.
class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.step,
    required this.total,
    required this.title,
  });

  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.caseStepLabel(step + 1, total),
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Wizard bottom bar: Back (from step 2 on) plus either Next or, on the final
/// step, the Create action.
class _WizardNav extends StatelessWidget {
  const _WizardNav({
    required this.showBack,
    required this.busy,
    required this.onBack,
    required this.isLast,
    required this.onNext,
    required this.onCreate,
  });

  final bool showBack;
  final bool busy;
  final VoidCallback? onBack;
  final bool isLast;
  final VoidCallback? onNext;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          if (showBack) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: Text(l10n.actionBack),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: isLast
                ? PrimaryButton(
                    label: l10n.caseCreateAction,
                    icon: Icons.check,
                    isLoading: busy,
                    onPressed: onCreate,
                  )
                : FilledButton.icon(
                    onPressed: onNext,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.actionNext),
                  ),
          ),
        ],
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
                prefixIcon: Icons.badge_outlined,
                enabled: enabled,
                textInputAction: TextInputAction.search,
                onChanged: (_) {},
                onSubmitted: (v) => onSearch(v.trim()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              icon: const Icon(Icons.search),
              tooltip: l10n.reidSearchLabel,
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

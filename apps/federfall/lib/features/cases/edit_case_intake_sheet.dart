import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/location/location_picker_screen.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edit a case's intake details after creation (UX Phase B): admission
/// reasons, age class, found/admitted dates, find location and intake
/// weight/notes. These were write-once at intake; this lets a carer fix
/// mistakes. Animal identity, finder PII and photos are edited elsewhere.
/// Resolves to `true` on save so the caller can refresh.
Future<bool?> showEditCaseIntakeSheet(BuildContext context, Case medicalCase) {
  return showAppSheet<bool>(
    context,
    builder: (_) => EditCaseIntakeSheet(medicalCase: medicalCase),
  );
}

class EditCaseIntakeSheet extends ConsumerStatefulWidget {
  const EditCaseIntakeSheet({required this.medicalCase, super.key});

  final Case medicalCase;

  @override
  ConsumerState<EditCaseIntakeSheet> createState() =>
      _EditCaseIntakeSheetState();
}

class _EditCaseIntakeSheetState extends ConsumerState<EditCaseIntakeSheet>
    with DiscardGuard {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _findLocation;
  late final TextEditingController _notes;
  late final Set<String> _reasons;
  late AgeClass? _ageClass;
  late DateTime? _foundAt;
  late DateTime? _admittedAt;
  GeoPoint? _findGeo;
  String? _findCity;
  String? _findRegion;
  bool _busy = false;
  String? _error;
  bool _reasonsError = false;

  @override
  void initState() {
    super.initState();
    final c = widget.medicalCase;
    _findLocation = TextEditingController(text: c.findLocation ?? '');
    _notes = TextEditingController(text: c.intakeNotes ?? '');
    _reasons = {...c.admissionReasons};
    _ageClass = c.ageClass;
    _foundAt = c.foundAt;
    _admittedAt = c.admittedAt;
    _findGeo = c.findGeo;
    _findCity = c.city;
    _findRegion = c.region;
  }

  @override
  void dispose() {
    _findLocation.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final picked = await showLocationPicker(
      context,
      initial: _findGeo,
      initialAddress: _findLocation.text.trim().isEmpty
          ? null
          : _findLocation.text.trim(),
    );
    if (picked == null) return;
    setState(() {
      _findGeo = picked.geo;
      _findCity = picked.city.isEmpty ? null : picked.city;
      _findRegion = picked.region.isEmpty ? null : picked.region;
      if (picked.address.isNotEmpty) _findLocation.text = picked.address;
    });
    markDirty();
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> onPicked,
    bool allowFuture = false,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      // Quarantine ends in the future; intake dates can't be after today.
      lastDate: allowFuture ? DateTime(now.year + 3, now.month, now.day) : now,
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final validForm = _formKey.currentState?.validate() ?? false;
    setState(() => _reasonsError = _reasons.isEmpty);
    if (!validForm || _reasons.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(casesRepositoryProvider.future);
      await repo.update(widget.medicalCase.id, {
        'admission_reasons': _reasons.toList(),
        'age_class': _ageClass?.wire ?? '',
        'found_at': _foundAt?.toUtc().toIso8601String() ?? '',
        'admitted_at': _admittedAt?.toUtc().toIso8601String() ?? '',
        'find_location': _findLocation.text.trim(),
        'find_geo': _findGeo == null
            ? {'lon': 0, 'lat': 0}
            : {'lon': _findGeo!.lon, 'lat': _findGeo!.lat},
        'city': _findCity ?? '',
        'region': _findRegion ?? '',
        'intake_notes': _notes.text.trim(),
      });
      ref
        ..invalidate(caseByIdProvider(widget.medicalCase.id))
        ..invalidate(casesBrowserDataProvider)
        ..invalidate(dashboardSummaryProvider);
      if (!mounted) return;
      navigator.pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
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
    final materialL10n = MaterialLocalizations.of(context);

    return guardUnsavedChanges(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.sm,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            onChanged: markDirty,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.caseEditIntakeTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.caseReasonsFieldLabel,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  switch (ref.watch(admissionReasonsProvider)) {
                    AsyncData(:final value) => Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        // Active entries, plus any deactivated one still set on
                        // this case (so the carer can see/remove it).
                        for (final r in value.where(
                          (r) => r.active || _reasons.contains(r.id),
                        ))
                          FilterChip(
                            label: Text(r.label),
                            selected: _reasons.contains(r.id),
                            onSelected: _busy
                                ? null
                                : (sel) {
                                    setState(() {
                                      sel
                                          ? _reasons.add(r.id)
                                          : _reasons.remove(r.id);
                                      _reasonsError = false;
                                    });
                                    markDirty();
                                  },
                          ),
                      ],
                    ),
                    AsyncError() => Text(l10n.errorGenericTitle),
                    _ => const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: LinearProgressIndicator(),
                    ),
                  },
                  if (_reasonsError)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        l10n.fieldRequired,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
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
                  const SizedBox(height: AppSpacing.sm),
                  _DateRow(
                    label: l10n.caseFieldFoundAt,
                    value: _foundAt,
                    formatted: _foundAt == null
                        ? null
                        : materialL10n.formatMediumDate(_foundAt!),
                    enabled: !_busy,
                    onPick: () => _pickDate(
                      current: _foundAt,
                      onPicked: (d) {
                        setState(() => _foundAt = d);
                        markDirty();
                      },
                    ),
                    onClear: () {
                      setState(() => _foundAt = null);
                      markDirty();
                    },
                  ),
                  _DateRow(
                    label: l10n.caseFieldAdmittedAt,
                    value: _admittedAt,
                    formatted: _admittedAt == null
                        ? null
                        : materialL10n.formatMediumDate(_admittedAt!),
                    enabled: !_busy,
                    onPick: () => _pickDate(
                      current: _admittedAt,
                      onPicked: (d) {
                        setState(() => _admittedAt = d);
                        markDirty();
                      },
                    ),
                    onClear: () {
                      setState(() => _admittedAt = null);
                      markDirty();
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _findLocation,
                          label: l10n.caseFieldFindLocation,
                          prefixIcon: Icons.place_outlined,
                          enabled: !_busy,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.map_outlined),
                        tooltip: l10n.caseFieldFindLocation,
                        onPressed: _busy ? null : _pickLocation,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _notes,
                    label: l10n.caseFieldIntakeNotes,
                    enabled: !_busy,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
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
        ),
      ),
    );
  }
}

/// A labelled date row with pick / clear actions (dates are optional).
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.formatted,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final String? formatted;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      subtitle: Text(formatted ?? '—'),
      trailing: value == null
          ? null
          : IconButton(
              icon: const Icon(Icons.clear),
              onPressed: enabled ? onClear : null,
            ),
      onTap: enabled ? onPick : null,
    );
  }
}

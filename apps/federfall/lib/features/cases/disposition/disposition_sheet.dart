import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_providers.dart';
import 'package:federfall/features/cases/location/location_picker_screen.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the record-outcome (disposition) form for a case. Pass [disposition]
/// to edit an existing outcome. Resolves to `true` when something changed.
Future<bool?> showDispositionSheet(
  BuildContext context, {
  required String caseId,
  Disposition? disposition,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DispositionSheet(caseId: caseId, disposition: disposition),
  );
}

/// Records a case outcome (FED-4.11 / FED-4.12): released (with location/geo),
/// placed in a named aviary, died, euthanized, transferred or returned to
/// owner. The backend hook then maintains the case status and the animal's
/// lifetime status (placement keeps the case alive as an aviary resident and
/// sets the animal's current aviary).
class DispositionSheet extends ConsumerStatefulWidget {
  const DispositionSheet({required this.caseId, this.disposition, super.key});

  final String caseId;
  final Disposition? disposition;

  /// Outcomes selectable here.
  static const List<DispositionType> _selectableTypes = [
    DispositionType.released,
    DispositionType.placedInAviary,
    DispositionType.died,
    DispositionType.euthanized,
    DispositionType.transferred,
    DispositionType.returnedToOwner,
  ];

  @override
  ConsumerState<DispositionSheet> createState() => _DispositionSheetState();
}

class _DispositionSheetState extends ConsumerState<DispositionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _releaseLocation = TextEditingController();
  final _releaseType = TextEditingController();
  final _transferType = TextEditingController();
  final _transferDestination = TextEditingController();
  final _vet = TextEditingController();

  DispositionType _type = DispositionType.released;
  GeoPoint? _releaseGeo;
  String? _aviaryId;
  DateTime _disposedAt = DateTime.now();
  bool _vetSignedOff = false;
  bool _busy = false;
  String? _error;

  bool get _isRelease => _type == DispositionType.released;
  bool get _isTransfer => _type == DispositionType.transferred;
  bool get _isEuthanized => _type == DispositionType.euthanized;
  bool get _isAviary => _type == DispositionType.placedInAviary;
  // Release can carry a vet sign-off flag; euthanasia instead records the
  // external vet who performed it (no vet login — a name).
  bool get _showVetSignoff => _isRelease;

  bool get _isEditing => widget.disposition != null;

  @override
  void initState() {
    super.initState();
    final d = widget.disposition;
    if (d == null) return;
    _type = d.type;
    _disposedAt = d.disposedAt ?? DateTime.now();
    _reason.text = d.reason ?? '';
    _releaseLocation.text = d.releaseLocation ?? '';
    _releaseType.text = d.releaseType ?? '';
    _releaseGeo = d.releaseGeo;
    _transferType.text = d.transferType ?? '';
    _transferDestination.text = d.transferDestination ?? '';
    _aviaryId = d.aviary;
    _vet.text = d.vet ?? '';
    _vetSignedOff = d.vetSignedOff;
  }

  @override
  void dispose() {
    for (final c in [
      _reason,
      _releaseLocation,
      _releaseType,
      _transferType,
      _transferDestination,
      _vet,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _disposedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _disposedAt = picked);
  }

  Future<void> _pickReleaseLocation() async {
    final picked = await showLocationPicker(
      context,
      initial: _releaseGeo,
      initialAddress: _trim(_releaseLocation),
    );
    if (picked == null) return;
    setState(() {
      _releaseGeo = picked.geo;
      if (picked.address.isNotEmpty) _releaseLocation.text = picked.address;
    });
  }

  Future<void> _save() async {
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
      final repo = await ref.read(dispositionsRepositoryProvider.future);

      final body = <String, dynamic>{
        'case': widget.caseId,
        'type': _type.wire,
        'disposed_at': _disposedAt.toUtc().toIso8601String(),
        'reason': _trim(_reason) ?? '',
        'performed_by': user.id,
        'vet_signed_off': _showVetSignoff && _vetSignedOff,
        if (_isEuthanized) 'vet': _trim(_vet) ?? '',
        'org': org,
        if (_isRelease) ...{
          'release_location': _trim(_releaseLocation) ?? '',
          'release_type': _trim(_releaseType) ?? '',
          if (_releaseGeo case final geo?)
            'release_geo': {'lon': geo.lon, 'lat': geo.lat},
        },
        if (_isTransfer) ...{
          'transfer_type': _trim(_transferType) ?? '',
          'transfer_destination': _trim(_transferDestination) ?? '',
        },
        if (_isAviary) 'aviary': ?_aviaryId,
      };

      final existing = widget.disposition;
      if (existing == null) {
        await repo.create(body);
      } else {
        await repo.update(existing.id, body);
      }

      _refresh();
      if (mounted) Navigator.of(context).pop(true);
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

  /// The backend hook maintains the case status and the animal's lifetime
  /// status / current aviary on any disposition change; refresh the views that
  /// show them.
  void _refresh() {
    ref
      ..invalidate(dispositionsForCaseProvider(widget.caseId))
      ..invalidate(caseByIdProvider(widget.caseId))
      ..invalidate(casesBrowserDataProvider)
      ..invalidate(dashboardSummaryProvider)
      ..invalidate(animalsRegistryProvider);
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final existing = widget.disposition;
    if (existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dispositionDeleteAction),
        content: Text(l10n.dispositionDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.dispositionDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(dispositionsRepositoryProvider.future);
      await repo.delete(existing.id);
      _refresh();
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
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? l10n.dispositionEditTitle
                    : l10n.dispositionNewTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<DispositionType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l10n.dispositionFieldType,
                  prefixIcon: const Icon(Icons.outbound_outlined),
                ),
                items: [
                  for (final t in DispositionSheet._selectableTypes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(dispositionTypeLabel(l10n, t)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (t) => setState(() => _type = t ?? _type),
              ),
              const SizedBox(height: AppSpacing.md),
              DateField(
                label: l10n.dispositionFieldDate,
                value: _disposedAt,
                enabled: !_busy,
                onPick: _pickDate,
              ),
              if (_isRelease) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _releaseLocation,
                        label: l10n.dispositionFieldReleaseLocation,
                        prefixIcon: Icons.place_outlined,
                        enabled: !_busy,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filledTonal(
                      icon: Icon(
                        _releaseGeo == null
                            ? Icons.add_location_alt_outlined
                            : Icons.edit_location_alt,
                      ),
                      tooltip: l10n.locationPickAction,
                      onPressed: _busy ? null : _pickReleaseLocation,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _releaseType,
                  label: l10n.dispositionFieldReleaseType,
                  hintText: l10n.dispositionReleaseTypeHint,
                  prefixIcon: Icons.flight_takeoff_outlined,
                  enabled: !_busy,
                ),
              ],
              if (_isTransfer) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _transferDestination,
                  label: l10n.dispositionFieldTransferTo,
                  prefixIcon: Icons.local_shipping_outlined,
                  enabled: !_busy,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _transferType,
                  label: l10n.dispositionFieldTransferType,
                  prefixIcon: Icons.category_outlined,
                  enabled: !_busy,
                ),
              ],
              if (_isAviary) ...[
                const SizedBox(height: AppSpacing.md),
                _AviaryPicker(
                  value: _aviaryId,
                  enabled: !_busy,
                  onChanged: (id) => setState(() => _aviaryId = id),
                ),
              ],
              if (_isEuthanized) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _vet,
                  label: l10n.dispositionFieldVet,
                  prefixIcon: Icons.local_hospital_outlined,
                  enabled: !_busy,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _reason,
                label: l10n.dispositionFieldReason,
                prefixIcon: Icons.notes_outlined,
                enabled: !_busy,
              ),
              if (_showVetSignoff) ...[
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.dispositionVetSignedOff),
                  value: _vetSignedOff,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _vetSignedOff = v),
                ),
              ],
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
                label: l10n.dispositionSaveAction,
                icon: Icons.check,
                isLoading: _busy,
                onPressed: _save,
              ),
              if (_isEditing) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    l10n.dispositionDeleteAction,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviary selector for the "placed in aviary" outcome (FED-4.12): a required
/// dropdown of the org's active aviaries.
class _AviaryPicker extends ConsumerWidget {
  const _AviaryPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final aviaries =
        ref.watch(activeAviariesProvider).value ?? const <Aviary>[];

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.dispositionFieldAviary,
        prefixIcon: const Icon(Icons.holiday_village_outlined),
      ),
      items: [
        for (final a in aviaries)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      validator: (v) => v == null ? l10n.fieldRequired : null,
      onChanged: enabled ? onChanged : null,
    );
  }
}

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create/edit an aviary (FED-6.1). Coordinators/supervisors only (the server
/// rules enforce it). Pass [aviary] to edit, omit to create.
Future<void> showAviaryFormSheet(
  BuildContext context, {
  Aviary? aviary,
}) => showAppSheet<void>(
  context,
  builder: (_) => _AviaryFormSheet(aviary: aviary),
);

class _AviaryFormSheet extends ConsumerStatefulWidget {
  const _AviaryFormSheet({this.aviary});

  final Aviary? aviary;

  @override
  ConsumerState<_AviaryFormSheet> createState() => _AviaryFormSheetState();
}

class _AviaryFormSheetState extends ConsumerState<_AviaryFormSheet>
    with DiscardGuard {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;
  late String? _keeperId;
  late bool _active;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.aviary;
    _name = TextEditingController(text: a?.name ?? '');
    _location = TextEditingController(text: a?.location ?? '');
    _capacity = TextEditingController(text: a?.capacity?.toString() ?? '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _keeperId = a?.keeper;
    _active = a?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _capacity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(aviariesRepositoryProvider.future);
      final me = await ref.read(currentUserProvider.future);
      final capacity = int.tryParse(_capacity.text.trim());
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'keeper': _keeperId ?? '',
        'location': _location.text.trim(),
        'capacity': capacity,
        'active': _active,
        'notes': _notes.text.trim(),
        'org': ?me?.org,
      };
      final existing = widget.aviary;
      if (existing == null) {
        await repo.create(body);
      } else {
        await repo.update(existing.id, body);
        ref.invalidate(aviaryByIdProvider(existing.id));
      }
      ref
        ..invalidate(aviariesProvider)
        ..invalidate(activeAviariesProvider);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final members = ref.watch(orgMembersProvider).value ?? const <AppUser>[];
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return guardUnsavedChanges(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + viewInsets,
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
                  widget.aviary == null
                      ? l10n.aviaryNewTitle
                      : l10n.aviaryEditTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.aviaryFieldName,
                  controller: _name,
                  autofocus: widget.aviary == null,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.fieldRequired
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String?>(
                  initialValue: _keeperId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.aviaryFieldKeeper,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(child: Text(l10n.aviaryKeeperNone)),
                    for (final m in members)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(memberLabel(m)),
                      ),
                  ],
                  onChanged: (id) => setState(() => _keeperId = id),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.aviaryFieldLocation,
                  controller: _location,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.aviaryFieldCapacity,
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: l10n.aviaryFieldNotes,
                  controller: _notes,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.aviaryFieldActive),
                  value: _active,
                  onChanged: (v) {
                    setState(() => _active = v);
                    markDirty();
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  onPressed: _busy ? null : _save,
                  isLoading: _busy,
                  label: l10n.aviarySaveAction,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

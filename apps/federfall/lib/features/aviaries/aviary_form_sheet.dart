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
    with DiscardGuard, FormSheetState {
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;
  late String? _keeperId;
  late bool _active;

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
    if (isBusy || !(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (_, org) = await requireUserOrg();
      final repo = await ref.read(aviariesRepositoryProvider.future);
      final capacity = int.tryParse(_capacity.text.trim());
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        // Non-null once validate() has passed; sending it unset anyway draws
        // the server's own required-field error rather than skipping silently.
        'keeper': _keeperId,
        'location': _location.text.trim(),
        'capacity': capacity,
        'active': _active,
        'notes': _notes.text.trim(),
      };
      final existing = widget.aviary;
      if (existing == null) {
        // `org` on create only: 1700000083 froze it, and its update rule
        // refuses a body that so much as mentions the field (federfall-t7ad —
        // resending the unchanged value 404s the whole edit).
        await repo.create({...body, 'org': org});
      } else {
        await repo.update(existing.id, body);
        ref.invalidate(aviaryByIdProvider(existing.id));
      }
      ref
        ..invalidate(aviariesProvider)
        ..invalidate(activeAviariesProvider);
    });
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final members = ref.watch(orgMembersProvider).value ?? const <AppUser>[];

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: widget.aviary == null
            ? l10n.aviaryNewTitle
            : l10n.aviaryEditTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        saveLabel: l10n.aviarySaveAction,
        onSave: _save,
        children: [
          AppTextField(
            label: l10n.aviaryFieldName,
            controller: _name,
            autofocus: widget.aviary == null,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
          ),
          const SizedBox(height: AppSpacing.md),
          // Required since 1700000076 (federfall-q7ks.1): the keeper is who
          // answers for this enclosure's residents, so there is no "none"
          // option to pick any more.
          DropdownButtonFormField<String>(
            initialValue: _keeperId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.aviaryFieldKeeper,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final m in members)
                DropdownMenuItem(value: m.id, child: Text(memberLabel(m))),
            ],
            validator: (v) => v == null ? l10n.fieldRequired : null,
            onChanged: (id) => setState(() => _keeperId = id),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(label: l10n.aviaryFieldLocation, controller: _location),
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
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
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
        ],
      ),
    );
  }
}

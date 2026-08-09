import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the apply/edit-marking form. Markings belong to [animalId]; when
/// applied during a treatment episode, [caseId] records it (null when managed
/// directly on the animal, e.g. an aviary resident with no open case).
Future<bool?> showMarkingSheet(
  BuildContext context, {
  required String animalId,
  String? caseId,
  Marking? marking,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => MarkingSheet(
      animalId: animalId,
      caseId: caseId,
      marking: marking,
    ),
  );
}

/// Form for applying or editing a ring/marker/chip (FED-4.10): type, code,
/// colour, issuing scheme and the date applied.
class MarkingSheet extends ConsumerStatefulWidget {
  const MarkingSheet({
    required this.animalId,
    this.caseId,
    this.marking,
    super.key,
  });

  final String animalId;
  final String? caseId;
  final Marking? marking;

  @override
  ConsumerState<MarkingSheet> createState() => _MarkingSheetState();
}

class _MarkingSheetState extends ConsumerState<MarkingSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _code;
  late final TextEditingController _colour;
  late final TextEditingController _scheme;

  /// Selected marking-type id, or null until the picker is populated / chosen.
  late String? _type;
  late DateTime _appliedAt;
  late bool _presentAtFind;

  /// The date the user had picked before ticking "present when found", so
  /// unticking gives it back rather than leaving the find moment behind.
  DateTime? _dateBeforeFind;

  bool get _isEditing => widget.marking != null;

  @override
  void initState() {
    super.initState();
    final m = widget.marking;
    _code = TextEditingController(text: m?.code ?? '');
    _colour = TextEditingController(text: m?.colour ?? '');
    _scheme = TextEditingController(text: m?.schemeOrg ?? '');
    // Editing keeps the marking's current type; new markings default once the
    // active code list loads (see build).
    _type = m?.type;
    _appliedAt = (m?.appliedAt ?? m?.created)?.toLocal() ?? DateTime.now();
    _presentAtFind = m?.presentAtFind ?? false;
  }

  /// Where a marking the bird already carried belongs in time. Both intake
  /// dates are optional on `cases`, so this falls through to the case's own
  /// creation rather than refusing to answer.
  DateTime? _findMoment(Case? c) =>
      c == null ? null : (c.foundAt ?? c.admittedAt ?? c.created);

  /// Ticking the box is what snapshots the find moment into [_appliedAt] —
  /// every reader of a marking orders on that date and none of them can see
  /// the flag, so it has to stay a real date. Re-saving an untouched marking
  /// therefore keeps the date it was stored with, even if the case's find date
  /// has since been corrected.
  void _setPresentAtFind({required bool value, required DateTime? findMoment}) {
    setState(() {
      _presentAtFind = value;
      if (value) {
        _dateBeforeFind = _appliedAt;
        if (findMoment != null) _appliedAt = findMoment.toLocal();
      } else if (_dateBeforeFind case final previous?) {
        _appliedAt = previous;
      }
    });
    markDirty();
  }

  @override
  void dispose() {
    for (final c in [_code, _colour, _scheme]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initial: _appliedAt);
    if (picked != null) {
      setState(() => _appliedAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(markingsRepositoryProvider.future);
      final body = <String, dynamic>{
        'type': _type,
        'code': trimToNull(_code) ?? '',
        'colour': trimToNull(_colour) ?? '',
        'scheme_org': trimToNull(_scheme) ?? '',
        'applied_at': _appliedAt.toUtc().toIso8601String(),
        'present_at_find': _presentAtFind,
      };

      final marking = widget.marking;
      if (marking == null) {
        await repo.create({
          ...body,
          'animal': widget.animalId,
          'applied_in_case': ?widget.caseId,
          'applied_by': user.id,
          'is_active': true,
          'org': org,
        });
      } else {
        await repo.update(marking.id, body);
      }

      ref.invalidate(markingsForAnimalProvider(widget.animalId));
      if (widget.caseId case final caseId?) {
        ref.invalidate(caseBundleProvider(caseId));
      }
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Only a case carries a find moment; the sheet also opens straight off an
    // animal (an aviary resident with no open case), where there is nothing to
    // anchor to and the option has no meaning.
    final caseId = widget.caseId;
    final findMoment = caseId == null
        ? null
        : _findMoment(ref.watch(caseByIdProvider(caseId)).value);

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.markingEditTitle : l10n.markingNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          _MarkingTypeField(
            selected: _type,
            enabled: !isBusy,
            onChanged: (id) => setState(() => _type = id),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _code,
            label: l10n.markingFieldCode,
            prefixIcon: Icons.tag,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _colour,
            label: l10n.markingFieldColour,
            prefixIcon: Icons.palette_outlined,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _scheme,
            label: l10n.markingFieldScheme,
            prefixIcon: Icons.business_outlined,
            enabled: !isBusy,
          ),
          if (caseId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.markingFieldPresentAtFind),
              subtitle: Text(l10n.markingFieldPresentAtFindHelp),
              value: _presentAtFind,
              // Until the case resolves there is no date to snapshot.
              onChanged: isBusy || findMoment == null
                  ? null
                  : (v) => _setPresentAtFind(
                      value: v ?? false,
                      findMoment: findMoment,
                    ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.markingFieldApplied,
            value: _appliedAt,
            // The find moment owns the date while the box is ticked; it still
            // shows, so it is visible WHICH date is being recorded.
            enabled: !isBusy && !_presentAtFind,
            onPick: _pickDate,
          ),
        ],
      ),
    );
  }
}

/// The marking-type picker, populated from the live `marking_types` code list.
/// New markings auto-select the first active type; editing keeps the marking's
/// current type even if it has since been deactivated.
class _MarkingTypeField extends ConsumerWidget {
  const _MarkingTypeField({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final decoration = InputDecoration(
      labelText: l10n.markingFieldType,
      prefixIcon: const Icon(Icons.sell_outlined),
    );

    return switch (ref.watch(markingTypesProvider)) {
      AsyncData(:final value) => Builder(
        builder: (context) {
          final options = value
              .where((t) => t.active || t.id == selected)
              .toList(growable: false);
          // Auto-select the first active type for a new marking once loaded.
          if (selected == null && options.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onChanged(options.first.id);
            });
          }
          return DropdownButtonFormField<String>(
            initialValue: options.any((t) => t.id == selected)
                ? selected
                : null,
            decoration: decoration,
            items: [
              for (final t in options)
                DropdownMenuItem(value: t.id, child: Text(t.label)),
            ],
            validator: (v) => v == null ? l10n.fieldRequired : null,
            onChanged: enabled ? onChanged : null,
          );
        },
      ),
      AsyncError() => InputDecorator(
        decoration: decoration,
        child: Text(l10n.errorGenericTitle),
      ),
      _ => DropdownButtonFormField<String>(
        decoration: decoration,
        items: const [],
        onChanged: null,
      ),
    };
  }
}

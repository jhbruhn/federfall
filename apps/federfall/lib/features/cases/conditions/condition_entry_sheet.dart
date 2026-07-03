import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the diagnosis add/edit form as a modal bottom sheet. Pass [entry] to
/// edit; [initialLabel] pre-fills the condition field with a code-list entry's
/// resolved label (the caller already knows it). Resolves to `true` on save.
Future<bool?> showConditionEntrySheet(
  BuildContext context, {
  required String caseId,
  CaseCondition? entry,
  String? initialLabel,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => ConditionEntrySheet(
      caseId: caseId,
      entry: entry,
      initialLabel: initialLabel,
    ),
  );
}

/// Form for recording or editing a diagnosis (FED-4.5). The condition field is
/// a type-ahead over the active code list that falls back to free text: the
/// final text is matched against the code list on save — an exact label match
/// is stored as a `condition` relation, anything else as `free_text`.
class ConditionEntrySheet extends ConsumerStatefulWidget {
  const ConditionEntrySheet({
    required this.caseId,
    this.entry,
    this.initialLabel,
    super.key,
  });

  final String caseId;
  final CaseCondition? entry;
  final String? initialLabel;

  @override
  ConsumerState<ConditionEntrySheet> createState() =>
      _ConditionEntrySheetState();
}

class _ConditionEntrySheetState extends ConsumerState<ConditionEntrySheet>
    with DiscardGuard, FormSheetState {
  final _notesController = TextEditingController();

  /// The condition field's controller, owned by the [Autocomplete].
  TextEditingController? _conditionController;

  late Certainty _certainty;
  late DateTime _onsetAt;
  DateTime? _resolvedAt;

  bool get _isEditing => widget.entry != null;

  String get _initialText =>
      widget.entry?.freeText ?? widget.initialLabel ?? '';

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _notesController.text = entry?.notes ?? '';
    _certainty = entry?.certainty ?? Certainty.suspected;
    _onsetAt =
        (entry?.onsetDate ?? entry?.created)?.toLocal() ?? DateTime.now();
    _resolvedAt = entry?.resolvedDate?.toLocal();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickOnset() async {
    final picked = await pickDate(context, initial: _onsetAt);
    if (picked != null) {
      setState(() => _onsetAt = picked);
      markDirty();
    }
  }

  Future<void> _pickResolved() async {
    final picked = await pickDate(context, initial: _resolvedAt ?? _onsetAt);
    if (picked != null) {
      setState(() => _resolvedAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (_, org) = await requireUserOrg();

      final text = _conditionController?.text.trim() ?? '';
      // Match the final text against the code list; an exact (case-insensitive)
      // label hit is stored as a relation, otherwise as free text.
      final all = await ref.read(conditionsProvider.future);
      final match = all
          .where((c) => c.label.toLowerCase() == text.toLowerCase())
          .firstOrNull;
      final notes = _notesController.text.trim();
      final resolvedIso = _resolvedAt?.toUtc().toIso8601String();

      final repo = await ref.read(caseConditionsRepositoryProvider.future);
      final entry = widget.entry;

      final body = <String, dynamic>{
        'condition': match?.id,
        'free_text': match == null ? text : '',
        'certainty': _certainty.wire,
        'onset_date': _onsetAt.toUtc().toIso8601String(),
        'resolved_date': resolvedIso ?? '',
        'notes': notes,
      };

      if (entry == null) {
        await repo.create({
          ...body,
          'case': widget.caseId,
          'org': org,
        });
      } else {
        await repo.update(entry.id, body);
      }

      ref.invalidate(caseBundleProvider(widget.caseId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active =
        ref.watch(conditionsProvider).value?.where((c) => c.active).toList() ??
        const <Condition>[];

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.conditionEditTitle : l10n.conditionNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          Autocomplete<Condition>(
            initialValue: TextEditingValue(text: _initialText),
            displayStringForOption: (c) => c.label,
            optionsBuilder: (value) {
              final q = value.text.trim().toLowerCase();
              if (q.isEmpty) return const Iterable<Condition>.empty();
              return active.where((c) => c.label.toLowerCase().contains(q));
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  _conditionController = controller;
                  return AppTextField(
                    controller: controller,
                    focusNode: focusNode,
                    label: l10n.conditionFieldName,
                    hintText: l10n.conditionFieldHint,
                    prefixIcon: Icons.coronavirus_outlined,
                    enabled: !isBusy,
                    validator: Validators.required(l10n),
                  );
                },
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<Certainty>(
            segments: [
              ButtonSegment(
                value: Certainty.suspected,
                label: Text(l10n.certaintySuspected),
              ),
              ButtonSegment(
                value: Certainty.confirmed,
                label: Text(l10n.certaintyConfirmed),
              ),
            ],
            selected: {_certainty},
            onSelectionChanged: isBusy
                ? null
                : (s) {
                    setState(() => _certainty = s.first);
                    markDirty();
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.conditionFieldOnset,
            value: _onsetAt,
            enabled: !isBusy,
            onPick: _pickOnset,
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.conditionFieldResolved,
            value: _resolvedAt,
            enabled: !isBusy,
            onPick: _pickResolved,
            onClear: () {
              setState(() => _resolvedAt = null);
              markDirty();
            },
            placeholder: l10n.caseDateNotSet,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _notesController,
            label: l10n.conditionFieldNotes,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}

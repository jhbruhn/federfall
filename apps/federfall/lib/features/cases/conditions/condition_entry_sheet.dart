import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
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

class _ConditionEntrySheetState extends ConsumerState<ConditionEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  /// The condition field's controller, owned by the [Autocomplete].
  TextEditingController? _conditionController;

  late Certainty _certainty;
  late DateTime _onsetAt;
  DateTime? _resolvedAt;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.entry != null;

  String get _initialText =>
      widget.entry?.freeText ?? widget.initialLabel ?? '';

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _notesController.text = entry?.notes ?? '';
    _certainty = entry?.certainty ?? Certainty.suspected;
    _onsetAt = entry?.onsetDate ?? entry?.created ?? DateTime.now();
    _resolvedAt = entry?.resolvedDate;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickOnset() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _onsetAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _onsetAt = picked);
  }

  Future<void> _pickResolved() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _resolvedAt ?? _onsetAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _resolvedAt = picked);
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

      ref.invalidate(caseConditionsForCaseProvider(widget.caseId));
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final active = ref.watch(conditionsProvider).value
            ?.where((c) => c.active)
            .toList() ??
        const <Condition>[];

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
                _isEditing ? l10n.conditionEditTitle : l10n.conditionNewTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Autocomplete<Condition>(
                initialValue: TextEditingValue(text: _initialText),
                displayStringForOption: (c) => c.label,
                optionsBuilder: (value) {
                  final q = value.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<Condition>.empty();
                  return active
                      .where((c) => c.label.toLowerCase().contains(q));
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
                    enabled: !_busy,
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
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _certainty = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                label: l10n.conditionFieldOnset,
                value: _onsetAt,
                enabled: !_busy,
                onPick: _pickOnset,
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                label: l10n.conditionFieldResolved,
                value: _resolvedAt,
                enabled: !_busy,
                onPick: _pickResolved,
                onClear: () => setState(() => _resolvedAt = null),
                placeholder: l10n.caseDateNotSet,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _notesController,
                label: l10n.conditionFieldNotes,
                prefixIcon: Icons.notes_outlined,
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
                label: l10n.actionSave,
                icon: Icons.check,
                isLoading: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable date row with an optional clear action for nullable dates.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
    this.onClear,
    this.placeholder,
  });

  final String label;
  final DateTime? value;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final text = value == null
        ? (placeholder ?? '')
        : materialL10n.formatMediumDate(value!);
    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: value != null && enabled && onClear != null
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

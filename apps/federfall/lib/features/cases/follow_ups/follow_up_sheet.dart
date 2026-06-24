import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/follow_ups/follow_ups_providers.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the schedule-recheck add/edit form. Pass [followUp] to edit.
Future<bool?> showFollowUpSheet(
  BuildContext context, {
  required String caseId,
  FollowUp? followUp,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FollowUpSheet(caseId: caseId, followUp: followUp),
  );
}

/// Form for scheduling a recheck on a case (cr3.4): a due date plus an optional
/// note. The recheck surfaces on the carer worklist when due.
class FollowUpSheet extends ConsumerStatefulWidget {
  const FollowUpSheet({required this.caseId, this.followUp, super.key});

  final String caseId;
  final FollowUp? followUp;

  @override
  ConsumerState<FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends ConsumerState<FollowUpSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _note;
  late DateTime _dueAt;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.followUp != null;

  @override
  void initState() {
    super.initState();
    final f = widget.followUp;
    _note = TextEditingController(text: f?.note ?? '');
    _dueAt = f?.dueAt?.toLocal() ?? DateTime.now();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _dueAt = picked);
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
      final repo = await ref.read(followUpsRepositoryProvider.future);
      final note = _note.text.trim();
      final body = <String, dynamic>{
        'due_at': _dueAt.toUtc().toIso8601String(),
        'note': note,
      };

      final existing = widget.followUp;
      if (existing == null) {
        await repo.create({
          ...body,
          'case': widget.caseId,
          'created_by': user.id,
          'org': org,
        });
      } else {
        await repo.update(existing.id, body);
      }

      ref
        ..invalidate(followUpsForCaseProvider(widget.caseId))
        ..invalidate(worklistProvider);
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
                _isEditing ? l10n.followUpEditTitle : l10n.followUpNewTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              DateField(
                label: l10n.followUpDueLabel,
                value: _dueAt,
                enabled: !_busy,
                onPick: _pickDate,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _note,
                label: l10n.followUpNoteLabel,
                prefixIcon: Icons.notes_outlined,
                enabled: !_busy,
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

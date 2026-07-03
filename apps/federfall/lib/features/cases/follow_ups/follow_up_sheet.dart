import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the schedule-recheck add/edit form. Pass [followUp] to edit.
Future<bool?> showFollowUpSheet(
  BuildContext context, {
  required String caseId,
  FollowUp? followUp,
}) {
  return showAppSheet<bool>(
    context,
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

class _FollowUpSheetState extends ConsumerState<FollowUpSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _note;
  late DateTime _dueAt;

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
    final picked = await pickDate(
      context,
      initial: _dueAt,
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) {
      setState(() => _dueAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
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
        ..invalidate(caseBundleProvider(widget.caseId))
        ..invalidate(worklistSourceProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.followUpEditTitle : l10n.followUpNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DateField(
            label: l10n.followUpDueLabel,
            value: _dueAt,
            enabled: !isBusy,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _note,
            label: l10n.followUpNoteLabel,
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

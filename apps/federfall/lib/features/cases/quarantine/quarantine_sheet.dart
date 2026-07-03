import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a freshly-imposed quarantine runs by default (matches the 14-day
/// intake default the cases hook applies).
const _defaultQuarantine = Duration(days: 14);

/// Opens the quarantine add/edit form as a modal bottom sheet (federfall-uvm).
/// Pass [entry] to edit an existing quarantine. Resolves to `true` on save.
Future<bool?> showQuarantineSheet(
  BuildContext context, {
  required String caseId,
  Quarantine? entry,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => QuarantineSheet(caseId: caseId, entry: entry),
  );
}

/// Form for imposing, extending or lifting quarantine: a required end date, an
/// optional start date (when it was imposed — its place on the chronology) and
/// an optional reason. To end quarantine early, set the end date to today.
class QuarantineSheet extends ConsumerStatefulWidget {
  const QuarantineSheet({required this.caseId, this.entry, super.key});

  final String caseId;
  final Quarantine? entry;

  @override
  ConsumerState<QuarantineSheet> createState() => _QuarantineSheetState();
}

class _QuarantineSheetState extends ConsumerState<QuarantineSheet>
    with DiscardGuard, FormSheetState {
  final _reasonController = TextEditingController();

  late DateTime _until;
  late DateTime _setAt;
  String? _dateError;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    final now = DateTime.now();
    _reasonController.text = entry?.reason ?? '';
    _setAt = (entry?.setAt ?? entry?.created)?.toLocal() ?? now;
    _until = entry?.until?.toLocal() ?? now.add(_defaultQuarantine);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickSetAt() async {
    final picked = await pickDate(context, initial: _setAt);
    if (picked != null) {
      setState(() {
        _setAt = picked;
        _dateError = null;
      });
      markDirty();
    }
  }

  Future<void> _pickUntil() async {
    final picked = await pickDate(
      context,
      initial: _until,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _until = picked;
        _dateError = null;
      });
      markDirty();
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    // Ending on the day quarantine was imposed is fine (that's how it is
    // lifted early); only an end strictly before the start is nonsense.
    if (DateUtils.dateOnly(_until).isBefore(DateUtils.dateOnly(_setAt))) {
      setState(() => _dateError = l10n.fieldEndBeforeStart);
      return;
    }

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();

      final body = <String, dynamic>{
        'set_at': _setAt.toUtc().toIso8601String(),
        'quarantine_until': _until.toUtc().toIso8601String(),
        'reason': _reasonController.text.trim(),
      };

      final repo = await ref.read(quarantineRepositoryProvider.future);
      final entry = widget.entry;
      if (entry == null) {
        await repo.create({
          ...body,
          'case': widget.caseId,
          'set_by': user.id,
          'org': org,
        });
      } else {
        await repo.update(entry.id, body);
      }

      ref
        ..invalidate(caseBundleProvider(widget.caseId))
        ..invalidate(caseQuarantineUntilProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.quarantineEditTitle : l10n.quarantineNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DateField(
            label: l10n.quarantineFieldStart,
            value: _setAt,
            enabled: !isBusy,
            onPick: _pickSetAt,
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.caseFieldQuarantineUntil,
            value: _until,
            enabled: !isBusy,
            errorText: _dateError,
            onPick: _pickUntil,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _reasonController,
            label: l10n.quarantineFieldReason,
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

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
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
    with DiscardGuard {
  final _reasonController = TextEditingController();

  late DateTime _until;
  late DateTime _setAt;
  bool _busy = false;
  String? _error;
  String? _dateError;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    final now = DateTime.now();
    _reasonController.text = entry?.reason ?? '';
    _setAt = entry?.setAt ?? entry?.created ?? now;
    _until = entry?.until ?? now.add(_defaultQuarantine);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickSetAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _setAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _setAt = picked;
        _dateError = null;
      });
      markDirty();
    }
  }

  Future<void> _pickUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _until,
      firstDate: DateTime(2000),
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
        ..invalidate(quarantineForCaseProvider(widget.caseId))
        ..invalidate(caseQuarantineUntilProvider);
      if (mounted) Navigator.of(context).pop(true);
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
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return guardUnsavedChanges(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + viewInsets,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? l10n.quarantineEditTitle
                    : l10n.quarantineNewTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                label: l10n.quarantineFieldStart,
                value: _setAt,
                enabled: !_busy,
                onPick: _pickSetAt,
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                label: l10n.caseFieldQuarantineUntil,
                value: _until,
                enabled: !_busy,
                errorText: _dateError,
                onPick: _pickUntil,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _reasonController,
                label: l10n.quarantineFieldReason,
                enabled: !_busy,
                onChanged: (_) => markDirty(),
                minLines: 2,
                maxLines: 5,
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

/// A tappable date row (no clear action — both quarantine dates are required).
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
    this.errorText,
  });

  final String label;
  final DateTime value;
  final bool enabled;
  final String? errorText;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          errorText: errorText,
        ),
        child: Text(materialL10n.formatMediumDate(value)),
      ),
    );
  }
}

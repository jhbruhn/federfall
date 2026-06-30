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

/// Create or edit a condition code-list entry (UX Phase A, supervisor only).
/// Resolves to `true` if the list changed so the caller can refresh.
Future<bool?> showConditionCodelistSheet(
  BuildContext context, {
  Condition? condition,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => ConditionCodelistSheet(condition: condition),
  );
}

class ConditionCodelistSheet extends ConsumerStatefulWidget {
  const ConditionCodelistSheet({this.condition, super.key});

  final Condition? condition;

  @override
  ConsumerState<ConditionCodelistSheet> createState() =>
      _ConditionCodelistSheetState();
}

class _ConditionCodelistSheetState extends ConsumerState<ConditionCodelistSheet>
    with DiscardGuard {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _description;
  late bool _notifiable;
  late bool _active;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.condition != null;

  @override
  void initState() {
    super.initState();
    final c = widget.condition;
    _label = TextEditingController(text: c?.label ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _notifiable = c?.isNotifiable ?? false;
    _active = c?.active ?? true;
  }

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(conditionsRepositoryProvider.future);
      final body = <String, dynamic>{
        'label': _label.text.trim(),
        'description': _description.text.trim(),
        'is_notifiable': _notifiable,
        'active': _active,
      };
      final existing = widget.condition;
      if (existing == null) {
        final me = await ref.read(currentUserProvider.future);
        await repo.create({...body, 'org': ?me?.org});
      } else {
        await repo.update(existing.id, body);
      }
      ref.invalidate(conditionsProvider);
      if (!mounted) return;
      navigator.pop(true);
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

    return guardUnsavedChanges(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.sm,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            onChanged: markDirty,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEditing
                      ? l10n.conditionCodelistEditTitle
                      : l10n.conditionCodelistNewTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _label,
                  label: l10n.conditionLabelLabel,
                  prefixIcon: Icons.label_outline,
                  enabled: !_busy,
                  validator: Validators.required(l10n),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _description,
                  label: l10n.conditionDescriptionLabel,
                  prefixIcon: Icons.notes_outlined,
                  enabled: !_busy,
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.conditionNotifiableLabel),
                  subtitle: Text(l10n.conditionNotifiableHelp),
                  value: _notifiable,
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() => _notifiable = v);
                          markDirty();
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.conditionActiveLabel),
                  subtitle: Text(l10n.conditionActiveHelp),
                  value: _active,
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() => _active = v);
                          markDirty();
                        },
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
                const SizedBox(height: AppSpacing.md),
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
      ),
    );
  }
}

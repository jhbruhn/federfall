import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create or edit a medication-route code-list entry (supervisor only).
/// Resolves to `true` if the list changed so the caller can refresh.
Future<bool?> showMedicationRouteCodelistSheet(
  BuildContext context, {
  MedicationRoute? route,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => MedicationRouteCodelistSheet(route: route),
  );
}

class MedicationRouteCodelistSheet extends ConsumerStatefulWidget {
  const MedicationRouteCodelistSheet({this.route, super.key});

  final MedicationRoute? route;

  @override
  ConsumerState<MedicationRouteCodelistSheet> createState() =>
      _MedicationRouteCodelistSheetState();
}

class _MedicationRouteCodelistSheetState
    extends ConsumerState<MedicationRouteCodelistSheet>
    with DiscardGuard {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late bool _active;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.route != null;

  @override
  void initState() {
    super.initState();
    final r = widget.route;
    _label = TextEditingController(text: r?.label ?? '');
    _active = r?.active ?? true;
  }

  @override
  void dispose() {
    _label.dispose();
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
      final repo = await ref.read(medicationRoutesRepositoryProvider.future);
      final body = <String, dynamic>{
        'label': _label.text.trim(),
        'active': _active,
      };
      final existing = widget.route;
      if (existing == null) {
        final me = await ref.read(currentUserProvider.future);
        await repo.create({...body, 'org': ?me?.org});
      } else {
        await repo.update(existing.id, body);
      }
      ref.invalidate(medicationRoutesProvider);
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
                      ? l10n.medicationRouteCodelistEditTitle
                      : l10n.medicationRouteCodelistNewTitle,
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
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.conditionActiveLabel),
                  subtitle: Text(l10n.medicationRouteActiveHelp),
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

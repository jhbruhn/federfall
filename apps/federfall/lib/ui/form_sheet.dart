import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:federfall/ui/widgets/primary_button.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mixin for a create/edit sheet's [ConsumerState]: owns the busy/error pair
/// and [formKey], plus [requireUserOrg] and [runSave] — the byte-identical
/// org guard and `_save()` try/catch tail every sheet repeated. Pair with the
/// `DiscardGuard` mixin for the unsaved-changes guard and [SheetScaffold] for
/// the surrounding layout (see e.g. `weight_entry_sheet.dart`).
mixin FormSheetState<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Owned so sheets don't each declare `final _formKey = GlobalKey<...>()`.
  final formKey = GlobalKey<FormState>();

  bool _busy = false;
  String? _error;

  bool get isBusy => _busy;
  String? get saveError => _error;

  /// Shows [message] in the same slot [runSave] uses, for a validation check
  /// that must run before the try/catch (e.g. a cross-field rule `Form`
  /// validators can't express).
  void setSaveError(String message) => setState(() => _error = message);

  /// Resolves the signed-in user and their org, or fails with the
  /// [RepositoryException] every sheet throws before writing without one.
  Future<(AppUser user, String org)> requireUserOrg() async {
    final user = await ref.read(currentUserProvider.future);
    final org = user?.org;
    if (user == null || org == null) {
      throw const RepositoryException('no org for current user');
    }
    return (user, org);
  }

  /// Runs [action] under the shared busy/error lifecycle. On success, [isBusy]
  /// is left true — the caller pops the sheet next. On a [RepositoryException]
  /// its message is shown; any other error is reported via
  /// [reportCaughtError] and shown as a generic message. Either failure clears
  /// [isBusy]. Returns whether [action] completed without error.
  Future<bool> runSave(Future<void> Function() action) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } on RepositoryException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(l10n, e);
        });
      }
      return false;
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.errorGenericTitle;
        });
      }
      return false;
    }
  }
}

/// The padding/scroll/Form/title/error-slot/save-button shell every
/// create/edit sheet hand-rolled. Wrap the returned widget in
/// `guardUnsavedChanges` (from the `DiscardGuard` mixin); [children] are the
/// sheet's own fields.
///
/// [formKey], [isBusy] and [error] normally come straight from a
/// [FormSheetState] mixed into the same state, and [onSave] from its
/// `_save()`. [trailing] renders below the save button (e.g. disposition's
/// delete action).
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    required this.title,
    required this.formKey,
    required this.onFormChanged,
    required this.children,
    required this.isBusy,
    required this.error,
    required this.onSave,
    this.saveLabel,
    this.trailing = const [],
    super.key,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final VoidCallback onFormChanged;
  final List<Widget> children;
  final bool isBusy;
  final String? error;
  final VoidCallback onSave;

  /// Defaults to the generic "Save" label.
  final String? saveLabel;

  /// Extra widgets rendered after the save button.
  final List<Widget> trailing;

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
          key: formKey,
          onChanged: onFormChanged,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              ...children,
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: saveLabel ?? l10n.actionSave,
                icon: Icons.check,
                isLoading: isBusy,
                onPressed: onSave,
              ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Trims a controller's text, returning null for an empty result — the
/// `_trim` helper every sheet with optional text fields repeated.
String? trimToNull(TextEditingController controller) {
  final value = controller.text.trim();
  return value.isEmpty ? null : value;
}

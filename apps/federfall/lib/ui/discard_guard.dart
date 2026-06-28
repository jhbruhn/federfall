import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Asks the user to confirm throwing away unsaved form input. Resolves to
/// `true` when they choose to discard, `false` when they keep editing (or
/// dismiss the dialog).
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final l10n = context.l10n;
  final discard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.discardChangesTitle),
      content: Text(l10n.discardChangesMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.discardKeepEditing),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.discardConfirm),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Mixin for a create/edit sheet's [State] that guards against losing unsaved
/// input on an accidental dismissal.
///
/// A modal bottom sheet can close several ways; this guards the two that
/// [PopScope] can intercept — the Android back button/gesture and a tap on the
/// scrim outside the sheet (both route through [Navigator.maybePop]). A
/// swipe-down drag-to-dismiss calls [Navigator.pop] directly and so cannot be
/// intercepted by [PopScope] (a Flutter limitation); it is intentionally left
/// unguarded rather than disabling the drag affordance everywhere.
///
/// Wiring (see e.g. `weight_entry_sheet.dart`):
/// * mix in on the sheet's [State];
/// * give the form `Form(onChanged: markDirty, ...)` so text edits flip the
///   flag, and call [markDirty] from non-form changes (date picks, dropdown
///   selections, staged photos);
/// * wrap the body returned from [build] in [guardUnsavedChanges].
mixin DiscardGuard<T extends StatefulWidget> on State<T> {
  bool _dirty = false;

  /// Whether the form holds unsaved edits.
  bool get isDirty => _dirty;

  /// Marks the form dirty. Idempotent, and rebuilds once on the clean→dirty
  /// edge so [PopScope.canPop] stays current. Call from a field's change
  /// callback — never from within [build].
  void markDirty() {
    if (_dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  /// Clears the dirty flag — call after a successful save when the sheet stays
  /// open. Most sheets pop on save, so this is rarely needed.
  void resetDirty() {
    if (!_dirty || !mounted) return;
    setState(() => _dirty = false);
  }

  /// Wraps [child] so a back gesture or scrim tap prompts to discard while
  /// [isDirty]. Use it around the sheet body returned from [build].
  Widget guardUnsavedChanges({required Widget child}) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await confirmDiscardChanges(context) && mounted) {
          navigator.pop();
        }
      },
      child: child,
    );
  }
}

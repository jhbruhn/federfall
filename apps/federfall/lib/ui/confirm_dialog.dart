import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// A cancel/confirm dialog, resolving to false when it is dismissed.
///
/// One spelling of a pair this app had written four times by hand, all four
/// with the same defect: the theme used to give every [FilledButton] an
/// infinite minimum width, so the confirm took the dialog's whole action bar
/// and pushed Cancel onto a line of its own (federfall-78k6.9). That is fixed
/// at the source now — the theme's default is Material's, and `PrimaryButton`
/// carries its own full width — so this no longer has to correct anything. It
/// stays because the pair, its Cancel label and its dismissed-means-false
/// contract are worth having in one place.
///
/// Not for a dialog that destroys something: `confirmAndDelete` and
/// `DestructiveDialog` own that, and their confirm carries weight and colour
/// the safe route must not borrow.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

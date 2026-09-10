import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// A cancel/confirm dialog, resolving to false when it is dismissed.
///
/// Exists because a bare `FilledButton` cannot be used in an [AlertDialog] in
/// this app. `AppTheme`'s `filledButtonTheme` gives every one of them
/// `minimumSize: Size.fromHeight(48)` — an *infinite* minimum width — which is
/// what makes `PrimaryButton` fill a form and is load-bearing for the twelve
/// forms built on it. In an action row it is wrong: the confirm button takes
/// the dialog's whole width, which overflows the row and drops Cancel onto a
/// line of its own, so the pair reads as a small text link stranded above a
/// full-width slab instead of two buttons side by side.
///
/// So the confirm button gets its natural width back, scoped to the dialog.
/// Use this rather than hand-rolling the pair — every hand-rolled one in this
/// app had the same defect (federfall-78k6.9).
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
          style: FilledButton.styleFrom(minimumSize: kNaturalButtonSize),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

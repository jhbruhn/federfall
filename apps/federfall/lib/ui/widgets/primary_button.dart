import 'package:flutter/material.dart';

/// Full-width primary action button with a built-in busy state.
///
/// When [isLoading] is true the label is replaced by a spinner and the button
/// is disabled, so callers don't have to juggle that wiring per form.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    super.key,
  });

  /// Button text.
  final String label;

  /// Tap handler; ignored while [isLoading]. Pass null to disable.
  final VoidCallback? onPressed;

  /// Shows a spinner and disables the button when true.
  final bool isLoading;

  /// Optional leading icon (hidden while loading).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);

    final onTap = isLoading ? null : onPressed;

    if (icon != null && !isLoading) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: child,
      );
    }
    return FilledButton(onPressed: onTap, child: child);
  }
}

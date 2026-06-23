import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Centered error state with an icon, message and optional retry button. Used
/// by `AsyncValueView` and anywhere a load/action fails.
class ErrorView extends StatelessWidget {
  const ErrorView({this.message, this.onRetry, super.key});

  /// The user-facing message; falls back to a generic localized title.
  final String? message;

  /// When non-null, a retry button is shown that invokes this.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message ?? l10n.errorGenericTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.actionRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

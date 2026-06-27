import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:federfall/ui/widgets/primary_button.dart';
import 'package:flutter/material.dart';

/// Centered empty-state placeholder for lists/collections with no items yet.
///
/// Beyond the icon + message it can carry a [title] headline and a primary
/// [actionLabel]/[onAction] call-to-action, so an empty list doubles as the
/// entry point for creating the first item instead of reading as a dead end.
class EmptyView extends StatelessWidget {
  const EmptyView({
    this.message,
    this.title,
    this.icon,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    super.key,
  });

  /// Optional headline shown above [message] for a stronger empty state.
  final String? title;

  /// Overrides the generic localized empty message.
  final String? message;

  /// Optional leading icon.
  final IconData? icon;

  /// Label for the primary call-to-action. The button appears only when both
  /// this and [onAction] are set.
  final String? actionLabel;

  /// Optional leading icon for the call-to-action button.
  final IconData? actionIcon;

  /// Tap handler for the call-to-action.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasAction = actionLabel != null && onAction != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A soft tinted disc lifts the icon off the page so the empty state
            // reads as intentional rather than as a blank screen.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? Icons.inbox_outlined,
                size: 40,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              message ?? context.l10n.emptyGeneric,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (hasAction) ...[
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                icon: actionIcon,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

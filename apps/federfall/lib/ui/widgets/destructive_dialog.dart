import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// What the user picked in a [DestructiveDialog].
enum DestructiveChoice {
  /// Backed out — nothing happens.
  cancel,

  /// Went ahead with the destructive action.
  confirm,

  /// Took the reversible way out offered alongside it
  /// ([DestructiveDialog.alternativeLabel]).
  alternative,
}

/// A confirmation that enumerates what is about to be destroyed before offering
/// the button that destroys it.
///
/// [bullets] pair each line with whether it is a warning (rendered in the error
/// colour). The counts they state should be **awaited** by the caller, not read
/// off an `AsyncValue.value` snapshot — a dialog whose whole job is to state
/// the damage truthfully must not render "no cases" because a provider happened
/// to still be loading.
///
/// Two of the three actions are optional, which covers the three shapes the app
/// needs:
///
/// - destroy or back out — [confirmLabel] only (animal / case delete);
/// - destroy, take a safer route, or back out — both labels, with the
///   alternative as the *primary* button (a code-list entry that is still
///   referenced: delete blanks it on those records, deactivating keeps them
///   readable);
/// - the destructive action is impossible, so only explain and offer the
///   alternative — [confirmLabel] null (a marking type in use: PocketBase
///   refuses the delete because the relation is required).
class DestructiveDialog extends StatelessWidget {
  const DestructiveDialog({
    required this.title,
    required this.intro,
    required this.bullets,
    this.confirmLabel,
    this.alternativeLabel,
    this.closingNote,
    super.key,
  });

  final String title;
  final String intro;

  /// Each consequence as its own line; `isWarning` renders it in the error
  /// colour, bold.
  final List<(String text, bool isWarning)> bullets;

  /// Label of the destructive action. Omit when it cannot be offered at all —
  /// the dialog then has no way to return [DestructiveChoice.confirm].
  final String? confirmLabel;

  /// Label of the reversible alternative. When set it becomes the primary
  /// (filled) button, so the safe route carries the visual weight.
  final String? alternativeLabel;

  /// Closing line under the bullets, in the error colour — e.g. "This cannot
  /// be undone." Omit where nothing irreversible is on offer.
  final String? closingNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(intro),
          const SizedBox(height: AppSpacing.sm),
          for (final (text, isWarning) in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '• $text',
                style: isWarning
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      )
                    : theme.textTheme.bodyMedium,
              ),
            ),
          if (closingNote case final note?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(DestructiveChoice.cancel),
          child: Text(l10n.actionCancel),
        ),
        if (confirmLabel case final label?)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(DestructiveChoice.confirm),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(label),
          ),
        // Last, so it lands in the primary (trailing) position.
        if (alternativeLabel case final label?)
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(DestructiveChoice.alternative),
            child: Text(label),
          ),
      ],
    );
  }
}

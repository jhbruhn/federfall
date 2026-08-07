import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The extra row below the last item of a keyset-paged list: the next page
/// arriving, or the reason it did not.
///
/// A failure has to be visible and recoverable *here*, at the end of the list.
/// It is the only place it shows, and a list the reader believes they have
/// reached the bottom of is worse than one that says it stopped
/// (federfall-ia9n). Shared by every paged feed — the audit log, the case
/// browser and the animals registry — so they all stop the same way.
class PagedListTail extends StatelessWidget {
  const PagedListTail({required this.onRetry, this.error, super.key});

  /// Why the last page failed, or null while one is simply in flight.
  final Object? error;

  /// Tries that page again, from the same cursor.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = error;
    if (failure == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        spacing: AppSpacing.sm,
        children: [
          Text(
            loadErrorMessage(l10n, failure),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.actionRetry),
          ),
        ],
      ),
    );
  }
}

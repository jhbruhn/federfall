import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Centered loading indicator with an optional label. The default async/empty
/// loading state across the app.
class LoadingView extends StatelessWidget {
  const LoadingView({this.label, super.key});

  /// Overrides the default "loading…" label. Pass an empty string to hide it.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? context.l10n.loadingLabel;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (text.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

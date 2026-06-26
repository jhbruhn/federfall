import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A muted "👤 Name" line naming the active carer of a case (federfall-127).
///
/// Resolves [carerId] to a display name via [orgMembersByIdProvider]; renders
/// nothing while the members load or when the id is unknown, so callers can
/// include it unconditionally once they know an id is present. Used in the
/// cases list, the prior-/other-cases lists and the case detail header so the
/// carer is named consistently wherever a case is shown.
class CarerLine extends ConsumerWidget {
  const CarerLine(this.carerId, {super.key});

  /// The carer's user id (a non-empty `active_carer` relation value).
  final String carerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(orgMembersByIdProvider).value?[carerId];
    if (user == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: context.l10n.placementFieldCarer,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 16, color: muted),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              memberLabel(user),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

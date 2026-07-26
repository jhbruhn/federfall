import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// A small icon in a soft tonal square — the shared "section icon" language
/// used by the KPI tiles and the dashboard's Today card (and echoing the
/// empty-state disc).
class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: colors.onPrimaryContainer),
    );
  }
}

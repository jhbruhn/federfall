import 'package:federfall/features/home/account_actions.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// Animals tab of the navigation shell (FED-7.0). Placeholder until the animals
/// registry lands in FED-7.5.
class AnimalsScreen extends StatelessWidget {
  const AnimalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.animalsTitle),
        actions: const [AccountActions()],
      ),
      body: EmptyView(
        icon: Icons.pets_outlined,
        message: l10n.animalsComingSoon,
      ),
    );
  }
}

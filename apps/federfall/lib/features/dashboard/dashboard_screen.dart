import 'package:federfall/features/home/account_actions.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// Dashboard tab of the navigation shell (FED-7.0). Placeholder until the
/// dashboard widgets land in FED-7.1.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle),
        actions: const [AccountActions()],
      ),
      body: EmptyView(
        icon: Icons.dashboard_outlined,
        message: l10n.dashboardComingSoon,
      ),
    );
  }
}

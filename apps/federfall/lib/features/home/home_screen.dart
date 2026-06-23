import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Authenticated app shell / landing. Placeholder for FED-2.4; role-gated
/// navigation and the dashboard arrive in FED-3.3 / Phase 7.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appName)),
      body: Center(child: Text(l10n.appName)),
    );
  }
}

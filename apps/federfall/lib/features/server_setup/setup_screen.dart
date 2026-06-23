import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// Native-only first-run screen where the user enters their Federfall server
/// URL. Placeholder gate target for FED-2.4; the validate-and-persist flow is
/// built in FED-3.0.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text('Server-Einrichtung (FED-3.0)'),
        ),
      ),
    );
  }
}

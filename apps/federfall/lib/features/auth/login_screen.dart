import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// Sign-in screen. Placeholder gate target for FED-2.4; the email/password
/// login and session wiring is built in FED-3.1.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anmelden')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text('Anmeldung (FED-3.1)'),
        ),
      ),
    );
  }
}

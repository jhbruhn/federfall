import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// Shown while the router resolves server config and auth status. The redirect
/// gate replaces it with /setup, /login or the home shell once those settle.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingView());
  }
}

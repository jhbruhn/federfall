import 'package:federfall/config/app_environment.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Flavored name (e.g. "[DEV] Federfall") for the window/tab title.
      title: AppEnvironment.appName,
      theme: ThemeData(
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePlaceholder(),
    );
  }
}

/// Temporary landing page until routing + the auth gate land in Phase 2/3
/// (FED-2.4 router, FED-3.0 server config, FED-3.1 login).
class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appName)),
      body: Center(child: Text(l10n.appName)),
    );
  }
}

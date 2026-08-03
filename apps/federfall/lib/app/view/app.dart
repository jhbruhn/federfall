import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/scanner/hardware_scan_listener.dart';
import 'package:federfall/features/reminders/reminders.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/router.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate the (lazy) reminder reconciler for the app's lifetime: listen
    // rather than watch, so its rebuilds never rebuild the MaterialApp. Same
    // shape for hardware-scanner deep links below (federfall-gdp8).
    ref
      ..listen(remindersProvider, (_, _) {})
      ..listen(hardwareScanListenerProvider, (_, _) {});
    return MaterialApp.router(
      // Root of the state-restoration tree. Paired with the
      // `restorationScopeId` on GoRouter and the branch/shell/list-detail
      // routes (routing/router.dart, federfall-7ev8), this restores which
      // screen was open after Android reclaims the process — go_router's native
      // restoration, not a manual last-route write.
      restorationScopeId: 'app',
      // Flavored name (e.g. "[DEV] Federfall") for the window/tab title.
      title: AppEnvironment.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follow the device's language preference (federfall-qdsa). German is the
      // design language and stays the fallback for anything we don't ship —
      // see `resolveAppLocale`.
      localeListResolutionCallback: (locales, _) => resolveAppLocale(locales),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      // Above the router, so the offline strip is one instance for the whole
      // app: it holds its position across every navigation, and it reaches the
      // routes pushed outside the navigation shell (intake wizard, admin,
      // login) that a per-shell banner would miss.
      builder: (context, child) => OfflineNotice(child: child!),
    );
  }
}

import 'package:federfall/config/app_environment.dart';
import 'package:federfall/features/reminders/medication_reminders.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/router.dart';
import 'package:federfall/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate the (lazy) reminder reconciler for the app's lifetime: listen
    // rather than watch, so its rebuilds never rebuild the MaterialApp.
    ref.listen(medicationRemindersProvider, (_, _) {});
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
      // German is the design language; English stays available for development.
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

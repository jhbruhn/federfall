import 'dart:async';
import 'dart:developer';

import 'package:federfall/routing/url_strategy/url_strategy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  // Clean path-based URLs on the web (no-op on native).
  configureUrlStrategy();

  runApp(
    ProviderScope(
      child: await builder(),
    ),
  );
}

import 'dart:async';

import 'package:federfall/config/zugvogel_bindings.dart';

/// Flutter runs this around every test in the package, which is the only hook
/// that reaches all of them.
///
/// It exists for one reason: zugvogel's providers need a [PbClientConfig], and
/// 86 test files build their own `ProviderScope` — none of which has anything
/// to do with which server this app talks to. Setting the default once here
/// keeps every one of those tests unaware that the config exists, while a test
/// that genuinely wants a different one still overrides
/// `pbClientConfigProvider` in its own scope and wins.
///
/// The production counterpart is the same line in `bootstrap()`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  defaultPbClientConfig = federfallPbClientConfig();
  await testMain();
}

import 'dart:async';

import 'package:federfall/config/zugvogel_bindings.dart';
import 'package:federfall/l10n/federfall_strings.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart';

/// Flutter runs this around every test in the package, which is the only hook
/// that reaches all of them.
///
/// It exists for two bindings the library cannot supply for itself, and that
/// no narrower seam reaches.
///
/// zugvogel's providers need a [PbClientConfig], and 86 test files build their
/// own `ProviderScope` — none of which has anything to do with which server
/// this app talks to. The shared widgets need a [ZugvogelStrings], and 69 test
/// files build their own `MaterialApp` — none of which is about which words a
/// button shows. Setting both defaults once here keeps every one of those tests
/// unaware that either binding exists, while a test that genuinely wants a
/// different one still overrides `pbClientConfigProvider`, or wraps its subtree
/// in a `ZugvogelStringsScope`, and wins.
///
/// The production counterpart is the same two lines in `bootstrap()`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  defaultPbClientConfig = federfallPbClientConfig();
  defaultZugvogelStrings = (context) => FederfallStrings(context.l10n);
  await testMain();
}

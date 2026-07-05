import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'case_deep_link.g.dart';

/// Wires `federfall://case/<caseNumber>` links (the case-report PDF's QR
/// code, federfall-gdp8) to in-app navigation.
///
/// A custom scheme, not an Android App Link / iOS Universal Link — see
/// `case_report.pb.js`'s comment on the QR for why: this app's server address
/// is chosen per-install at runtime (native `ServerConfigController`), so
/// there is no single fixed domain a shared app build could ever verify a
/// platform App Link against.
///
/// Started once from the app root (`ref.listen` in `app.dart`, mirroring
/// `medicationRemindersProvider`) and kept alive for the rest of the session.
/// go_router's own auth/setup gate (`_gate` in router.dart) already preserves
/// a deep-linked target through login/setup — "a shared /cases/abc link opens
/// that case after sign-in instead of the default landing tab" — so this only
/// has to resolve the human-readable case number to a real case id and call
/// `.go()`; the gate gets to it from there like any other navigation.
@Riverpod(keepAlive: true)
class CaseDeepLinkListener extends _$CaseDeepLinkListener {
  @override
  Future<void> build() async {
    final appLinks = AppLinks();
    final subscription = appLinks.uriLinkStream.listen(
      _handle,
      onError: _onLinkError,
    );
    ref.onDispose(subscription.cancel);

    // The intent/URL that cold-launched the app doesn't arrive on
    // uriLinkStream (that's only for links opened while already running) —
    // app_links surfaces it separately.
    final initial = await appLinks.getInitialLink();
    if (initial != null) await _handle(initial);
  }

  // A plain tearoff of `reportCaughtError` doesn't type-check as a stream
  // `onError` handler: `Function.onError` only accepts exactly `void
  // Function(Object)` or `void Function(Object, StackTrace)`, and
  // `reportCaughtError`'s optional `context` param disqualifies it.
  void _onLinkError(Object error, StackTrace stackTrace) =>
      reportCaughtError(error, stackTrace);

  Future<void> _handle(Uri uri) async {
    if (uri.scheme != 'federfall' || uri.host != 'case') return;
    if (uri.pathSegments.isEmpty) return;
    final caseNumber = uri.pathSegments.first;
    try {
      final repo = await ref.read(casesRepositoryProvider.future);
      final medicalCase = await repo.byCaseNumber(caseNumber);
      // Not found (wrong org/instance, deleted case, ...) — silently do
      // nothing rather than a dead-end error screen; the case number is
      // still visible as plain text on the printed report as a manual
      // fallback (look it up in the app, or call the shelter).
      if (medicalCase == null) return;
      ref.read(routerProvider).go(AppRoutes.caseDetail(medicalCase.id));
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
    }
  }
}

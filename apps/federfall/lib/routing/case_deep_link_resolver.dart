import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Translates a `federfall://case/<caseNumber>` deep link (the case-report
/// PDF's QR code, federfall-gdp8) into a real in-app location, or `null` if
/// [uri] isn't one of these.
///
/// Shared by two entry points that both end up with the same string: the
/// phone-camera path (a platform intent, resolved via go_router's own
/// redirect — see the comment on its call site in `router.dart` for why it's
/// wired in there rather than via a separate listener) and the hardware
/// barcode-scanner path (`core/scanner/`, which has no such platform-intent
/// hook to piggyback on and calls `router.go()` directly with this result).
Future<String?> resolveCaseDeepLink(Ref ref, Uri uri) async {
  if (uri.scheme != 'federfall' || uri.host != 'case') return null;
  if (uri.pathSegments.isEmpty) return AppRoutes.home;
  final caseNumber = uri.pathSegments.first;
  try {
    final repo = await ref.read(casesRepositoryProvider.future);
    final medicalCase = await repo.byCaseNumber(caseNumber);
    // Not found (wrong org/instance, deleted case, ...) — land on the home
    // tab rather than a dead-end error screen; the case number is still
    // visible as plain text on the printed report as a manual fallback.
    return medicalCase == null
        ? AppRoutes.home
        : AppRoutes.caseDetail(medicalCase.id);
  } on Object catch (error, stackTrace) {
    reportCaughtError(error, stackTrace);
    return AppRoutes.home;
  }
}

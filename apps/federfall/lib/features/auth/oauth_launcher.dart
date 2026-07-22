import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// The deep link an OAuth2 provider redirects back to on mobile, for the manual
/// code-exchange flow (`AuthRepository.signInWithOAuth2Code`).
///
/// It MUST be registered as an allowed redirect URI with the provider (see
/// docs/DEPLOYMENT.md). The matching Android intent filter lives in
/// `android/app/src/main/AndroidManifest.xml` (scheme `federfall`, host
/// `oauth-callback` — deliberately a *different* host from the `federfall://case`
/// QR deep links so the two never collide). iOS needs no registration:
/// ASWebAuthenticationSession captures the scheme itself.
const oauthRedirectUrl = 'federfall://oauth-callback';

/// Opens [authorizationUrl] in an in-app browser tab (Custom Tab / AuthTab on
/// Android, SFSafariViewController on iOS) and resolves with the full callback
/// URL once the provider redirects back to [oauthRedirectUrl].
///
/// The tab keeps ownership of the redirect and hands the result straight back
/// here, so — unlike the realtime "all-in-one" flow — it does not matter that
/// the app was backgrounded meanwhile. Throws a `PlatformException` with code
/// `CANCELED` if the user dismisses the browser.
///
/// Known cosmetic wart: with flutter_web_auth_2 5.x's AuthTab flow, a browser
/// that doesn't implement AuthTab's auto-close (notably Firefox, incl. current
/// versions) leaves a spent, empty tab behind after the redirect — sign-in
/// still completes, the user just has to dismiss the leftover tab. We accept
/// it: the
/// pre-AuthTab 4.x line closed cleanly but launches from an application context
/// (needs FLAG_ACTIVITY_NEW_TASK) and doesn't build against the current Kotlin
/// toolchain, so it traded one bug for worse ones. No options are passed
/// (`preferEphemeral` off) so the provider page reuses an existing browser IdP
/// login (SSO).
Future<String> authenticateOAuth(Uri authorizationUrl) {
  return FlutterWebAuth2.authenticate(
    url: authorizationUrl.toString(),
    callbackUrlScheme: Uri.parse(oauthRedirectUrl).scheme,
  );
}

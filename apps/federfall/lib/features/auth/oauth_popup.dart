import 'package:federfall/features/auth/oauth_popup_io.dart'
    if (dart.library.js_interop) 'package:federfall/features/auth/oauth_popup_web.dart'
    as impl;

/// A browser window opened **synchronously during a tap** on the web, to be
/// navigated to the OAuth2 provider URL once the SDK has produced it.
///
/// Safari (and every browser on iOS, which is Safari underneath) blocks
/// `window.open` unless it runs inside the call stack of a user gesture.
/// PocketBase's realtime OAuth2 flow opens the provider window only *after*
/// awaiting `listAuthMethods` + the realtime connect, so a window opened there
/// is treated as an unsolicited popup and blocked — the sign-in page never
/// appears. Opening a blank window up front (inside the tap) and merely
/// *navigating* it later sidesteps the blocker, because pointing an
/// already-open window at a URL needs no gesture.
///
/// Off the web this is a no-op: native/desktop have no such popup blocker.
abstract interface class OAuthPopup {
  /// Points the pre-opened window at [url].
  void navigateTo(Uri url);

  /// Closes the window if it is still open — used when the flow fails or is
  /// cancelled before the provider's redirect page closes it itself.
  void closeIfOpen();
}

/// Opens a blank popup now, or returns `null` off the web (and if the browser
/// refused even inside the gesture) so the caller can fall back to a normal
/// launch.
OAuthPopup? openBlankOAuthPopup() => impl.openBlankOAuthPopup();

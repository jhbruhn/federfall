import 'package:federfall/features/auth/oauth_popup.dart';
import 'package:web/web.dart' as web;

/// Opens a blank, named window synchronously (see [OAuthPopup]). Returns `null`
/// if the browser refused even inside the gesture, so the caller can fall back.
OAuthPopup? openBlankOAuthPopup() {
  final window = web.window.open('', 'federfall_oauth');
  return window == null ? null : _WindowOAuthPopup(window);
}

class _WindowOAuthPopup implements OAuthPopup {
  _WindowOAuthPopup(this._window);

  final web.Window _window;

  @override
  void navigateTo(Uri url) => _window.location.href = url.toString();

  @override
  void closeIfOpen() => _window.close();
}

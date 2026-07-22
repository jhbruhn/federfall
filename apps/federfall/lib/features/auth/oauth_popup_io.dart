import 'package:federfall/features/auth/oauth_popup.dart';

/// Native/desktop have no browser popup blocker to appease, so nothing is
/// pre-opened and the caller uses its normal launch path.
OAuthPopup? openBlankOAuthPopup() => null;

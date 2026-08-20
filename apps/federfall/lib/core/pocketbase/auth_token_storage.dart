// Auth-token storage now lives in zugvogel_pb_client (eiermann-d2a.4).
//
// The storage KEY is injected now — see config/zugvogel_bindings.dart. It was
// the literal 'federfall.auth'; two Zugvogel apps must never share one, because
// on web they can be served from the same host and the token belongs to the
// origin that issued it.
//
// Read PrefsAuthTokenStorage's header before changing the web CSP: that policy
// is load-bearing for this decision, not defence in depth.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show
        AuthTokenStorage,
        PrefsAuthTokenStorage,
        SecureAuthTokenStorage,
        authTokenStorageProvider;

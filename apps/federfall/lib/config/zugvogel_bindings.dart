import 'package:federfall/config/app_environment.dart';
import 'package:federfall/config/map_config.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart';

// The config type itself, so a test can build a variant of it (a probe that
// tolerates plain http, say) without importing the package directly.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show PbClientConfig, defaultPbClientConfig;

/// Everything zugvogel needs to know about *this* app.
///
/// The library holds no configuration and reads no compile-time define
/// (injection boundary 3), so every environment value it uses arrives from
/// here. This is the one place in federfall that maps `AppEnvironment` onto
/// zugvogel's seams — a second one would be a second answer to "which server?".
PbClientConfig federfallPbClientConfig() => PbClientConfig(
  // Derives the /api/federfall/info route, the identity marker the client
  // requires before accepting a server, and the `federfall.auth` /
  // `federfall.serverUrl` storage keys. All three have to agree, which is why
  // they come from one field.
  service: 'federfall',
  fallbackServerName: 'Federfall',
  mapFallback: mapConfigFromDefines(),
  webBaseUrlOverride: AppEnvironment.pocketbaseUrlOverride,
  // http:// sends the bearer token in cleartext, so it is only tolerated on a
  // non-loopback host in development — where reaching a plain-http PocketBase
  // on the LAN is the point. Loopback is always allowed regardless.
  allowInsecureHttp: AppEnvironment.flavor == AppFlavor.development,
);

/// The overrides every `ProviderScope` in this app must carry.
///
/// `pbClientConfigProvider` throws until overridden, deliberately: a
/// silently-wrong service name would point every request at the wrong /info
/// route and store the auth payload under the wrong key, which is far harder to
/// notice than a startup failure.
List<Override> zugvogelOverrides() => [
  pbClientConfigProvider.overrideWithValue(federfallPbClientConfig()),
];

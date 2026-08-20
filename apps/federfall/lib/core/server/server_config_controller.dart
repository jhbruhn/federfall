// ServerConfigController now lives in zugvogel_pb_client (eiermann-d2a.4).
//
// Same resolution rules: on web the serving origin (or the build-time override,
// now passed in as PbClientConfig.webBaseUrlOverride); on native the persisted
// URL, or unconfigured so first run lands on the setup screen. Changing the URL
// still purges the persisted auth payload, because a token belongs to the
// origin that issued it.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show ServerConfigController, serverConfigControllerProvider;

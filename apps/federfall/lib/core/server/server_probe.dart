// ServerProbe now lives in zugvogel_pb_client (eiermann-d2a.4).
//
// ProbeNotFederfall is ProbeWrongService there: the marker it checks is the
// configured service name, so the case covers a generic PocketBase, an
// unrelated 200, AND the other Zugvogel app's server.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show
        ProbeInsecureHttp,
        ProbeInvalidUrl,
        ProbeReachable,
        ProbeUnreachable,
        ProbeWrongService,
        ServerInfoProber,
        ServerProbe,
        ServerProbeResult,
        normalizeServerUrl,
        serverProbeProvider;

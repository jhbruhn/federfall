// The User-Agent client now lives in zugvogel_pb_client (eiermann-d2a.4).
//
// The product name is injected (PbClientConfig.userAgentName, defaulting to the
// service) rather than the hardcoded 'federfall/$version' it was.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show
        UserAgentClient,
        appVersionProvider,
        loadAppVersion,
        loadUserAgent,
        userAgentProvider;

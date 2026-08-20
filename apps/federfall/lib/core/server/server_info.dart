// ServerInfo now lives in zugvogel_pb_client (eiermann-d2a.4).
//
// tryParse takes the service name now instead of hardcoding the federfall
// marker — which is what makes pointing this app at eiermann's backend a clean
// 'not this server' rather than a client half-working against the wrong schema.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show ServerAuthOptions, ServerInfo, ServerMapConfig;

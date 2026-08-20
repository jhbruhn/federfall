// The PocketBase client provider now lives in zugvogel_pb_client
// (eiermann-d2a.4). Its base URL comes from ServerConfigController and its auth
// store writes through AuthTokenStorage, exactly as before.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show ServerNotConfiguredException, pocketBaseProvider;

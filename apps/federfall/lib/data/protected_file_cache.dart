// The protected-file cache now lives in zugvogel_pb_client (eiermann-d2a.4),
// with its cache key injected — it was the literal 'federfallProtectedFiles',
// and two apps on one device must not share a store that holds different
// users' files.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show ProtectedFileCacheManager, fileCacheKey;

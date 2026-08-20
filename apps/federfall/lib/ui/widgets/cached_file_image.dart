// CachedFileImage now lives in zugvogel_ui (eiermann-d2a.10), and fileCacheKey
// in zugvogel_pb_client (eiermann-d2a.4) beside the protected-file cache
// manager it keys — stripping the `token` query param is a fact about
// PocketBase's file URLs, not about this widget.
//
// Both are re-exported here so the ~dozen call sites and the key's own test
// keep the import they already had.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart' show fileCacheKey;
export 'package:zugvogel_ui/zugvogel_ui.dart' show CachedFileImage;

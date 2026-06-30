import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// A [CacheManager] for PocketBase **Protected** file fields (FED-8.1).
///
/// Protected files are only served with a short-lived `?token=`
/// (`pb.files.getToken()`, ~2min TTL). Rather than baking that token into the
/// image URL — which forces every widget to wait on a token mint before it can
/// even render an already-*cached* image — this manager appends the token
/// lazily, inside the file service, only when an actual download happens (a
/// cache miss). Cache hits never touch the token at all, so previously
/// downloaded images appear instantly.
///
/// Bytes are keyed on the token-free URL (callers pass that as both the image
/// URL and the cache key), so a rotated token reuses the stored file.
class ProtectedFileCacheManager extends CacheManager {
  ProtectedFileCacheManager({
    required Future<String> Function() tokenProvider,
  }) : super(
         Config(
           cacheKey,
           fileService: _ProtectedFileService(tokenProvider: tokenProvider),
         ),
       );

  /// Name of the on-device cache store (sqlite db + file dir) for these files.
  static const cacheKey = 'federfallProtectedFiles';
}

/// Mints a fresh file token and appends it to each request URL at fetch time,
/// so the token is only needed when bytes are actually downloaded.
class _ProtectedFileService extends HttpFileService {
  _ProtectedFileService({required this.tokenProvider});

  final Future<String> Function() tokenProvider;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final token = await tokenProvider();
    final base = Uri.parse(url);
    final withToken = base.replace(
      queryParameters: {...base.queryParameters, 'token': token},
    );
    return super.get(withToken.toString(), headers: headers);
  }
}

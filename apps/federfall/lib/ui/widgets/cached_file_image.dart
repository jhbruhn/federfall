import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cache key for a PocketBase file URL, with the short-lived `token` query
/// param stripped (FED-8.1 / 49l.1).
///
/// Protected file URLs carry a `?token=` that rotates every ~90s (see
/// `fileTokenProvider`); keying the image cache on the full URL would make
/// every rotation look like a brand-new image and re-download it. Keying on the
/// token-free identity instead lets the cache (memory + disk) reuse the bytes
/// across rotations, while the server's own `Cache-Control` still governs
/// freshness (PocketBase sends a long `max-age`, so we honour it rather than
/// refetching on open).
String fileCacheKey(Uri url) {
  final params = {...url.queryParameters}..remove('token');
  final base = '${url.origin}${url.path}';
  if (params.isEmpty) return base;
  final query = params.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
  return '$base?$query';
}

/// A cached image for a protected PocketBase file [url] (already carrying its
/// access token). Caches by [fileCacheKey] so a rotated token reuses the bytes,
/// and falls back to a broken-image placeholder on error.
class CachedFileImage extends StatelessWidget {
  const CachedFileImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    super.key,
  });

  final Uri url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Shown when the image fails to load; defaults to a broken-image tile.
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url.toString(),
      cacheKey: fileCacheKey(url),
      width: width,
      height: height,
      fit: fit,
      errorWidget: (context, _, _) =>
          errorWidget ??
          Container(
            width: width,
            height: height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
    );
  }
}

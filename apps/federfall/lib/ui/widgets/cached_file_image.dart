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
///
/// Retries a failed load a few times before giving up (federfall-q4d):
/// PocketBase generates a `?thumb=` lazily on the first request, so the very
/// first fetch of a *just-uploaded* file's thumbnail can fail — and
/// `cached_network_image` does not retry on its own, leaving the tile blank
/// until it happens to rebuild (e.g. a manual pull-to-refresh). On error we
/// evict the entry and re-request with a short backoff, only showing the
/// broken-image placeholder once the retries are exhausted.
class CachedFileImage extends StatefulWidget {
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

  /// Shown when the image fails to load (after retries); defaults to a
  /// broken-image tile.
  final Widget? errorWidget;

  @override
  State<CachedFileImage> createState() => _CachedFileImageState();
}

class _CachedFileImageState extends State<CachedFileImage> {
  /// How many times to re-request before showing the error placeholder.
  static const _maxRetries = 3;

  int _attempt = 0;
  bool _retryPending = false;

  @override
  void didUpdateWidget(CachedFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different target (not just a rotated token, which keeps the same cache
    // key) starts a fresh retry budget.
    if (fileCacheKey(oldWidget.url) != fileCacheKey(widget.url)) {
      _attempt = 0;
      _retryPending = false;
    }
  }

  void _scheduleRetry() {
    if (_retryPending || _attempt >= _maxRetries) return;
    _retryPending = true;
    final next = _attempt + 1;
    // Grow the backoff (~0.5s, 1s, 1.5s) to give the server time to finish
    // generating the thumbnail.
    Future.delayed(Duration(milliseconds: 500 * next), () async {
      // Drop the failed entry so the rebuild re-requests it rather than
      // replaying the cached error.
      await CachedNetworkImage.evictFromCache(
        widget.url.toString(),
        cacheKey: fileCacheKey(widget.url),
      );
      if (!mounted) return;
      setState(() {
        _attempt = next;
        _retryPending = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CachedNetworkImage(
      // Bump the key on each retry so the widget re-resolves the image.
      key: ValueKey(_attempt),
      imageUrl: widget.url.toString(),
      cacheKey: fileCacheKey(widget.url),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorWidget: (context, _, _) {
        if (_attempt < _maxRetries) {
          _scheduleRetry();
          // Stay neutral while retrying instead of flashing the broken icon.
          return Container(
            width: widget.width,
            height: widget.height,
            color: theme.colorScheme.surfaceContainerHighest,
          );
        }
        return widget.errorWidget ??
            Container(
              width: widget.width,
              height: widget.height,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            );
      },
    );
  }
}

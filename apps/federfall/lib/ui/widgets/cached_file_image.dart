import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/'
    'cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:federfall/data/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cache key for a PocketBase file URL, with any `token` query param stripped
/// (FED-8.1 / 49l.1).
///
/// Callers pass token-free URLs (the token is appended lazily at download time
/// by the protected-file cache manager), but this defends against a token
/// leaking into the URL: keying the cache on the token-free identity lets the
/// cache (memory + disk) reuse the bytes across token rotations.
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

/// A cached image for a protected PocketBase file at the token-free [url].
///
/// Downloads go through [protectedFileCacheManagerProvider], which appends the
/// access token only when bytes are actually fetched — so a previously cached
/// image renders instantly, with no token round-trip. Caches by [fileCacheKey]
/// so a rotated token reuses the bytes, and falls back to a broken-image
/// placeholder on error.
///
/// Retries a failed load a few times before giving up (federfall-q4d):
/// PocketBase generates a `?thumb=` lazily on the first request, so the very
/// first fetch of a *just-uploaded* file's thumbnail can fail — and
/// `cached_network_image` does not retry on its own, leaving the tile blank
/// until it happens to rebuild (e.g. a manual pull-to-refresh). On error we
/// evict the entry and re-request with a short backoff, only showing the
/// broken-image placeholder once the retries are exhausted.
class CachedFileImage extends ConsumerStatefulWidget {
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
  ConsumerState<CachedFileImage> createState() => _CachedFileImageState();
}

class _CachedFileImageState extends ConsumerState<CachedFileImage> {
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
    // Captured now — the tile can be disposed during the backoff (thumbnails
    // scrolled off-screen), and ref must not be touched afterwards.
    final cacheManager = ref.read(protectedFileCacheManagerProvider);
    // Grow the backoff (~0.5s, 1s, 1.5s) to give the server time to finish
    // generating the thumbnail.
    Future.delayed(Duration(milliseconds: 500 * next), () async {
      // Drop the failed entry so the rebuild re-requests it rather than
      // replaying the cached error.
      await cacheManager.removeFile(fileCacheKey(widget.url));
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
    // Decode at display resolution, not the source's. These are small tiles
    // (avatars/thumbnails), but the cached file is a 200x200 thumb; decoding it
    // full-size wastes ~25x the RAM, so Flutter's decoded-image cache evicts
    // sooner and an already-on-disk image has to re-read + re-decode (a visible
    // "tiny bit to load" with no fade). Sizing the decode to the box keeps far
    // more tiles resident, so they render instantly.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int? decodePx(double? logical) =>
        logical == null ? null : (logical * dpr).round();

    return CachedNetworkImage(
      // Bump the key on each retry so the widget re-resolves the image.
      key: ValueKey(_attempt),
      cacheManager: ref.watch(protectedFileCacheManagerProvider),
      // On web, the default HtmlImage render path loads via the browser with
      // the raw URL, bypassing the cache manager (and our token-appending file
      // service) — so Protected files 403. HttpGet routes the fetch through the
      // cache manager on web too, which is also what appends the access token.
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      imageUrl: widget.url.toString(),
      cacheKey: fileCacheKey(widget.url),
      memCacheWidth: decodePx(widget.width),
      memCacheHeight: decodePx(widget.height),
      // CachedNetworkImage plays its placeholder cross-fade (default 500ms in /
      // 1s out) even on a cache hit, so an already-cached thumbnail visibly
      // "loads" for half a second. Zero the fades so cached images appear at
      // once; the brief fade adds nothing for these small tiles.
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
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

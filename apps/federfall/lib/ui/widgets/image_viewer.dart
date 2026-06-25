import 'dart:async';

import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

/// Opens the full-screen image viewer over [imageUrls], starting at
/// [initialIndex]: swipe between photos, pinch / double-tap to zoom, and share
/// the current one.
Future<void> showImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageViewerScreen(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
      ),
    ),
  );
}

/// Full-screen, swipeable image viewer with pinch + double-tap zoom and a share
/// action. Used wherever a record's photos are shown as thumbnails.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    required this.imageUrls,
    this.initialIndex = 0,
    super.key,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller;
  late int _index;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    try {
      final res = await http.get(Uri.parse(widget.imageUrls[_index]));
      if (res.statusCode != 200) {
        throw http.ClientException('status ${res.statusCode}');
      }
      final name = _filename(widget.imageUrls[_index]);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(res.bodyBytes, name: name, mimeType: _mime(name)),
          ],
          fileNameOverrides: [name],
        ),
      );
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.imageShareFailed)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _filename(String url) {
    final last = Uri.parse(url).pathSegments.lastOrNull ?? '';
    return last.isEmpty ? 'image' : last;
  }

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = widget.imageUrls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(total <= 1 ? '' : '${_index + 1} / $total'),
        actions: [
          if (_sharing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l10n.imageShareAction,
              onPressed: _share,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: total,
        itemBuilder: (_, i) => _ZoomableImage(url: widget.imageUrls[i]),
      ),
    );
  }
}

/// One page: an image that pinch-zooms (via [InteractiveViewer]) and toggles a
/// 2.5× zoom centred on the tapped point on double-tap.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.url});

  final String url;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  static const double _zoomScale = 2.5;

  final _transform = TransformationController();
  late final AnimationController _animation;
  Animation<Matrix4>? _zoomAnimation;
  TapDownDetails? _doubleTapDetails;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final value = _zoomAnimation?.value;
        if (value != null) _transform.value = value;
      });
  }

  @override
  void dispose() {
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// A uniform-scale + translation matrix without the deprecated
  /// `Matrix4.translate` / `scale` helpers (translation lives in column 3).
  Matrix4 _matrix(double scale, double tx, double ty) => Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(2, 2, scale)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);

  void _handleDoubleTap() {
    final Matrix4 end;
    if (_zoomed) {
      end = Matrix4.identity();
    } else {
      final p = _doubleTapDetails?.localPosition ?? Offset.zero;
      end = _matrix(
        _zoomScale,
        -p.dx * (_zoomScale - 1),
        -p.dy * (_zoomScale - 1),
      );
    }
    _zoomAnimation = Matrix4Tween(begin: _transform.value, end: end).animate(
      CurvedAnimation(parent: _animation, curve: Curves.easeOut),
    );
    unawaited(_animation.forward(from: 0));
    setState(() => _zoomed = !_zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: 5,
        child: Center(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}

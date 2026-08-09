import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_image/crop_image.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Re-encode quality for the cropped result. High enough that a portrait
/// survives a second JPEG generation without visible artefacts, low enough
/// that the upload stays a fraction of the original.
const _jpegQuality = 90;

/// Raw premultiplied RGBA pixels and their dimensions, as
/// [ui.Image.toByteData] hands them over.
typedef JpegEncodeRequest = ({Uint8List rgba, int width, int height});

/// Encodes raw RGBA pixels as JPEG. Top-level and synchronous so it can be
/// handed to [compute].
///
/// The pixels come from the engine, which already holds the picked photo
/// decoded (it is on screen). Re-decoding the original file in Dart instead
/// would cost hundreds of milliseconds to seconds for a phone photo — and on
/// web that would land squarely on the UI thread, since `compute` has no
/// isolate to run on there and falls back to running inline.
Uint8List encodeRgbaAsJpeg(JpegEncodeRequest request) {
  final image = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: request.rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: _jpegQuality);
}

/// Opens the full-screen crop step over [bytes] and resolves to the cropped
/// JPEG, or null if the user backed out.
///
/// Takes a [NavigatorState] rather than a `BuildContext` on purpose: callers
/// reach this straight after `pickImage`, and the camera can dispose the
/// calling element while it is in the foreground (Android backgrounds the
/// activity). A navigator captured before the pick survives that; a context
/// does not, and an unmounted one here would silently drop the photo.
///
/// [aspectRatio] locks the rectangle's shape (1 for a square); pass null to
/// let the user drag any shape. [circularPreview] outlines the circle the
/// result will be clipped to, for targets that render round.
Future<Uint8List?> showImageCropper(
  NavigatorState navigator, {
  required Uint8List bytes,
  double? aspectRatio,
  bool circularPreview = false,
}) {
  return navigator.push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageCropScreen(
        bytes: bytes,
        aspectRatio: aspectRatio,
        circularPreview: circularPreview,
      ),
    ),
  );
}

/// Full-screen crop step between picking a photo and uploading it. Pops with
/// the cropped JPEG bytes, or with null when dismissed.
class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({
    required this.bytes,
    this.aspectRatio,
    this.circularPreview = false,
    super.key,
  });

  /// The picked photo, still encoded as it came off the picker.
  final Uint8List bytes;

  /// Width / height the crop rectangle is held to, or null for free-form.
  final double? aspectRatio;

  /// Whether to outline the circle the result will be clipped to.
  final bool circularPreview;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  late final CropController _controller = CropController(
    aspectRatio: widget.aspectRatio,
    // Inset slightly rather than starting at the full frame, so the handles
    // are visible (and draggable inward) the moment the screen opens.
    defaultCrop: const Rect.fromLTRB(0.05, 0.05, 0.95, 0.95),
  );
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_working) return;
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    try {
      // The engine does the cropping, against the image it already has
      // decoded for display, at full resolution. That also settles the EXIF
      // orientation for free: what is on screen is upright, so the rectangle
      // the user drew needs no correction.
      final cropped = await _controller.croppedBitmap();
      final width = cropped.width;
      final height = cropped.height;
      // Defaults to ui.ImageByteFormat.rawRgba — naming it would trip
      // avoid_redundant_argument_values.
      final raw = await cropped.toByteData();
      cropped.dispose();
      if (raw == null) {
        throw StateError('cropped bitmap has no pixels');
      }
      final jpeg = await compute(encodeRgbaAsJpeg, (
        rgba: raw.buffer.asUint8List(),
        width: width,
        height: height,
      ));
      navigator.pop(jpeg);
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(l10n.imageCropFailed)));
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.imageCropTitle),
        actions: [
          if (_working)
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
            TextButton(onPressed: _apply, child: Text(l10n.actionSave)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: CropImage(
            controller: _controller,
            image: Image.memory(widget.bytes),
            alwaysShowThirdLines: true,
            overlayPainter: widget.circularPreview
                ? _CircleHint(_controller)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Outlines the circle a round target will clip the square crop to, so what
/// the user frames is what they get. Painted over the whole image, hence the
/// rectangle is derived from the controller's normalized crop each paint.
class _CircleHint extends CustomPainter {
  _CircleHint(this.controller) : super(repaint: controller);

  final CropController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final crop = controller.crop;
    canvas.drawOval(
      Rect.fromLTRB(
        crop.left * size.width,
        crop.top * size.height,
        crop.right * size.width,
        crop.bottom * size.height,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white70,
    );
  }

  // Repainting is driven by the controller passed to `super.repaint`.
  @override
  bool shouldRepaint(_CircleHint oldDelegate) => false;
}

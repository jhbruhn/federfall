import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Scroll-wheel zoom that steps whole zoom levels, as a [FlutterMap] child.
///
/// Replaces flutter_map's built-in wheel zoom, which is continuous: it adds
/// `scrollDelta.dy * scrollWheelVelocity` to the zoom, and one notch is a
/// fraction of a level (~0.27 with the stock velocity), so the camera lands
/// between integer zooms and essentially never on one.
///
/// That is what makes a raster map look soft. `TileLayer` fetches
/// `zoom.round()` and draws each 256px tile at `256 * 2^(zoom - round(zoom))`,
/// i.e. between 71% and 141% of native — and the upscaling half of that range
/// (rounding *down* to the tile zoom) is the blurry direction. A tile is
/// pixel-exact only at a whole zoom level, and at devicePixelRatio 1 there is
/// no denser physical grid to hide the resample, so sharpness visibly pulses as
/// you scroll. Stepping whole levels keeps the map at 1:1.
///
/// Deliberately scoped to the wheel: pinch-zoom stays continuous, because
/// snapping mid-gesture would fight the user's fingers, and the touch devices
/// that pinch are the high-density ones where the resample doesn't show.
///
/// Usage: drop into `FlutterMap.children` and remove
/// [InteractiveFlag.scrollWheelZoom] from the map's flags — otherwise
/// flutter_map's own handler runs too and re-introduces fractional zoom.
class MapWheelZoom extends StatefulWidget {
  const MapWheelZoom({super.key});

  @override
  State<MapWheelZoom> createState() => _MapWheelZoomState();

  /// Every interaction except the built-in wheel zoom, for the map's flags.
  static const int flags =
      InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom;
}

class _MapWheelZoomState extends State<MapWheelZoom> {
  /// Scroll delta seen since the last zoom step.
  ///
  /// A mouse notch arrives as one large event (~53px on Linux), but a trackpad
  /// swipe arrives as a stream of small ones — stepping a whole level per event
  /// would fly through the whole pyramid. Accumulating to a threshold gives
  /// one step per notch and a bearable number per swipe.
  double _accumulated = 0;

  static const double _notch = 40;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final controller = MapController.of(context);

    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
          // Reversing direction mid-scroll starts a fresh count, so a small
          // nudge back does not have to undo the whole accumulated delta.
          if (_accumulated.sign != event.scrollDelta.dy.sign) _accumulated = 0;
          _accumulated += event.scrollDelta.dy;
          if (_accumulated.abs() < _notch) return;

          final zoomIn = _accumulated < 0;
          _accumulated = 0;

          // Step to the adjacent whole level. Taking floor/ceil rather than
          // round(zoom) ± 1 keeps the first step after a pinch (or any other
          // fractional camera) to a single level instead of up to two.
          final stepped = zoomIn
              ? camera.zoom.floorToDouble() + 1
              : camera.zoom.ceilToDouble() - 1;
          final next = stepped
              .clamp(camera.minZoom ?? 0, camera.maxZoom ?? double.infinity)
              .toDouble();
          if (next == camera.zoom) return;

          controller.move(
            camera.focusedZoomCenter(event.localPosition, next),
            next,
          );
        },
      ),
    );
  }
}

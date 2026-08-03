import 'package:federfall/ui/ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Enough delta to cross the widget's per-step threshold in one event, as a
/// mouse notch does (Linux reports ~53px per notch).
const _notch = 60.0;

Future<MapCamera> _pumpMap(
  WidgetTester tester, {
  double initialZoom = 12,
  double? maxZoom,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
        options: MapOptions(
          initialCenter: const LatLng(53.14, 8.21),
          initialZoom: initialZoom,
          maxZoom: maxZoom,
          interactionOptions: const InteractionOptions(
            flags: MapWheelZoom.flags,
          ),
        ),
        children: const [MapWheelZoom()],
      ),
    ),
  );
  await tester.pump();
  return MapCamera.of(tester.element(find.byType(MapWheelZoom)));
}

Future<void> _scroll(WidgetTester tester, double dy) async {
  final centre = tester.getCenter(find.byType(FlutterMap));
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(centre));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pump();
}

double _zoom(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(MapWheelZoom))).zoom;

void main() {
  testWidgets('one notch in steps up exactly one whole zoom level', (
    tester,
  ) async {
    await _pumpMap(tester);
    await _scroll(tester, -_notch);

    expect(_zoom(tester), 13);
  });

  testWidgets('one notch out steps down exactly one whole zoom level', (
    tester,
  ) async {
    await _pumpMap(tester);
    await _scroll(tester, _notch);

    expect(_zoom(tester), 11);
  });

  // The whole point: flutter_map's built-in wheel zoom lands between integer
  // zooms, where every raster tile is redrawn at 71–141% of its native size.
  testWidgets('snaps a fractional camera one whole level at a time', (
    tester,
  ) async {
    await _pumpMap(tester, initialZoom: 12.4);

    await _scroll(tester, -_notch);
    expect(_zoom(tester), 13);

    await _scroll(tester, _notch);
    expect(_zoom(tester), 12);
  });

  testWidgets('accumulates trackpad-sized deltas into one step', (
    tester,
  ) async {
    await _pumpMap(tester);

    for (var i = 0; i < 3; i++) {
      await _scroll(tester, -8);
    }
    expect(_zoom(tester), 12, reason: 'below the threshold, no step yet');

    for (var i = 0; i < 5; i++) {
      await _scroll(tester, -8);
    }
    expect(_zoom(tester), 13, reason: 'one step once the deltas add up');
  });

  testWidgets("does not zoom past the camera's maxZoom", (tester) async {
    await _pumpMap(tester, initialZoom: 19, maxZoom: 19);
    await _scroll(tester, -_notch);

    expect(_zoom(tester), 19);
  });
}

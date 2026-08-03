import 'dart:async';

import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _raster = ServerMapConfig(
  mode: MapMode.raster,
  url: 'https://tiles.example.org/{z}/{x}/{y}.png',
  attribution: '© Example Tiles',
);

Future<void> _pumpMap(
  WidgetTester tester, {
  required Future<ServerInfo?> info,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [serverInfoProvider.overrideWith((ref) => info)],
    child: const MaterialApp(
      // Scaffold because MapAttribution links through an InkWell, which needs
      // a Material ancestor — as it has on every screen that hosts a map.
      home: Scaffold(
        body: FlutterMap(children: [MapTileLayer(), MapAttribution()]),
      ),
    ),
  ),
);

ServerInfo _serverWith(ServerMapConfig? map) => ServerInfo(
  version: '1.0',
  name: 'Federfall',
  auth: const ServerAuthOptions(),
  map: map,
);

void main() {
  testWidgets('falls back to the defines when nothing is prescribed', (
    tester,
  ) async {
    await _pumpMap(tester, info: Future.value(_serverWith(null)));
    await tester.pump();

    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, AppEnvironment.mapTileUrl);
    expect(find.text(AppEnvironment.mapAttribution), findsOneWidget);
  });

  testWidgets('a prescribed vector source takes the vector path', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      info: Future.value(
        _serverWith(
          const ServerMapConfig(
            mode: MapMode.vector,
            url: 'https://maps.example.org/style.json',
            attribution: '© Example Vector',
          ),
        ),
      ),
    );
    await tester.pump();

    // No raster layer, and the credit is the prescribed one. The style fetch
    // itself cannot resolve in a test, so the vector layer stays unbuilt.
    expect(find.byType(TileLayer), findsNothing);
    expect(find.text('© Example Vector'), findsOneWidget);
  });

  testWidgets('a prescribed raster source replaces source AND credit', (
    tester,
  ) async {
    await _pumpMap(tester, info: Future.value(_serverWith(_raster)));
    await tester.pump();

    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, 'https://tiles.example.org/{z}/{x}/{y}.png');
    expect(find.text('© Example Tiles'), findsOneWidget);
    expect(find.text(AppEnvironment.mapAttribution), findsNothing);
  });

  // The router only awaits /info on the unauthenticated path, so a warm start
  // into a screen with a map can build one before the prescription lands. The
  // layer has to swap when it does — the vector path reads its style in
  // initState, which an in-place rebuild could not redo.
  testWidgets('swaps the source when /info resolves after the map is built', (
    tester,
  ) async {
    final pending = Completer<ServerInfo?>();
    await _pumpMap(tester, info: pending.future);
    await tester.pump();

    expect(find.text(AppEnvironment.mapAttribution), findsOneWidget);
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
      AppEnvironment.mapTileUrl,
    );

    pending.complete(_serverWith(_raster));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
      'https://tiles.example.org/{z}/{x}/{y}.png',
    );
    expect(find.text('© Example Tiles'), findsOneWidget);
  });
}

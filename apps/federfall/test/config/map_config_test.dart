import 'package:federfall/config/app_environment.dart';
import 'package:federfall/config/map_config.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapConfig.resolve', () {
    test('falls back to the build-time defines without a prescription', () {
      final config = MapConfig.resolve(null);

      expect(config.mode, AppEnvironment.mapMode);
      expect(config.attribution, AppEnvironment.mapAttribution);
      expect(config.attributionUrl, AppEnvironment.mapAttributionUrl);
      // url tracks the mode, since only one of the two defines is ever in play.
      expect(
        config.url,
        config.mode == MapMode.raster
            ? AppEnvironment.mapTileUrl
            : AppEnvironment.mapStyleUrl,
      );
    });

    // Raster by default: vector_map_tiles has no GPU path, so it costs frame
    // rate and label quality against plain image tiles.
    test('the shipped default is raster OSM, credited to OSM', () {
      final config = MapConfig.resolve(null);

      expect(config.mode, MapMode.raster);
      expect(config.url, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(config.attribution, '© OpenStreetMap contributors');
    });

    test('takes the whole prescription when the server sends one', () {
      final config = MapConfig.resolve(
        const ServerMapConfig(
          mode: MapMode.raster,
          url: 'https://tiles.example.org/{z}/{x}/{y}.png',
          attribution: '© Example Tiles',
        ),
      );

      expect(config.mode, MapMode.raster);
      expect(config.url, 'https://tiles.example.org/{z}/{x}/{y}.png');
      // Not merged with the defines: the credit for a server-chosen provider
      // can only come from that server, and the built-in one would be wrong.
      expect(config.attribution, '© Example Tiles');
      expect(config.attributionUrl, isNull);
    });

    test('substitutes the API key into a raster template', () {
      final config = MapConfig.resolve(
        const ServerMapConfig(
          mode: MapMode.raster,
          url: 'https://api.example.org/{z}/{x}/{y}.png?key={key}',
          attribution: '© Example Tiles',
          apiKey: 'a b/c',
        ),
      );

      // flutter_map only knows the {z}/{x}/{y} placeholders and would request
      // the literal {key}; encoded as a query component, as the vector side is.
      expect(
        config.rasterUrl,
        'https://api.example.org/{z}/{x}/{y}.png?key=a+b%2Fc',
      );
    });

    test('a raster template without a key placeholder is left alone', () {
      final config = MapConfig.resolve(
        const ServerMapConfig(
          mode: MapMode.raster,
          url: 'https://tiles.example.org/{z}/{x}/{y}.png?key=inline',
          attribution: '© Example Tiles',
        ),
      );

      expect(config.rasterUrl, config.url);
    });

    test('has value equality, so it can key a widget', () {
      const a = ServerMapConfig(
        mode: MapMode.raster,
        url: 'https://tiles.example.org/{z}/{x}/{y}.png',
        attribution: '© Example Tiles',
      );

      expect(MapConfig.resolve(a), MapConfig.resolve(a));
      expect(MapConfig.resolve(a), isNot(MapConfig.resolve(null)));
    });
  });
}

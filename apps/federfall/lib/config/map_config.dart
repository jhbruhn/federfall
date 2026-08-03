import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_config.g.dart';

/// The map source actually in effect, after resolving the server's prescription
/// against the build-time defines (federfall-el1f).
///
/// The defines are baked into the web bundle and the APK, so on the published
/// container image they are not configuration at all — a self-hoster cannot
/// change them without rebuilding. The server can therefore prescribe a source
/// through `/api/federfall/info`, and that wins here. It fails open exactly
/// like the rest of that endpoint's discovery: no prescription, an older server
/// without the `map` key, or an unreachable `/info` all land on the defines.
@immutable
class MapConfig {
  const MapConfig({
    required this.mode,
    required this.url,
    required this.attribution,
    this.attributionUrl,
    this.apiKey,
  });

  /// The build-time defaults from `dart_defines/<flavor>.json`.
  factory MapConfig.fromDefines() {
    final mode = AppEnvironment.mapMode;
    return MapConfig(
      mode: mode,
      url: mode == MapMode.raster
          ? AppEnvironment.mapTileUrl
          : AppEnvironment.mapStyleUrl,
      attribution: AppEnvironment.mapAttribution,
      attributionUrl: AppEnvironment.mapAttributionUrl.isEmpty
          ? null
          : AppEnvironment.mapAttributionUrl,
      // No define counterpart on purpose: the shipped default provider needs no
      // key, and the defines files are committed — a key does not belong there.
    );
  }

  /// [server]'s prescription when it sent one, else [MapConfig.fromDefines].
  ///
  /// All-or-nothing on purpose — there is no field-by-field merge. Mixing the
  /// two sources is what produces a map that renders one provider's tiles under
  /// another's credit; [ServerMapConfig] is only ever parsed as a complete unit
  /// for the same reason.
  factory MapConfig.resolve(ServerMapConfig? server) => server == null
      ? MapConfig.fromDefines()
      : MapConfig(
          mode: server.mode,
          url: server.url,
          attribution: server.attribution,
          attributionUrl: server.attributionUrl,
          apiKey: server.apiKey,
        );

  /// Which rendering path the map widgets take, see [MapMode].
  final MapMode mode;

  /// MapLibre style JSON URL in [MapMode.vector], `{z}/{x}/{y}` raster template
  /// in [MapMode.raster].
  final String url;

  /// Credit line the map displays for [url]'s provider.
  final String attribution;

  /// Copyright/licence page [attribution] links to, or null for plain text.
  final String? attributionUrl;

  /// The tile provider's API key, or null when it needs none.
  ///
  /// Applied differently per mode, which is why it stays a separate field
  /// instead of being pre-substituted into [url]: the vector path hands it to
  /// `StyleReader`, which has to substitute it inside the style's own source,
  /// sprite and glyph URLs too — only the client can do that, while reading the
  /// style. In raster mode there is nothing further to reach, so [rasterUrl]
  /// resolves it up front.
  final String? apiKey;

  /// [url] ready for a raster `TileLayer`: the `{key}` token substituted, since
  /// flutter_map only knows the `{z}/{x}/{y}` placeholders and would request
  /// the literal token. Encoded as a query component, matching what
  /// `vector_map_tiles` does on the vector side.
  String get rasterUrl =>
      url.replaceAll('{key}', Uri.encodeQueryComponent(apiKey ?? ''));

  @override
  bool operator ==(Object other) =>
      other is MapConfig &&
      other.mode == mode &&
      other.url == url &&
      other.attribution == attribution &&
      other.attributionUrl == attributionUrl &&
      other.apiKey == apiKey;

  @override
  int get hashCode =>
      Object.hash(mode, url, attribution, attributionUrl, apiKey);
}

/// The resolved [MapConfig] for the configured server.
///
/// Watches `serverInfoProvider`, so this is genuinely reactive rather than
/// read-once: while `/info` is still in flight (or if it fails) the value is
/// the defines, and it swaps to the server's prescription when the fetch lands.
/// The router gate only awaits `serverInfoProvider` on the *unauthenticated*
/// path, so a warm start straight into a case detail can build a map before it
/// resolves — the map widgets rebuild on the swap instead of assuming it is
/// already there.
@Riverpod(keepAlive: true)
MapConfig mapConfig(Ref ref) =>
    MapConfig.resolve(ref.watch(serverInfoProvider).value?.map);

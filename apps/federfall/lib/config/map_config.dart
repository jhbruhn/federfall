import 'package:federfall/config/app_environment.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart';

// MapConfig, ServerMapConfig and mapConfigProvider now live in
// zugvogel_pb_client (eiermann-d2a.4). What could NOT move is the half that
// reads this app's dart-defines: zugvogel holds no configuration and reads
// no compile-time define (injection boundary 3), so `MapConfig.resolve`
// takes the fallback as a parameter and this file supplies it.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show MapConfig, MapMode, ServerMapConfig, mapConfigProvider;

/// The build-time map defaults from `dart_defines/<flavor>.json`.
///
/// A function rather than the `MapConfig.fromDefines()` factory it replaces:
/// the
/// class is zugvogel's now, and Dart has no way to add a static member to
/// somebody else's type.
///
/// These are only the FALLBACK. The server can prescribe a source at runtime
/// through `/api/federfall/info` (federfall-el1f) — it has to be able to, since
/// these constants are baked into the web bundle and the APK and are not
/// configuration at all on a published image. Read the effective values through
/// `mapConfigProvider`, never from here directly.
MapConfig mapConfigFromDefines() {
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

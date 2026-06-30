import 'package:federfall/config/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tile attribution overlay, pinned bottom-left and kept legible over the map.
///
/// Required by the OpenStreetMap Tile Usage Policy (and most tile providers):
/// every map must carry visible, non-hidden attribution. The text comes from
/// [AppEnvironment.mapAttribution] and links to
/// [AppEnvironment.mapAttributionUrl] (the OSM copyright page by default), as
/// the OSMF attribution guidelines recommend for interactive maps. Drop it in
/// as a `FlutterMap` child after the tile layer.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const text = AppEnvironment.mapAttribution;
    if (text.isEmpty) return const SizedBox.shrink();

    final url = Uri.tryParse(AppEnvironment.mapAttributionUrl);
    final label = Text(text, style: theme.textTheme.labelSmall);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: url == null
            ? label
            : InkWell(
                onTap: () =>
                    launchUrl(url, mode: LaunchMode.externalApplication),
                child: label,
              ),
      ),
    );
  }
}

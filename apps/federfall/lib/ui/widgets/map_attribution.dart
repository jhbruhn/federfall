import 'package:federfall/config/map_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tile attribution overlay, pinned bottom-left and kept legible over the map.
///
/// Required by the tile provider's usage policy, whichever [MapConfig.mode] is
/// active: every map must carry visible, non-hidden attribution. Text and link
/// come from [mapConfigProvider], i.e. from the same resolution step as the
/// tile URL itself — so a server that repoints the maps credits its own
/// provider and never keeps showing the built-in one. The link target is
/// optional (the OSM copyright page by default), as the OSMF attribution
/// guidelines recommend for interactive maps. Drop it in as a `FlutterMap`
/// child after the tile layer.
class MapAttribution extends ConsumerWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(mapConfigProvider);
    final text = config.attribution;
    if (text.isEmpty) return const SizedBox.shrink();

    final attributionUrl = config.attributionUrl;
    final url = attributionUrl == null ? null : Uri.tryParse(attributionUrl);
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

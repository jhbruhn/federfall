import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart' show LiveRefresh;

/// The period a case's `admittedAt` must fall in for its pin to show.
enum _Period { thisYear, last12Months, allTime }

/// Intake find-location overview (federfall-xr8t): plots every intake case's
/// find location for a filtered period, as a situational-awareness/reporting
/// map. Reached from the statistics screen. Cases come straight from the
/// `intakeLocations` provider, which loads through the same
/// org-scoped/server-enforced repositories as the rest of the statistics
/// section — no extra client-side visibility filtering is needed, since a
/// case the viewer isn't allowed to read never reaches the list.
class IntakeMapScreen extends ConsumerStatefulWidget {
  const IntakeMapScreen({super.key});

  @override
  ConsumerState<IntakeMapScreen> createState() => _IntakeMapScreenState();
}

class _IntakeMapScreenState extends ConsumerState<IntakeMapScreen> {
  /// Ceiling for the automatic fit, see [_cameraFit]. Street level, not rooftop
  /// — far enough in to place a cluster of finds, not so far that a tight
  /// cluster opens on a view with no landmarks.
  static const double _fitMaxZoom = 16;

  /// Ceiling for the camera itself. The tile pyramid ends at `TileLayer`'s
  /// `maxNativeZoom` (19); past it flutter_map keeps drawing z19 tiles at an
  /// ever larger scale, so without this a few scroll-wheel notches — far easier
  /// to overshoot than a pinch — turn the map into magnified pixels.
  static const double _maxZoom = 19;

  _Period _period = _Period.thisYear;

  /// The active filter range, resolved once per period change (not on every
  /// build) — the `intakeLocations` family provider is keyed by this value,
  /// so a fresh `DateTime.now()` each rebuild would mint a distinct argument
  /// every time and reload forever.
  late DateTimeRange? _range = _rangeFor(_period);

  static DateTimeRange? _rangeFor(_Period period) {
    final now = DateTime.now();
    switch (period) {
      case _Period.thisYear:
        return DateTimeRange(start: DateTime(now.year), end: now);
      case _Period.last12Months:
        return DateTimeRange(
          start: DateTime(now.year - 1, now.month, now.day),
          end: now,
        );
      case _Period.allTime:
        return null;
    }
  }

  /// How the camera frames [bounds] when the map is built.
  ///
  /// Handed to `MapOptions.initialCameraFit` rather than applied through a
  /// `MapController.fitCamera` in a post-frame callback, which is what this
  /// screen used to do and is why the map came up with **no tiles at all**
  /// until the first scroll. `TileLayer` only ever *fetches* tiles from a
  /// `MapEvent` (`_loadTiles`); the tiles a rebuild creates for a new camera
  /// are left unfetched — `TileImageManager.createMissingTiles` returns them
  /// and the layer's `build` drops that list. So when a camera move's
  /// tile-update event does not reach the layer, as a controller-driven fit's
  /// did not on web, the layer keeps only the tiles it loaded when it mounted:
  /// the *pre-fit* camera, positioned off-screen and invisible, while the
  /// markers sit at the fitted camera. The first real gesture emitted an event
  /// and the whole map appeared at once. `initialCameraFit` is applied by
  /// `FlutterMap` itself, at the point in its own lifecycle where that works —
  /// the statistics mini-map has always framed itself this way and never had
  /// the bug. The map's `initialCenter` then seeds the pre-fit camera over the
  /// same pins, so even the mount-time load asks for tiles the viewer sees.
  ///
  /// `forceIntegerZoomLevel` is not cosmetic: a raster tile is only pixel-exact
  /// when the camera sits on an integer zoom. Off it, `TileLayer` fetches
  /// `zoom.round()` and draws each 256px tile at `256 * 2^(zoom - round(zoom))`
  /// — between 71% and 141% of native — so a fitted zoom of 8.37 renders the
  /// whole map through a resample. That is invisible on a phone's 3x screen and
  /// glaring at devicePixelRatio 1, i.e. on the desktop where this full-screen
  /// map is actually read.
  ///
  /// [_fitMaxZoom] also guards a degenerate fit: `CameraFit.bounds` divides the
  /// viewport by the bounds' pixel size, so a lone pin — or two cases found at
  /// the *same* coordinates (one nest, one finder) — gives a zero-size bounds,
  /// an infinite scale, and a zoom of `double.infinity`.
  static CameraFit _cameraFit(LatLngBounds bounds) => CameraFit.bounds(
    bounds: bounds,
    padding: const EdgeInsets.all(AppSpacing.xl),
    maxZoom: _fitMaxZoom,
    forceIntegerZoomLevel: true,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canViewReports(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.intakeMapTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final range = _range;
    ref.liveRefresh(
      const ['cases'],
      () => ref.invalidate(intakeLocationsProvider),
    );
    final locations = ref.watch(
      intakeLocationsProvider(admittedRange: range),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.intakeMapTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_Period>(
                segments: [
                  ButtonSegment(
                    value: _Period.thisYear,
                    label: Text(l10n.intakeMapPeriodThisYear),
                  ),
                  ButtonSegment(
                    value: _Period.last12Months,
                    label: Text(l10n.intakeMapPeriodLast12Months),
                  ),
                  ButtonSegment(
                    value: _Period.allTime,
                    label: Text(l10n.intakeMapPeriodAllTime),
                  ),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() {
                  _period = s.single;
                  _range = _rangeFor(_period);
                }),
              ),
            ),
          ),
        ),
      ),
      body: AsyncValueView<List<IntakeLocation>>(
        value: locations,
        onRetry: () => ref.invalidate(intakeLocationsProvider),
        data: (data) {
          if (data.isEmpty) {
            return EmptyView(
              icon: Icons.map_outlined,
              message: l10n.intakeMapEmpty,
            );
          }
          final bounds = LatLngBounds.fromPoints([
            for (final l in data) l.point,
            // A single find would otherwise be a zero-size bounds built from
            // one point, which `LatLngBounds.fromPoints` rejects outright.
            if (data.length == 1) data.single.point,
          ]);
          return FlutterMap(
            // Keyed on the period so choosing one re-frames the map: FlutterMap
            // applies `initialCameraFit` once per State, so a new fit only
            // takes effect on a fresh one. Deliberately NOT keyed on the data —
            // a realtime refresh should add pins, not yank the camera out from
            // under someone who has panned away.
            key: ValueKey(_period),
            options: MapOptions(
              initialCameraFit: _cameraFit(bounds),
              // The pre-fit camera, i.e. what the tile layer loads on mount.
              // Whole zoom level, and already over the pins: 5.5 rendered every
              // tile at 71% of native, and the fallback centre spent a
              // viewport's worth of tile requests on the wrong part of Germany.
              initialCenter: bounds.center,
              initialZoom: _fitMaxZoom,
              maxZoom: _maxZoom,
              interactionOptions: const InteractionOptions(
                flags: MapWheelZoom.flags,
              ),
            ),
            children: [
              const MapTileLayer(),
              const MapWheelZoom(),
              MarkerLayer(
                markers: [
                  for (final location in data)
                    Marker(
                      point: location.point,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _showLocationSheet(context, location),
                        child: Icon(
                          Icons.location_on,
                          size: 40,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
              const MapAttribution(),
            ],
          );
        },
      ),
    );
  }

  /// Shows the pin's detail sheet, then — only once it has fully closed —
  /// navigates to the case if "Open case" was tapped, via `context.go` (every
  /// other case-detail call site in the app uses `go`, never `push` — see
  /// e.g. `worklist_tile.dart`, `cases_screen.dart`). `caseDetail` is nested
  /// under the cases tab's `StatefulShellRoute` branch, which preserves that
  /// branch's own navigation stack in the background; `push`ing it from
  /// outside the shell added a second page for a route the branch could
  /// already hold, and go_router asserts on the resulting duplicate page key.
  /// `go` recomputes the whole location instead of stacking a page, so it
  /// can't collide like that.
  Future<void> _showLocationSheet(
    BuildContext context,
    IntakeLocation location,
  ) async {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    final admittedAt = location.admittedAt;

    final openCase = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location.animalName ?? l10n.intakeMapUnnamedCase,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              if (location.caseNumber case final caseNumber?)
                Text(
                  caseNumber,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      sheetContext,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              if (location.species case final species? when species.isNotEmpty)
                _SheetRow(icon: Icons.pets_outlined, text: species),
              if (admittedAt != null)
                _SheetRow(
                  icon: Icons.event_available_outlined,
                  text:
                      '${l10n.caseFieldAdmittedAt} '
                      '${formatLocalDate(materialL10n, admittedAt)}',
                ),
              if (location.city case final city? when city.isNotEmpty)
                _SheetRow(icon: Icons.place_outlined, text: city),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: l10n.intakeMapOpenCase,
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );

    if (openCase == true && context.mounted) {
      context.go(AppRoutes.caseDetail(location.caseId));
    }
  }
}

/// One icon + text line in the pin detail sheet.
class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

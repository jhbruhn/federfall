import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

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
  static const _fallbackCentre = LatLng(51.16, 10.45);

  final _mapController = MapController();
  _Period _period = _Period.thisYear;

  /// The active filter range, resolved once per period change (not on every
  /// build) — the `intakeLocations` family provider is keyed by this value,
  /// so a fresh `DateTime.now()` each rebuild would mint a distinct argument
  /// every time and reload forever.
  late DateTimeRange? _range = _rangeFor(_period);

  /// The last data list passed to [_fit] — fitting the camera moves the map,
  /// which rebuilds [FlutterMap]; without this guard, refitting on every
  /// rebuild would re-trigger itself forever. A fresh provider load always
  /// hands back a new list instance, so identity is enough to detect
  /// "already fitted".
  List<IntakeLocation>? _fitted;

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

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _fit(List<IntakeLocation> locations) {
    if (locations.isEmpty) return;
    if (locations.length == 1) {
      _mapController.move(locations.single.point, 12);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          for (final l in locations) l.point,
        ]),
        padding: const EdgeInsets.all(AppSpacing.xl),
      ),
    );
  }

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
          if (!identical(_fitted, data)) {
            _fitted = data;
            WidgetsBinding.instance.addPostFrameCallback((_) => _fit(data));
          }
          if (data.isEmpty) {
            return EmptyView(
              icon: Icons.map_outlined,
              message: l10n.intakeMapEmpty,
            );
          }
          return FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _fallbackCentre,
              initialZoom: 5.5,
            ),
            children: [
              const MapTileLayer(),
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

  Future<void> _showLocationSheet(
    BuildContext context,
    IntakeLocation location,
  ) {
    final l10n = context.l10n;
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location.caseNumber ?? l10n.intakeMapUnnamedCase,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              if (location.species case final species? when species.isNotEmpty)
                Text(species),
              if (location.city case final city? when city.isNotEmpty)
                Text(city),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: l10n.intakeMapOpenCase,
                icon: Icons.arrow_forward,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(
                    context.push(AppRoutes.caseDetail(location.caseId)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

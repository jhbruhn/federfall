import 'dart:async';

import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// The location chosen in the picker: a pin plus its resolved address parts.
class PickedLocation {
  const PickedLocation({
    required this.geo,
    required this.address,
    required this.city,
    required this.region,
  });

  final GeoPoint geo;
  final String address;
  final String city;
  final String region;
}

/// Opens the find-location map picker, returning the chosen [PickedLocation]
/// or `null` if cancelled. [initial] pre-centres on an existing pin.
Future<PickedLocation?> showLocationPicker(
  BuildContext context, {
  GeoPoint? initial,
  String? initialAddress,
}) {
  return Navigator.of(context).push<PickedLocation>(
    MaterialPageRoute(
      builder: (_) => LocationPickerScreen(
        initial: initial,
        initialAddress: initialAddress,
      ),
    ),
  );
}

/// Find-location picker (FED-4.2): an OSM map where the carer searches for an
/// address (forward geocode) or taps to drop a pin (reverse geocode). Tiles are
/// configurable via [AppEnvironment.mapTileUrl]; geocoding goes through the
/// backend proxy.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({this.initial, this.initialAddress, super.key});

  final GeoPoint? initial;
  final String? initialAddress;

  /// Map centre when there is no initial pin — roughly the middle of Germany.
  static const _fallbackCentre = LatLng(51.16, 10.45);

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();

  LatLng? _pin;
  String _address = '';
  String _city = '';
  String _region = '';
  List<GeoResult> _results = const [];
  bool _searching = false;
  bool _reversing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _pin = LatLng(initial.lat, initial.lon);
    _address = widget.initialAddress ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final l10n = context.l10n;
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final repo = await ref.read(geocodingRepositoryProvider.future);
      final results = await repo.forward(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e is RepositoryException
            ? errorMessage(l10n, e)
            : l10n.errorGenericTitle;
      });
    }
  }

  void _selectResult(GeoResult r) {
    final point = LatLng(r.lat, r.lon);
    setState(() {
      _pin = point;
      _address = r.displayName;
      _city = r.city;
      _region = r.region;
      _results = const [];
      _searchController.text = r.displayName;
    });
    _mapController.move(point, 15);
  }

  Future<void> _dropPin(LatLng point) async {
    setState(() {
      _pin = point;
      _reversing = true;
      _error = null;
    });
    try {
      final repo = await ref.read(geocodingRepositoryProvider.future);
      final r = await repo.reverse(point.latitude, point.longitude);
      if (!mounted) return;
      setState(() {
        _reversing = false;
        if (r != null) {
          _address = r.displayName;
          _city = r.city;
          _region = r.region;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() => _reversing = false);
    }
  }

  void _confirm() {
    final pin = _pin;
    if (pin == null) return;
    Navigator.of(context).pop(
      PickedLocation(
        geo: GeoPoint(lat: pin.latitude, lon: pin.longitude),
        address: _address,
        city: _city,
        region: _region,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pin = _pin;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.locationPickerTitle)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: pin ?? LocationPickerScreen._fallbackCentre,
              initialZoom: pin == null ? 5.5 : 15,
              onTap: (_, point) => unawaited(_dropPin(point)),
            ),
            children: [
              TileLayer(
                urlTemplate: AppEnvironment.mapTileUrl,
                userAgentPackageName: 'de.jhbruhn.federfall',
              ),
              if (pin != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pin,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  color: theme.colorScheme.surface.withValues(alpha: 0.7),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    AppEnvironment.mapAttribution,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            child: _SearchBar(
              controller: _searchController,
              busy: _searching,
              onSubmit: _search,
              results: _results,
              onSelect: _selectResult,
              error: _error,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _reversing
                    ? l10n.locationResolving
                    : (_address.isEmpty ? l10n.locationPickHint : _address),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: l10n.locationUseAction,
                icon: Icons.check,
                onPressed: pin == null ? null : _confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating search field with a results dropdown over the map.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.busy,
    required this.onSubmit,
    required this.results,
    required this.onSelect,
    required this.error,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;
  final List<GeoResult> results;
  final ValueChanged<GeoResult> onSelect;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: l10n.locationSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: onSubmit,
                    ),
              border: InputBorder.none,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          if (results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in results)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(r.displayName),
                      onTap: () => onSelect(r),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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

/// Find-location picker (FED-4.2, refined in 2fa): an OSM map with a pin fixed
/// at screen centre — the carer drags the map so the target sits under the pin
/// (reverse geocode on settle), searches for an address (forward geocode), or
/// taps "my location" (GPS). Tiles come from the shared [MapTileLayer];
/// geocoding goes through the backend proxy.
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

  /// The map centre — the pin sits here, so it is the location being chosen.
  late LatLng _centre;
  String _address = '';
  String _city = '';
  String _region = '';
  List<GeoResult> _results = const [];
  bool _searched = false;
  bool _searching = false;
  bool _reversing = false;
  bool _locating = false;
  String? _error;

  /// Monotonic id of the latest reverse-geocode; stale responses (from a pin
  /// position that has since changed) are dropped instead of applied.
  int _resolveSeq = 0;

  /// True once a pin position has produced a resolved address — gates "Use".
  bool get _hasLocation => _address.isNotEmpty && !_reversing;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _centre = initial == null
        ? LocationPickerScreen._fallbackCentre
        : LatLng(initial.lat, initial.lon);
    _address = widget.initialAddress ?? '';
    // With an initial pin but no address, resolve it once the map is up.
    if (initial != null && _address.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveCentre());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    // The user dragged/flung the map; whatever is now under the pin becomes
    // the candidate location. Programmatic moves resolve explicitly instead.
    if (event is MapEventMoveEnd) {
      _centre = event.camera.center;
      unawaited(_resolveCentre());
    }
  }

  /// Reverse-geocodes the current map centre into the address card. On
  /// failure the previous pin's address is cleared (never paired with the new
  /// coordinates) so "Use" stays gated until a fresh resolve succeeds.
  Future<void> _resolveCentre() async {
    final l10n = context.l10n;
    final seq = ++_resolveSeq;
    setState(() {
      _reversing = true;
      _error = null;
    });
    try {
      final repo = await ref.read(geocodingRepositoryProvider.future);
      final r = await repo.reverse(_centre.latitude, _centre.longitude);
      if (!mounted || seq != _resolveSeq) return;
      setState(() {
        _reversing = false;
        _address = r?.displayName ?? '';
        _city = r?.city ?? '';
        _region = r?.region ?? '';
      });
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (!mounted || seq != _resolveSeq) return;
      setState(() {
        _reversing = false;
        _address = '';
        _city = '';
        _region = '';
        _error = error is RepositoryException
            ? errorMessage(l10n, error)
            : l10n.errorGenericTitle;
      });
    }
  }

  Future<void> _search() async {
    final l10n = context.l10n;
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searched = true;
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
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = const [];
        _error = e is RepositoryException
            ? errorMessage(l10n, e)
            : l10n.errorGenericTitle;
      });
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _results = const [];
      _searched = false;
      _error = null;
    });
    FocusScope.of(context).unfocus();
  }

  void _selectResult(GeoResult r) {
    _centre = LatLng(r.lat, r.lon);
    // The picked result is authoritative — drop any in-flight reverse lookup.
    _resolveSeq++;
    setState(() {
      _reversing = false;
      _address = r.displayName;
      _city = r.city;
      _region = r.region;
      _results = const [];
      _searched = false;
      _searchController.text = r.displayName;
    });
    FocusScope.of(context).unfocus();
    _mapController.move(_centre, 16);
  }

  Future<void> _useMyLocation() async {
    final l10n = context.l10n;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationException();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw const _LocationException();
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _centre = LatLng(pos.latitude, pos.longitude);
      setState(() => _locating = false);
      _mapController.move(_centre, 16);
      await _resolveCentre();
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = l10n.locationPermissionDenied;
      });
    }
  }

  void _confirm() {
    if (!_hasLocation) return;
    Navigator.of(context).pop(
      PickedLocation(
        geo: GeoPoint(lat: _centre.latitude, lon: _centre.longitude),
        address: _address,
        city: _city,
        region: _region,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.locationPickerTitle)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _centre,
              initialZoom: widget.initial == null ? 5.5 : 16,
              onMapEvent: _onMapEvent,
              onTap: (_, point) => _mapController.move(point, 16),
            ),
            children: const [
              MapTileLayer(),
              MapAttribution(),
            ],
          ),
          // Pin fixed at screen centre, lifted by a shadow dot beneath it.
          IgnorePointer(child: _CentrePin(reversing: _reversing)),
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            child: _SearchBar(
              controller: _searchController,
              busy: _searching,
              searched: _searched,
              onSubmit: _search,
              onClear: _clearSearch,
              results: _results,
              onSelect: _selectResult,
              error: _error,
            ),
          ),
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              tooltip: l10n.locationCurrentAction,
              onPressed: _locating ? null : _useMyLocation,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _AddressBar(
        address: _address,
        city: _city,
        region: _region,
        reversing: _reversing,
        canConfirm: _hasLocation,
        onConfirm: _confirm,
      ),
    );
  }
}

/// Sentinel for "couldn't get a usable GPS fix" (services off or denied).
class _LocationException implements Exception {
  const _LocationException();
}

/// The map's static centre pin: a marker glyph with a small shadow ellipse
/// beneath, so it reads as floating above the moving map.
class _CentrePin extends StatelessWidget {
  const _CentrePin({required this.reversing});

  final bool reversing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      // Offset up by half the icon so the tip sits on the exact centre.
      child: Transform.translate(
        offset: const Offset(0, -20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on,
              size: 44,
              color: theme.colorScheme.error,
              shadows: const [
                Shadow(blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            Container(
              width: 8,
              height: 4,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating search field with a connected results dropdown over the map.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.busy,
    required this.searched,
    required this.onSubmit,
    required this.onClear,
    required this.results,
    required this.onSelect,
    required this.error,
  });

  final TextEditingController controller;
  final bool busy;
  final bool searched;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final List<GeoResult> results;
  final ValueChanged<GeoResult> onSelect;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showEmpty = searched && !busy && results.isEmpty && error == null;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rebuilt per keystroke via the controller so the clear button
          // appears/disappears while typing, not only on unrelated setStates.
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, text, _) => TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: l10n.locationSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : text.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.actionClear,
                        onPressed: onClear,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
          if (error != null)
            _SearchMessage(text: error!, isError: true)
          else if (showEmpty)
            _SearchMessage(text: l10n.locationNoMatches, isError: false)
          else if (results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = results[i];
                  final locality = [
                    if (r.city.isNotEmpty) r.city,
                    if (r.region.isNotEmpty) r.region,
                  ].join(' · ');
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(
                      r.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: locality.isEmpty ? null : Text(locality),
                    onTap: () => onSelect(r),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isError
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Selected-address card + confirm action, anchored to the bottom.
class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.address,
    required this.city,
    required this.region,
    required this.reversing,
    required this.canConfirm,
    required this.onConfirm,
  });

  final String address;
  final String city;
  final String region;
  final bool reversing;
  final bool canConfirm;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locality = [
      if (city.isNotEmpty) city,
      if (region.isNotEmpty) region,
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: reversing
                          ? Text(
                              l10n.locationResolving,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : address.isEmpty
                          ? Text(
                              l10n.locationPickHint,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  address,
                                  style: theme.textTheme.bodyLarge,
                                ),
                                if (locality.isNotEmpty)
                                  Text(
                                    locality,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: l10n.locationUseAction,
              icon: Icons.check,
              onPressed: canConfirm ? onConfirm : null,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cold_start_location.g.dart';

/// The location the router should navigate to on cold start (federfall-7ev8).
/// `null` by default; `bootstrap.dart` overrides this with the persisted
/// `LastRouteStorage` value — read before `runApp`, so it's available
/// synchronously when the router builds — before falling back to the default
/// landing.
@Riverpod(keepAlive: true)
String? coldStartLocation(Ref ref) => null;

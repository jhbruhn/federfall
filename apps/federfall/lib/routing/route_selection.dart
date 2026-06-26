import 'package:federfall/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The id of the item whose detail is open for the current route, or null when
/// nothing is selected — used by the list-detail surfaces to highlight the
/// active row on expanded widths.
///
/// Returns null when there is no [GoRouter] ancestor (e.g. a widget test that
/// pumps a screen standalone), so the list screens stay usable outside the
/// router. When a router *is* present this reads via [GoRouterState.of] so the
/// caller rebuilds — and the highlight follows — as the route changes.
String? selectedDetailId(BuildContext context) {
  if (GoRouter.maybeOf(context) == null) return null;
  return detailIdOf(GoRouterState.of(context).uri.toString());
}

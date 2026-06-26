import 'package:flutter/widgets.dart';

/// Material 3 window-size classes — the single source of truth for mapping the
/// current width to a layout decision. Everything adaptive (the nav shell, the
/// list-detail surfaces, the case detail) derives from here instead of
/// sprinkling raw `MediaQuery` width checks through the widget tree.
///
/// Breakpoints follow the M3 spec: compact `< 600`, medium `600–839`, expanded
/// `>= 840` (logical pixels).
enum WindowSizeClass {
  /// Phones in portrait — single pane, bottom navigation.
  compact,

  /// Large phones / small tablets — single pane, navigation rail.
  medium,

  /// Tablets / desktop / web — room for two panes, extended rail.
  expanded;

  /// Whether this class is [expanded] (i.e. wide enough for two panes).
  bool get isExpanded => this == WindowSizeClass.expanded;
}

/// Width (logical px) at/above which the layout is [WindowSizeClass.medium].
const double kMediumMin = 600;

/// Width (logical px) at/above which the layout is [WindowSizeClass.expanded]
/// and the canonical list-detail surfaces show both panes.
const double kExpandedMin = 840;

/// Fixed width of the list pane in a two-pane (list-detail) layout.
const double kListPaneWidth = 360;

/// Maximum width for flat, scrolling page content (settings lists, the profile,
/// statistics, admin sections). Beyond this, content is centred with margins so
/// rows and bars don't stretch to an unreadable length on wide windows. See
/// `ContentBounds`.
const double kContentMaxWidth = 840;

/// Maximum width for a modal sheet's content. On wide windows the sheet floats
/// centred at this width instead of stretching edge-to-edge; below it the sheet
/// fills the screen as before. See `showAppSheet`.
const double kSheetMaxWidth = 640;

/// Width of the *detail pane* at/above which the case detail lays Overview and
/// History out side-by-side instead of behind tabs. Keyed on the pane (not the
/// window) so a 840-wide window — whose detail pane is only ~480 — keeps tabs,
/// while a wide desktop or a full-screen detail shows both columns.
const double kCaseDetailTwoColumnMin = 720;

/// Maps a raw width to its [WindowSizeClass].
WindowSizeClass windowSizeClassFor(double width) {
  if (width >= kExpandedMin) return WindowSizeClass.expanded;
  if (width >= kMediumMin) return WindowSizeClass.medium;
  return WindowSizeClass.compact;
}

/// Window-size helpers on [BuildContext]. Reads `MediaQuery.sizeOf`, so callers
/// rebuild when the window is resized.
extension WindowSizeContext on BuildContext {
  /// The current [WindowSizeClass] for this context's width.
  WindowSizeClass get windowSizeClass =>
      windowSizeClassFor(MediaQuery.sizeOf(this).width);

  /// Whether the current width is [WindowSizeClass.expanded] — i.e. wide enough
  /// to show a list and a detail side-by-side.
  bool get isExpanded => windowSizeClass.isExpanded;
}

/// Whether [location] addresses an item-detail page (`.../:id`) of one of the
/// canonical list-detail surfaces. Used by the nav shell to drop the bottom
/// navigation bar on compact widths so a phone detail stays full-screen, even
/// though the detail now resolves inside the navigation shell.
///
/// Matches `/cases/<id>`, `/animals/<id>`, `/aviaries/<id>` — but not the
/// section roots, nor the literal `/cases/new` and `/cases/browse` sub-routes
/// (those already push full-screen over the shell on their own).
bool isDetailLocation(String location) {
  // Strip any query string, then split into non-empty path segments.
  final path = location.split('?').first;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length != 2) return false;
  const sections = {'cases', 'animals', 'aviaries'};
  if (!sections.contains(segments.first)) return false;
  const reserved = {'new', 'browse'};
  return !reserved.contains(segments[1]);
}

/// The selected item id encoded in [location] when it is an [isDetailLocation],
/// else null. Lets a list highlight the row whose detail is open in the other
/// pane on expanded widths.
String? detailIdOf(String location) {
  if (!isDetailLocation(location)) return null;
  final path = location.split('?').first;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  return segments.length == 2 ? segments[1] : null;
}

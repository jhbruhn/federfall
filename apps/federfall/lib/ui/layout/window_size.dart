// The Material 3 size classes, their breakpoints and the width caps now live in
// zugvogel_ui (eiermann-d2a.13): compact/medium/expanded is Material's mapping,
// not federfall's, and both apps read it the same way.
//
// This file was SPLIT rather than moved. What stayed below are the breakpoints
// tuned to particular content — the width the statistics cards need before two
// columns of chart stay readable, the one the dashboard's KPI tiles need, the
// one the case detail's panes need — plus the two route predicates. Those are
// facts about federfall's screens and federfall's URLs, so a shared package
// answering for them would only be guessing.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show
        WindowSizeClass,
        WindowSizeContext,
        kContentMaxWidth,
        kExpandedMin,
        kListPaneWidth,
        kMediumMin,
        kSheetMaxWidth,
        kWideContentMaxWidth,
        windowSizeClassFor;

/// Width at/above which the statistics screen lays its cards out in two
/// columns instead of one.
///
/// Higher than [kCaseDetailTwoColumnMin] on purpose: that split moves two lists
/// side by side, while these columns hold charts — a donut with its legend, and
/// a series with up to 31 bars — which stop being readable well before a list
/// does. Below this the screen stays the single column a phone gets.
const double kStatsTwoColumnMin = 960;

/// Width at/above which the dashboard lays its Today preview and its caseload
/// side by side instead of stacking them.
///
/// Higher than [kStatsTwoColumnMin], and derived rather than chosen: the right
/// column carries the KPI grid, which needs room for two tiles at its own
/// 240px minimum (`KpiGrid`), i.e. 496 including the gap between them. Two such
/// columns plus the gap between them and the page's own padding is 1040. Below
/// that the caseload is better off with the full width — and the split used to
/// happen at `kExpandedMin`, which is not even the width the dashboard gets: a
/// `NavigationRail` stands beside it, so the body is 80–200px narrower than the
/// window and the tiles came out under 190px.
const double kDashboardTwoColumnMin = 1040;

/// Width of the *detail pane* at/above which the case detail lays Overview and
/// History out side-by-side instead of behind tabs. Keyed on the pane (not the
/// window) so a 840-wide window — whose detail pane is only ~480 — keeps tabs,
/// while a wide desktop or a full-screen detail shows both columns.
const double kCaseDetailTwoColumnMin = 720;

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

/// Spacing scale used across Federfall, in logical pixels.
///
/// A small fixed scale keeps layouts consistent and avoids scattering magic
/// numbers through widgets.
abstract final class AppSpacing {
  /// 4 — hairline gaps between tightly related elements.
  static const double xs = 4;

  /// 8 — default gap inside a row/column of related controls.
  static const double sm = 8;

  /// 16 — standard padding around content and between sections.
  static const double md = 16;

  /// 24 — generous separation between distinct groups.
  static const double lg = 24;

  /// 32 — page-level breathing room.
  static const double xl = 32;
}

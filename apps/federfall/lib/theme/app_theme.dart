import 'package:flutter/material.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart';

// This theme stays federfall's own (eiermann-d2a.13), unlike the widgets it
// styles. zugvogel_ui ships a ZugvogelTheme scaffold, but it bundles the fonts
// as package assets and names its families with a `packages/zugvogel_ui/`
// prefix; federfall bundles the same families itself, and a test pins the
// declarations in this app's pubspec against the names used here. Moving to the
// package's scaffold would mean changing what that test is allowed to assert,
// which is not a thing a migration gets to do.
//
// What did have to change: BreakdownBars and BreakdownPie no longer name their
// hues. A shared package may not name a colour (injection boundary 2), so the
// categorical chart palette is injected through a ZugvogelSemantics theme
// extension — registered below, per brightness, with exactly the hues the two
// charts used to hold as literals.

/// Federfall's Material 3 theming.
///
/// A single seed colour drives both light and dark schemes. The palette leans
/// on a muted teal-green — calm and naturalistic, fitting wildlife care and
/// staying clear of the stock "Flutter blue" template look. Component themes
/// (inputs, buttons, cards) are tuned once here so screens stay declarative.
abstract final class AppTheme {
  /// Brand seed colour.
  static const Color seed = Color(0xFF356859);

  /// Categorical chart hues in fixed order, light theme.
  ///
  /// Steps chosen against a light surface, not derived from the seed: adjacent
  /// slices of a donut have to be told apart, which no single Material role can
  /// promise. [darkCategorical] is the same set of hues re-picked against a
  /// dark surface rather than an automatic lightness flip of these — a flip is
  /// exactly what passes contrast in one theme and fails in the other.
  static const List<Color> lightCategorical = <Color>[
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF199E70),
  ];

  /// Categorical chart hues in fixed order, dark theme.
  static const List<Color> darkCategorical = <Color>[
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
  ];

  /// The neutral a chart uses for a folded "other" tail, light theme.
  ///
  /// Deliberately not one of [lightCategorical]: the tail is not a category, it
  /// is the absence of one, and a hue of its own would invite the reader to
  /// compare it with the named slices.
  static const Color lightCategoricalOther = Color(0xFF5F5F5F);

  /// The neutral a chart uses for a folded "other" tail, dark theme.
  static const Color darkCategoricalOther = Color(0xFF6F6F6F);

  /// Bundled families consulted for glyphs the bundled Roboto lacks
  /// (federfall-sbtx).
  ///
  /// Web has no system fonts: CanvasKit/skwasm resolves a missing codepoint by
  /// downloading a per-glyph Noto slice from fonts.gstatic.com — blocked by our
  /// CSP and retried on every layout, so a single `✓` in a note produced an
  /// endless stream of console errors. Declaring the fonts in pubspec.yaml is
  /// not enough: the engine tests coverage against the families a `TextStyle`
  /// names, so they have to be named here too.
  ///
  /// Order is text-presentation first — a pictograph that exists in Noto Sans
  /// Symbols 2 (`✓ ✗ ★ ⚠ ♥`, and outlines of the older emoji) renders
  /// monochrome, which reads better inside a clinical record than a coloured
  /// sign; anything emoji-only (`😀 🥚 ✅`) still comes out in colour. Swapping
  /// the last two entries flips that preference.
  ///
  /// Not exhaustive by choice: CJK, Arabic and Indic scripts would add ~12 MB,
  /// so those still fall back to a download the CSP blocks — boxes on web,
  /// which is the honest outcome for a German-language app.
  static const List<String> fontFallbacks = <String>[
    'Noto Sans Symbols', // → ↑ ↓ ♀ ♂ ⌀ ⚕
    'Noto Sans Symbols 2', // ✓ ✗ ☑ ★ ♥ ⚠ + monochrome pictographs
    'Noto Color Emoji', // everything else emoji, in COLRv1 colour
  ];

  /// Light theme.
  static ThemeData get light => _build(Brightness.light);

  /// Dark theme.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // How the shared charts find their palette. good/warning/critical are
      // left scheme-derived — nothing in federfall reads them yet, and a
      // hand-picked green that clashes with the brand is worse than a
      // borrowed role.
      extensions: [
        ZugvogelSemantics.fromScheme(colorScheme).copyWith(
          categorical: dark ? darkCategorical : lightCategorical,
          categoricalOther: dark ? darkCategoricalOther : lightCategoricalOther,
        ),
      ],
      // Named explicitly (rather than relying on the M3 default) so the
      // fallbacks below hang off the same family the app actually bundles.
      fontFamily: 'Roboto',
      fontFamilyFallback: fontFallbacks,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        scrolledUnderElevation: 2,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      // Filled rather than outlined: a subtle tonal surface that stays present
      // on busy scroll views without the fussiness of a hairline border. One
      // change lifts every card (KPIs, the Today card, sheets) at once.
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      // A selected ListTile (the active row in a list-detail pane) gets a
      // visible primary tint behind it — but the text/icons stay onSurface
      // rather than M3's default primary recolouring, which reads as poor
      // contrast on the tint. The background alone marks the open row.
      listTileTheme: ListTileThemeData(
        selectedColor: colorScheme.onSurface,
        selectedTileColor: colorScheme.primary.withValues(alpha: 0.10),
      ),
    );
  }
}

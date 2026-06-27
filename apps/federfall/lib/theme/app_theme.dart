import 'package:flutter/material.dart';

/// Federfall's Material 3 theming.
///
/// A single seed colour drives both light and dark schemes. The palette leans
/// on a muted teal-green — calm and naturalistic, fitting wildlife care and
/// staying clear of the stock "Flutter blue" template look. Component themes
/// (inputs, buttons, cards) are tuned once here so screens stay declarative.
abstract final class AppTheme {
  /// Brand seed colour.
  static const Color seed = Color(0xFF356859);

  /// Light theme.
  static ThemeData get light => _build(Brightness.light);

  /// Dark theme.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
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

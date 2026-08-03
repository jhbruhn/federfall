import 'dart:io';

import 'package:federfall/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// federfall-sbtx: web has no system fonts, so a codepoint no bundled family
/// covers makes the engine fetch a Noto slice from fonts.gstatic.com — which
/// the CSP blocks and the engine then retries on every layout. Keeping that
/// fixed needs BOTH halves to stay in place, and neither is exercised by any
/// widget test: the families declared in pubspec.yaml and the same families
/// named in the theme's fontFamilyFallback (the engine only tests coverage
/// against the families a TextStyle names).
void main() {
  group('bundled text fallbacks (federfall-sbtx)', () {
    test(
      'every fallback family is declared in pubspec.yaml with its asset',
      () {
        final pubspec = File('pubspec.yaml').readAsStringSync();

        for (final family in AppTheme.fontFallbacks) {
          expect(
            pubspec,
            contains('- family: $family'),
            reason:
                '$family is in AppTheme.fontFallbacks but not bundled — the '
                'engine would download it from fonts.gstatic.com instead.',
          );
        }

        // The asset files themselves, not just the declarations: a missing .ttf
        // fails at runtime, and only on the platform that needs the glyph.
        for (final asset in const <String>[
          'assets/fonts/NotoSansSymbols-Regular.ttf',
          'assets/fonts/NotoSansSymbols2-Regular.ttf',
          'assets/fonts/NotoColorEmoji.ttf',
        ]) {
          expect(pubspec, contains(asset));
          expect(
            File(asset).existsSync(),
            isTrue,
            reason: '$asset is declared in pubspec.yaml but missing on disk',
          );
        }
      },
    );

    test('both themes apply the fallbacks to their text styles', () {
      for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
        expect(theme.textTheme.bodyMedium?.fontFamily, 'Roboto');
        expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback,
          AppTheme.fontFallbacks,
        );
      }
    });
  });
}

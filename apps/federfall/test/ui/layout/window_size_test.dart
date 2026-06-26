import 'package:federfall/ui/layout/window_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('windowSizeClassFor', () {
    test('maps widths to Material 3 window-size classes', () {
      expect(windowSizeClassFor(0), WindowSizeClass.compact);
      expect(windowSizeClassFor(599), WindowSizeClass.compact);
      expect(windowSizeClassFor(600), WindowSizeClass.medium);
      expect(windowSizeClassFor(839), WindowSizeClass.medium);
      expect(windowSizeClassFor(840), WindowSizeClass.expanded);
      expect(windowSizeClassFor(1440), WindowSizeClass.expanded);
    });

    test('only expanded reports isExpanded', () {
      expect(WindowSizeClass.compact.isExpanded, isFalse);
      expect(WindowSizeClass.medium.isExpanded, isFalse);
      expect(WindowSizeClass.expanded.isExpanded, isTrue);
    });
  });

  group('isDetailLocation', () {
    test('true for a section item detail', () {
      expect(isDetailLocation('/cases/abc123'), isTrue);
      expect(isDetailLocation('/animals/a1'), isTrue);
      expect(isDetailLocation('/aviaries/v9'), isTrue);
      expect(isDetailLocation('/cases/abc123?tab=history'), isTrue);
    });

    test('false for section roots and reserved sub-routes', () {
      expect(isDetailLocation('/cases'), isFalse);
      expect(isDetailLocation('/cases/new'), isFalse);
      expect(isDetailLocation('/cases/browse'), isFalse);
      expect(isDetailLocation('/animals'), isFalse);
    });

    test('false for unrelated and deeper paths', () {
      expect(isDetailLocation('/admin/team'), isFalse);
      expect(isDetailLocation('/cases/abc/extra'), isFalse);
      expect(isDetailLocation('/'), isFalse);
    });
  });

  group('detailIdOf', () {
    test('returns the id for a detail location', () {
      expect(detailIdOf('/cases/abc123'), 'abc123');
      expect(detailIdOf('/animals/a1?x=y'), 'a1');
    });

    test('null when there is no selection', () {
      expect(detailIdOf('/cases'), isNull);
      expect(detailIdOf('/cases/new'), isNull);
      expect(detailIdOf('/admin/team'), isNull);
    });
  });
}

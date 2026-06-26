import 'package:federfall/ui/layout/list_detail_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: ListDetailShell(
          list: Text('THE-LIST'),
          detailChild: Text('THE-DETAIL'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compact shows only the detail child (single pane)',
      (tester) async {
    await _pumpAt(tester, const Size(400, 800));

    expect(find.text('THE-DETAIL'), findsOneWidget);
    expect(find.text('THE-LIST'), findsNothing);
  });

  testWidgets('expanded shows the list and the detail side-by-side',
      (tester) async {
    await _pumpAt(tester, const Size(1000, 800));

    expect(find.text('THE-LIST'), findsOneWidget);
    expect(find.text('THE-DETAIL'), findsOneWidget);
  });
}

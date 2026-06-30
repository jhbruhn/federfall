import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/markings/marking_sheet.dart';
import 'package:federfall/features/cases/markings/marking_tile.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockMarkingsRepo markings;

  setUp(() {
    markings = MockMarkingsRepo();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        markingsRepositoryProvider.overrideWith((ref) async => markings),
        markingTypesProvider.overrideWith(
          (ref) async =>
              const [MarkingType(id: 'mktp_finder', label: "Finder's ring")],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('applying a marking records animal, case, type and active',
      (tester) async {
    when(() => markings.create(any())).thenAnswer(
      (_) async => const Marking(
        id: 'm1',
        animal: 'a1',
        type: 'mktp_finder',
      ),
    );

    await pump(
      tester,
      const MarkingSheet(animalId: 'a1', caseId: 'c1'),
    );
    await tester.enterText(find.byType(TextField).first, 'AT-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body =
        verify(() => markings.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['animal'], 'a1');
    expect(body['applied_in_case'], 'c1');
    expect(body['type'], 'mktp_finder');
    expect(body['code'], 'AT-123');
    expect(body['is_active'], true);
  });

  testWidgets('marking tile shows details and can be marked removed',
      (tester) async {
    when(() => markings.update('m1', any())).thenAnswer(
      (_) async => const Marking(
        id: 'm1',
        animal: 'a1',
        type: 'mktp_finder',
      ),
    );

    await pump(
      tester,
      const MarkingTile(
        marking: Marking(
          id: 'm1',
          animal: 'a1',
          type: 'mktp_finder',
          code: 'AT-123',
          colour: 'blue',
          isActive: true,
        ),
        caseId: 'c1',
      ),
    );

    expect(find.text("Finder's ring"), findsOneWidget);
    expect(find.text('blue · AT-123'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark removed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Mark removed'));
    await tester.pumpAndSettle();

    final body = verify(() => markings.update('m1', captureAny()))
        .captured
        .single as Map<String, dynamic>;
    expect(body['is_active'], false);
    expect(body.containsKey('removed_at'), isTrue);
  });
}

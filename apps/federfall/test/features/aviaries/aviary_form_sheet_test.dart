import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/aviary_form_sheet.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAviariesRepo extends Mock implements PbAviariesRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockAviariesRepo aviaries;

  setUp(() {
    aviaries = MockAviariesRepo();
  });

  Future<void> pump(
    WidgetTester tester, {
    Aviary? aviary,
    List<AppUser> members = const [],
    UserRole? role,
  }) async {
    // Taller than the 600px default: the sheet is a scroll view on a real
    // device, but in a test it is laid out at the view size, so one more line
    // of helper text under the keeper field pushes Save out of hit-test range.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              AppUser(id: 'u1', email: 'me@x.org', org: 'org1', role: role),
        ),
        aviariesRepositoryProvider.overrideWith((ref) async => aviaries),
        orgMembersProvider.overrideWith((ref) async => members),
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
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAviaryFormSheet(context, aviary: aviary),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // federfall-q7ks.1: the keeper is required too, so an empty form reports
  // BOTH fields — an aviary with nobody answering for it is not a saveable
  // thing any more.
  testWidgets('creating an aviary requires a name and a keeper', (
    tester,
  ) async {
    await pump(
      tester,
      members: const [
        AppUser(id: 'u2', email: 'keeper@x.org', name: 'Keeper Kim'),
      ],
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsNWidgets(2));
    verifyNever(() => aviaries.create(any()));
  });

  testWidgets('naming a keeper is what unblocks the save', (tester) async {
    await pump(
      tester,
      members: const [
        AppUser(id: 'u2', email: 'keeper@x.org', name: 'Keeper Kim'),
      ],
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Voliere 1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsOneWidget);
    verifyNever(() => aviaries.create(any()));
  });

  testWidgets('creates an active aviary with a keeper', (tester) async {
    when(() => aviaries.create(any())).thenAnswer(
      (_) async => const Aviary(id: 'av1', name: 'Voliere 1', keeper: 'u2'),
    );

    await pump(
      tester,
      members: const [
        AppUser(id: 'u2', email: 'keeper@x.org', name: 'Keeper Kim'),
      ],
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Voliere 1',
    );
    // Nothing is preselected, so the dropdown is opened by its own field
    // rather than by tapping a "none" entry that no longer exists.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keeper Kim').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Capacity'),
      '12',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body =
        verify(() => aviaries.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['name'], 'Voliere 1');
    expect(body['keeper'], 'u2');
    expect(body['capacity'], 12);
    expect(body['active'], true);
    expect(body['org'], 'org1');
  });

  // federfall-t7ad: `aviaries.org` is frozen (1700000083) and its update rule
  // refuses a body that so much as MENTIONS the field — resending the unchanged
  // value made every edit 404 ("not found" on the record being edited). So the
  // assertion is about the key's absence, not its value.
  testWidgets('editing an aviary does not resend the frozen org', (
    tester,
  ) async {
    when(() => aviaries.update('av1', any())).thenAnswer(
      (_) async => const Aviary(id: 'av1', name: 'Voliere 1', keeper: 'u2'),
    );

    await pump(
      tester,
      // The keeper must be among the members: a dropdown whose selection names
      // nobody in its item list is a framework assertion, not a blank field.
      members: const [
        AppUser(id: 'u2', email: 'keeper@x.org', name: 'Keeper Kim'),
      ],
      aviary: const Aviary(
        id: 'av1',
        name: 'Voliere 1',
        keeper: 'u2',
        location: 'Nordflügel',
        capacity: 8,
        active: false,
      ),
    );

    expect(find.text('Keeper Kim'), findsOneWidget);

    expect(find.text('Voliere 1'), findsOneWidget);
    expect(find.text('Nordflügel'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body =
        verify(() => aviaries.update('av1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['name'], 'Voliere 1');
    expect(body['active'], false);
    expect(body.containsKey('org'), isFalse);
  });

  // 1700000086: the keeper edits their own enclosure, but handing it to
  // somebody else stays a coordinator's — that names another member as the
  // holder of every resident and the reader of their patronages. The rule
  // admits `keeper` from a keeper only while it still names them, and the form
  // always sends it, so the field is locked rather than dropped.
  group('the keeper field on edit', () {
    const kept = Aviary(id: 'av1', name: 'Voliere 1', keeper: 'u1');
    const members = [
      AppUser(id: 'u1', email: 'me@x.org', name: 'Keeper Kim'),
      AppUser(id: 'u2', email: 'other@x.org', name: 'Coord Chris'),
    ];

    DropdownButtonFormField<String> keeperField(WidgetTester tester) =>
        tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );

    testWidgets('is locked, and says why, for the keeper themselves', (
      tester,
    ) async {
      await pump(tester, aviary: kept, members: members, role: UserRole.carer);

      expect(keeperField(tester).onChanged, isNull);
      expect(
        find.text(
          'Only coordination or management can hand this aviary to '
          'another keeper.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('is open for a coordinator', (tester) async {
      await pump(
        tester,
        aviary: kept,
        members: members,
        role: UserRole.coordinator,
      );

      expect(keeperField(tester).onChanged, isNotNull);
      expect(find.textContaining('hand this aviary'), findsNothing);
    });

    testWidgets('a locked keeper is still sent, unchanged', (tester) async {
      when(() => aviaries.update('av1', any())).thenAnswer((_) async => kept);

      await pump(tester, aviary: kept, members: members, role: UserRole.carer);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(() => aviaries.update('av1', captureAny())).captured.single
              as Map<String, dynamic>;
      // The rule reads `@request.body.keeper = @request.auth.id`, so the value
      // has to be there and has to still name them — omitting it would be
      // fine by the rule but would blank a required field.
      expect(body['keeper'], 'u1');
    });
  });
}

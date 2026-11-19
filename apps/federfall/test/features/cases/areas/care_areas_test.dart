import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/areas/care_areas_sheet.dart';
import 'package:federfall/features/cases/areas/case_area_line.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:flutter_test/flutter_test.dart' as ft show Finder;
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class _MockAreas extends Mock implements PbCareAreasRepository {}

class _MockCases extends Mock implements PbCasesRepository {}

const _me = AppUser(id: 'me', email: 'me@f.local', org: 'org1');
const _colleague = AppUser(id: 'kim', email: 'kim@f.local', name: 'Kim');

void main() {
  late _MockAreas areasRepo;
  late _MockCases casesRepo;
  late List<CareArea> stored;

  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  setUp(() {
    areasRepo = _MockAreas();
    casesRepo = _MockCases();
    stored = [
      const CareArea(id: 'quar', name: 'Quarantine', owner: 'me'),
      const CareArea(id: 'garage', name: 'Garage', owner: 'me', position: 1),
      const CareArea(id: 'balcony', name: 'Balcony', owner: 'kim'),
    ];
    when(() => areasRepo.all()).thenAnswer((_) async => stored);
    when(() => areasRepo.create(any())).thenAnswer((i) async {
      final body = i.positionalArguments.first as Map<String, dynamic>;
      final area = CareArea(
        id: 'new',
        name: body['name'] as String,
        owner: body['owner'] as String,
        position: body['position'] as int,
      );
      stored = [...stored, area];
      return area;
    });
    when(() => areasRepo.update(any(), any())).thenAnswer(
      (i) async => stored.firstWhere((a) => a.id == i.positionalArguments[0]),
    );
    when(() => areasRepo.delete(any())).thenAnswer((_) async {});
    when(
      () => casesRepo.update(any(), any()),
    ).thenAnswer((_) async => const Case(id: 'c1', animal: 'a1'));
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          careAreasRepositoryProvider.overrideWith((ref) async => areasRepo),
          casesRepositoryProvider.overrideWith((ref) async => casesRepo),
          currentUserProvider.overrideWith((ref) async => _me),
          orgMembersProvider.overrideWith((ref) async => [_me, _colleague]),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField).last, name);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  group('CareAreasSheet', () {
    testWidgets('lists only my own rooms, in my order', (tester) async {
      await pump(tester, const CareAreasSheet());

      final quar = tester.getTopLeft(find.text('Quarantine')).dy;
      expect(quar, lessThan(tester.getTopLeft(find.text('Garage')).dy));
      expect(find.text('Balcony'), findsNothing);
    });

    testWidgets('a new room goes to the end of my order, as mine', (
      tester,
    ) async {
      await pump(tester, const CareAreasSheet());

      await tester.tap(find.text('Add area'));
      await tester.pumpAndSettle();
      await enterName(tester, '  Attic ');

      final body =
          verify(() => areasRepo.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body, {
        'name': 'Attic',
        'position': 2,
        'owner': 'me',
        'org': 'org1',
      });
      expect(find.text('Attic'), findsOneWidget);
    });

    testWidgets('an empty name creates nothing', (tester) async {
      await pump(tester, const CareAreasSheet());

      await tester.tap(find.text('Add area'));
      await tester.pumpAndSettle();
      await enterName(tester, '   ');

      verifyNever(() => areasRepo.create(any()));
    });

    testWidgets('renames a room', (tester) async {
      await pump(tester, const CareAreasSheet());

      await tester.tap(find.byType(PopupMenuButton<void>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await enterName(tester, 'Isolation');

      verify(() => areasRepo.update('quar', {'name': 'Isolation'})).called(1);
    });

    testWidgets('deletes a room after asking', (tester) async {
      await pump(tester, const CareAreasSheet());

      await tester.tap(find.byType(PopupMenuButton<void>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('cases in “Garage”'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => areasRepo.delete('garage')).called(1);
    });

    testWidgets('dragging writes only the positions that moved', (
      tester,
    ) async {
      await pump(tester, const CareAreasSheet());

      final handle = find.byIcon(Icons.drag_handle).last;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      verify(() => areasRepo.update('garage', {'position': 0})).called(1);
      verify(() => areasRepo.update('quar', {'position': 1})).called(1);
    });

    testWidgets('says so when there is nothing yet', (tester) async {
      stored = const [];
      await pump(tester, const CareAreasSheet());

      expect(find.text('You have not created any areas yet.'), findsOneWidget);
    });
  });

  group('CaseAreaLine', () {
    const mine = Case(id: 'c1', animal: 'a1', activeCarer: 'me', area: 'quar');

    testWidgets('names the room', (tester) async {
      await pump(
        tester,
        const CaseAreaLine(medicalCase: mine, editable: false),
      );

      expect(find.text('Quarantine'), findsOneWidget);
    });

    testWidgets('prompts for one only when it may be set', (tester) async {
      const unplaced = Case(id: 'c1', animal: 'a1', activeCarer: 'me');
      await pump(
        tester,
        const Column(
          children: [
            CaseAreaLine(medicalCase: unplaced, editable: true),
            CaseAreaLine(medicalCase: unplaced, editable: false),
          ],
        ),
      );

      expect(find.text('Assign area'), findsOneWidget);
    });

    testWidgets('a closed case has no room', (tester) async {
      await pump(
        tester,
        const CaseAreaLine(
          medicalCase: Case(
            id: 'c1',
            animal: 'a1',
            area: 'quar',
            status: CaseStatus.disposed,
          ),
          editable: true,
        ),
      );

      expect(find.text('Quarantine'), findsNothing);
    });

    ft.Finder inPicker(String text) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(text),
    );

    testWidgets('moves the bird to another of my rooms', (tester) async {
      await pump(
        tester,
        const CaseAreaLine(medicalCase: mine, editable: true),
      );

      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();
      expect(inPicker('Balcony'), findsNothing);
      await tester.tap(inPicker('Garage'));
      await tester.pumpAndSettle();

      verify(() => casesRepo.update('c1', {'area': 'garage'})).called(1);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('"no area" clears it', (tester) async {
      await pump(
        tester,
        const CaseAreaLine(medicalCase: mine, editable: true),
      );

      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();
      await tester.tap(inPicker('No area'));
      await tester.pumpAndSettle();

      verify(() => casesRepo.update('c1', {'area': ''})).called(1);
    });

    testWidgets('a new room is created and assigned in one go', (
      tester,
    ) async {
      await pump(
        tester,
        const CaseAreaLine(medicalCase: mine, editable: true),
      );

      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();
      await tester.tap(inPicker('Add area'));
      await tester.pumpAndSettle();
      await enterName(tester, 'Attic');

      verify(() => areasRepo.create(any())).called(1);
      verify(() => casesRepo.update('c1', {'area': 'new'})).called(1);
    });

    testWidgets("someone else's case offers THEIR rooms, and says so", (
      tester,
    ) async {
      await pump(
        tester,
        const CaseAreaLine(
          medicalCase: Case(id: 'c1', animal: 'a1', activeCarer: 'kim'),
          editable: true,
        ),
      );

      await tester.tap(find.text('Assign area'));
      await tester.pumpAndSettle();

      expect(inPicker('Balcony'), findsOneWidget);
      expect(inPicker('Quarantine'), findsNothing);
      expect(find.textContaining("Kim's areas"), findsOneWidget);
      // An area is always created as the caller's own, so it could not be
      // assigned here anyway.
      expect(inPicker('Add area'), findsNothing);
    });

    testWidgets('a refused write keeps the picker open and says why', (
      tester,
    ) async {
      when(
        () => casesRepo.update(any(), any()),
      ).thenThrow(const RepositoryException('nope'));
      await pump(
        tester,
        const CaseAreaLine(medicalCase: mine, editable: true),
      );

      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();
      await tester.tap(inPicker('Garage'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}

import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/realtime/collection_events.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/features/printing/printer_service.dart';
import 'package:federfall/features/printing/printer_settings.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';

import '../printing/fake_printer_service.dart';
import '../printing/fake_printer_settings.dart';

class MockCaseReportRepo extends Mock implements PbCaseReportRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockFindersRepo extends Mock implements PbFindersRepository {}

class MockJournalRepo extends Mock implements PbJournalRepository {}

class MockWeightsRepo extends Mock implements PbWeightsRepository {}

class MockCaseConditionsRepo extends Mock
    implements PbCaseConditionsRepository {}

class MockMedicationsRepo extends Mock implements PbMedicationsRepository {}

class MockAdministrationsRepo extends Mock
    implements PbMedicationAdministrationsRepository {}

class MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

class MockPlacementsRepo extends Mock implements PbPlacementsRepository {}

class MockDispositionsRepo extends Mock implements PbDispositionsRepository {}

class MockFollowUpsRepo extends Mock implements PbFollowUpsRepository {}

class MockExamsRepo extends Mock implements PbExamsRepository {}

class MockExamFindingsRepo extends Mock implements PbExamFindingsRepository {}

class MockQuarantineRepo extends Mock implements PbQuarantineRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockCasesRepo cases;
  late MockAnimalsRepo animals;
  late MockFindersRepo finders;
  late MockJournalRepo journal;
  late MockWeightsRepo weights;
  late MockCaseConditionsRepo caseConditions;
  late MockMedicationsRepo medications;
  late MockAdministrationsRepo administrations;
  late MockMarkingsRepo markings;
  late MockPlacementsRepo placements;
  late MockDispositionsRepo dispositions;
  late MockFollowUpsRepo followUps;
  late MockExamsRepo exams;
  late MockExamFindingsRepo examFindings;
  late MockQuarantineRepo quarantine;

  final medicalCase = Case(
    id: 'c1',
    animal: 'a1',
    caseNumber: '2026-001',
    status: CaseStatus.inCare,
    ageClass: AgeClass.adult,
    admissionReasons: const ['adre1'],
    findLocation: 'Domplatz',
    intakeWeightG: 250,
    intakeNotes: 'thin but alert',
    finder: 'f1',
    foundAt: DateTime.utc(2026, 6, 20),
    admittedAt: DateTime.utc(2026, 6, 21),
    created: DateTime.utc(2026, 6, 21, 9),
  );

  setUp(() {
    cases = MockCasesRepo();
    animals = MockAnimalsRepo();
    finders = MockFindersRepo();
    journal = MockJournalRepo();
    weights = MockWeightsRepo();
    caseConditions = MockCaseConditionsRepo();
    medications = MockMedicationsRepo();
    administrations = MockAdministrationsRepo();
    markings = MockMarkingsRepo();
    placements = MockPlacementsRepo();
    dispositions = MockDispositionsRepo();
    followUps = MockFollowUpsRepo();
    exams = MockExamsRepo();
    examFindings = MockExamFindingsRepo();
    quarantine = MockQuarantineRepo();
    when(() => quarantine.forCase(any())).thenAnswer((_) async => []);
    when(() => followUps.forCase(any())).thenAnswer((_) async => []);
    when(() => exams.forCase(any())).thenAnswer((_) async => []);
    when(() => examFindings.forCase(any())).thenAnswer((_) async => []);
    when(() => placements.forCase(any())).thenAnswer((_) async => []);
    when(() => dispositions.forCase(any())).thenAnswer((_) async => []);
    when(() => journal.forCase(any())).thenAnswer((_) async => []);
    when(() => weights.forCase(any())).thenAnswer((_) async => []);
    when(() => caseConditions.forCase(any())).thenAnswer((_) async => []);
    when(() => medications.forCase(any())).thenAnswer((_) async => []);
    when(() => administrations.forCase(any())).thenAnswer((_) async => []);
    when(() => markings.forAnimal(any())).thenAnswer((_) async => []);
    when(() => cases.getOne(any())).thenAnswer((_) async => medicalCase);
    // The detail reads everything off the case bundle (federfall-kh0u);
    // assemble it from the leaf repo mocks, so the per-test `forCase` /
    // `getOne` stubs keep driving what the screen shows.
    when(() => cases.bundle(any())).thenAnswer((inv) async {
      final id = inv.positionalArguments.single as String;
      final c = await cases.getOne(id);
      return CaseBundle(
        medicalCase: c,
        journal: await journal.forCase(id),
        weights: await weights.forCase(id),
        caseConditions: await caseConditions.forCase(id),
        medications: await medications.forCase(id),
        administrations: await administrations.forCase(id),
        markings: await markings.forAnimal(c.animal),
        placements: await placements.forCase(id),
        dispositions: await dispositions.forCase(id),
        followUps: await followUps.forCase(id),
        exams: await exams.forCase(id),
        examFindings: await examFindings.forCase(id),
        quarantines: await quarantine.forCase(id),
      );
    });
    when(() => animals.getOne(any())).thenAnswer(
      (_) async => const Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
    );
    when(() => finders.getOne(any())).thenAnswer(
      (_) async => const Finder(id: 'f1', lastName: 'Klein', phone: '0151'),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    AnimalLifetime? lifetime,
    AppUser? currentUser,
    double width = 420,
    // Photo tiles show a perpetually-spinning placeholder for images that
    // never resolve in tests (no real network), so pumpAndSettle would hang
    // whenever a case has photos — pass false and settle with bounded pumps.
    bool settle = true,
    PbCaseReportRepository? caseReport,
    FakePrinterService? printerService,
  }) async {
    // A tall surface so the whole scroll view (incl. the timeline) is built.
    // [width] defaults narrow so the case detail renders its compact, tabbed
    // form; the wide Overview|History split has its own test.
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        // case_realtime.dart's live-refresh listens to collectionEventsProvider
        // for 14 collections, which chains through pocketBaseProvider (a real
        // client construction reading stored server config). Left
        // un-isolated, tests implicitly depended on that whole chain failing
        // silently rather than actually being decoupled from it — harmless
        // until something (e.g. an explicit SharedPreferences mock install
        // elsewhere in the same test) perturbed the timing enough to turn a
        // latent retry loop into a hard "Timer still pending" failure.
        // Mirrors medication_reminders_test.dart's isolation of the same
        // family provider.
        collectionEventsProvider.overrideWith(
          (ref, collection) => const Stream<RecordSubscriptionEvent>.empty(),
        ),
        // Overrides the abstraction instead of seeding real
        // shared_preferences (see fake_printer_settings.dart) — avoids ever
        // touching the platform channel from this widget test.
        printerSettingsProvider.overrideWith(
          () => FakePrinterSettingsNotifier(
            PrinterSettings(
              device: printerService == null
                  ? null
                  : const NetworkPrinterDeviceRef(
                      name: 'Epson TM-T88IV',
                      host: '10.0.0.5',
                    ),
            ),
          ),
        ),
        casesRepositoryProvider.overrideWith((ref) async => cases),
        admissionReasonsProvider.overrideWith(
          (ref) async => const [AdmissionReason(id: 'adre1', label: 'Injury')],
        ),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        findersRepositoryProvider.overrideWith((ref) async => finders),
        journalRepositoryProvider.overrideWith((ref) async => journal),
        weightsRepositoryProvider.overrideWith((ref) async => weights),
        caseConditionsRepositoryProvider.overrideWith(
          (ref) async => caseConditions,
        ),
        medicationsRepositoryProvider.overrideWith((ref) async => medications),
        medicationAdministrationsRepositoryProvider.overrideWith(
          (ref) async => administrations,
        ),
        markingsRepositoryProvider.overrideWith((ref) async => markings),
        placementsRepositoryProvider.overrideWith((ref) async => placements),
        dispositionsRepositoryProvider.overrideWith(
          (ref) async => dispositions,
        ),
        followUpsRepositoryProvider.overrideWith((ref) async => followUps),
        examsRepositoryProvider.overrideWith((ref) async => exams),
        examFindingsRepositoryProvider.overrideWith(
          (ref) async => examFindings,
        ),
        quarantineRepositoryProvider.overrideWith((ref) async => quarantine),
        if (lifetime != null)
          animalLifetimeProvider('a1').overrideWith((ref) async => lifetime),
        if (currentUser != null)
          currentUserProvider.overrideWith((ref) async => currentUser),
        if (caseReport != null)
          caseReportRepositoryProvider.overrideWith((ref) async => caseReport),
        if (printerService != null)
          printerServiceProvider.overrideWithValue(printerService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CaseDetailScreen(caseId: 'c1'),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  testWidgets('renders a name-first header with species and case number', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Pauli'), findsOneWidget);
    expect(find.text('Stadttaube · 2026-001'), findsOneWidget);
    expect(find.text('In care'), findsOneWidget);
  });

  testWidgets('shows the intake summary and the linked finder', (tester) async {
    await pump(tester);

    expect(find.text('Domplatz'), findsOneWidget);
    // Quarantine is no longer a static Overview row — it lives on the timeline
    // (History) as its own record kind (federfall-uvm).
    expect(find.text('Quarantine until'), findsNothing);
    expect(find.text('thin but alert'), findsOneWidget);
    expect(find.text('Klein · 0151'), findsOneWidget);
  });

  testWidgets(
    'Overview renders intake dates in local time, matching the History tab',
    (tester) async {
      // PocketBase stores UTC; the Overview used to format it without
      // .toLocal(), so a near-midnight-UTC instant showed a different
      // calendar day than the History timeline (which converts to local).
      // Regression guard for that split — both must agree.
      final foundInstant = DateTime.utc(2026, 6, 20, 23, 30);
      when(() => cases.getOne(any())).thenAnswer(
        // Same instant for found + admitted so the Overview intake rows and the
        // History "Admitted" milestone must all resolve to the same day; a
        // distinct `created` keeps the History count unambiguous.
        (_) async => medicalCase.copyWith(
          foundAt: foundInstant,
          admittedAt: foundInstant,
          created: DateTime.utc(2026, 3, 10, 9),
        ),
      );

      await pump(tester);

      // Expected string via the shared helper against the real localizations,
      // so this holds in any timezone (in UTC CI toLocal is a no-op; on a
      // machine at UTC+2 the un-converted code would render the prior day).
      final ml = MaterialLocalizations.of(tester.element(find.text('Pauli')));
      final expected = formatEventDate(ml, foundInstant);
      // Overview: both the "Found on" and "Admitted on" rows show that day.
      expect(find.text(expected), findsNWidgets(2));

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      // History: the "Admitted" milestone shows the very same day.
      expect(find.text(expected), findsOneWidget);
    },
  );

  testWidgets('lists intake milestones in the History tab', (tester) async {
    await pump(tester);

    // The chronology lives behind the History tab.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Admitted'), findsOneWidget);
    expect(find.text('Case opened'), findsOneWidget);
  });

  testWidgets('shows Overview and History side-by-side on a wide pane', (
    tester,
  ) async {
    await pump(tester, width: 1000);

    // No tabs on a wide pane — both columns are visible at once, so the intake
    // summary (Overview) and the chronology (History) show together.
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Domplatz'), findsOneWidget);
    expect(find.text('Admitted'), findsOneWidget);
    expect(find.text('Case opened'), findsOneWidget);
  });

  testWidgets("Overview lists the animal's other cases", (tester) async {
    await pump(
      tester,
      lifetime: const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
        markings: [],
        cases: [
          // The current case plus an older, accessible one.
          CaseSummary(id: 'c1', animal: 'a1', caseNumber: '2026-001'),
          CaseSummary(
            id: 'c0',
            animal: 'a1',
            caseNumber: '2025-009',
            status: CaseStatus.disposed,
          ),
        ],
        accessibleCaseIds: {'c1', 'c0'},
      ),
    );

    expect(find.text('Other cases'), findsOneWidget);
    // The other case shows; the current case (c1) is excluded from the list.
    expect(find.text('2025-009'), findsOneWidget);
  });

  testWidgets('Overview hides prior cases when there are none', (tester) async {
    await pump(
      tester,
      lifetime: const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
        markings: [],
        cases: [CaseSummary(id: 'c1', animal: 'a1', caseNumber: '2026-001')],
        accessibleCaseIds: {'c1'},
      ),
    );

    expect(find.text('Other cases'), findsNothing);
  });

  testWidgets('a supervisor can mark an in-care case ready for release', (
    tester,
  ) async {
    when(() => cases.update(any(), any())).thenAnswer(
      (_) async => medicalCase,
    );

    await pump(
      tester,
      currentUser: const AppUser(
        id: 'sup1',
        email: 'sup@x.org',
        role: UserRole.supervisor,
      ),
    );

    await tester.tap(find.text('Mark ready for release'));
    await tester.pumpAndSettle();

    final data =
        verify(() => cases.update('c1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['status'], 'ready_for_release');
  });

  testWidgets('a read-only viewer sees no status control', (tester) async {
    await pump(
      tester,
      currentUser: const AppUser(
        id: 'other',
        email: 'other@x.org',
        role: UserRole.carer,
      ),
    );

    expect(find.text('Mark ready for release'), findsNothing);
  });

  testWidgets(
    'Overview shows a consolidated, chronologically-ordered photo gallery; '
    'tapping a tile opens the viewer',
    (tester) async {
      Uri urlFor(
        String recordId,
        String filename, {
        String? thumb,
      }) => Uri.parse(
        'https://x.test/$recordId/$filename${thumb == null ? '' : '?thumb=$thumb'}',
      );
      when(
        () => cases.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      ).thenAnswer(
        (inv) => urlFor(
          inv.positionalArguments[0] as String,
          inv.positionalArguments[1] as String,
          thumb: inv.namedArguments[#thumb] as String?,
        ),
      );
      when(() => cases.fileUrl(any(), any())).thenAnswer(
        (inv) => urlFor(
          inv.positionalArguments[0] as String,
          inv.positionalArguments[1] as String,
        ),
      );
      when(
        () => journal.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      ).thenAnswer(
        (inv) => urlFor(
          inv.positionalArguments[0] as String,
          inv.positionalArguments[1] as String,
          thumb: inv.namedArguments[#thumb] as String?,
        ),
      );
      when(() => journal.fileUrl(any(), any())).thenAnswer(
        (inv) => urlFor(
          inv.positionalArguments[0] as String,
          inv.positionalArguments[1] as String,
        ),
      );
      when(() => cases.getOne(any())).thenAnswer(
        (_) async => medicalCase.copyWith(intakePhotos: const ['intake.jpg']),
      );
      when(() => journal.forCase(any())).thenAnswer(
        (_) async => [
          // Before the intake date (2026-06-21) — sorts first.
          JournalEntry(
            id: 'j1',
            text: 'early',
            entryAt: DateTime.utc(2026, 6, 20),
            attachments: const ['early.jpg'],
          ),
          // After the intake date — sorts last.
          JournalEntry(
            id: 'j2',
            text: 'late',
            entryAt: DateTime.utc(2026, 6, 25),
            attachments: const ['late.jpg'],
          ),
        ],
      );

      await pump(tester, settle: false);

      expect(find.text('Photos'), findsOneWidget);
      expect(find.bySemanticsLabel('View photo 1 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('View photo 3 of 3'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('casePhoto-https://x.test/j1/early.jpg?thumb=200x200'),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final viewer = tester.widget<ImageViewerScreen>(
        find.byType(ImageViewerScreen),
      );
      expect(viewer.imageUrls, [
        'https://x.test/j1/early.jpg',
        'https://x.test/c1/intake.jpg',
        'https://x.test/j2/late.jpg',
      ]);
      expect(viewer.initialIndex, 0);
    },
  );

  testWidgets('Overview renders no photo gallery when the case has none', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Photos'), findsNothing);
  });

  testWidgets('printing with no printer configured shows a snackbar', (
    tester,
  ) async {
    final caseReport = MockCaseReportRepo();
    await pump(tester, caseReport: caseReport);

    await tester.tap(find.byTooltip('Print receipt'));
    await tester.pumpAndSettle();

    expect(find.text('No printer configured'), findsOneWidget);
    verifyNever(
      () => caseReport.fetchReceiptPng(
        any(),
        widthDots: any(named: 'widthDots'),
      ),
    );
  });

  testWidgets(
    'printing with a configured printer fetches the receipt and prints it',
    (tester) async {
      final caseReport = MockCaseReportRepo();
      final receiptBytes = Uint8List.fromList([1, 2, 3]);
      when(
        () => caseReport.fetchReceiptPng(
          any(),
          widthDots: any(named: 'widthDots'),
          lang: any(named: 'lang'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).thenAnswer((_) async => receiptBytes);
      final printer = FakePrinterService();
      await pump(tester, caseReport: caseReport, printerService: printer);

      await tester.tap(find.byTooltip('Print receipt'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => caseReport.fetchReceiptPng(
          'c1',
          widthDots: captureAny(named: 'widthDots'),
          lang: any(named: 'lang'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).captured;
      expect(captured.single, ReceiptPaperSize.mm72.widthPixels);
      expect(printer.connected, hasLength(1));
      expect(printer.receiptsPrinted, hasLength(1));
      expect(printer.receiptsPrinted.single.$1, receiptBytes);
      expect(printer.disconnectCalls, 1);
    },
  );

  testWidgets('a failed print surfaces an error and still disconnects', (
    tester,
  ) async {
    final caseReport = MockCaseReportRepo();
    when(
      () => caseReport.fetchReceiptPng(
        any(),
        widthDots: any(named: 'widthDots'),
        lang: any(named: 'lang'),
        tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
      ),
    ).thenThrow(Exception('offline'));
    final printer = FakePrinterService();
    await pump(tester, caseReport: caseReport, printerService: printer);

    await tester.tap(find.byTooltip('Print receipt'));
    await tester.pumpAndSettle();

    expect(printer.receiptsPrinted, isEmpty);
    expect(printer.disconnectCalls, 1);
  });
}

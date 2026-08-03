import 'package:federfall/core/calendar/calendar_export.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/vet_appointments/vet_appointment_calendar.dart';
import 'package:federfall/features/cases/vet_appointments/vet_appointment_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:shared_preferences/shared_preferences.dart';

/// A [CalendarExporter] that records what it was handed instead of talking to a
/// method channel, and reports whatever the test wants back.
class FakeCalendarExporter implements CalendarExporter {
  FakeCalendarExporter({this.isSupported = true, this.result = true});

  @override
  final bool isSupported;

  /// What the OS hand-off resolves to — false covers both "no calendar app" and
  /// "the user cancelled the editor".
  final bool result;

  final events = <CalendarEvent>[];

  @override
  Future<bool> add(CalendarEvent event) async {
    events.add(event);
    return result;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final startsAt = DateTime.now().toUtc().add(const Duration(days: 3));

  const medicalCase = Case(
    id: 'c1',
    animal: 'a1',
    caseNumber: '2026-001',
    status: CaseStatus.inCare,
  );

  Future<FakeCalendarExporter> pumpTile(
    WidgetTester tester, {
    required VetAppointment appointment,
    bool isSupported = true,
    bool result = true,
  }) async {
    final exporter = FakeCalendarExporter(
      isSupported: isSupported,
      result: result,
    );
    final container = ProviderContainer(
      overrides: [
        calendarExporterProvider.overrideWithValue(exporter),
        caseBundleProvider('c1').overrideWith(
          (ref) async => const CaseBundle(
            medicalCase: medicalCase,
            animal: Animal(id: 'a1', species: 'Columba livia', name: 'Bella'),
          ),
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
          home: Scaffold(
            body: VetAppointmentTile(appointment: appointment, caseId: 'c1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return exporter;
  }

  VetAppointment appointment({
    DateTime? at,
    DateTime? attendedAt,
    DateTime? cancelledAt,
  }) => VetAppointment(
    id: 'va1',
    caseId: 'c1',
    startsAt: at ?? startsAt,
    vet: 'Praxis Müller',
    reason: 'Wing check',
    attendedAt: attendedAt,
    cancelledAt: cancelledAt,
  );

  group('VetAppointmentTile calendar export', () {
    testWidgets('hands the appointment to the calendar', (tester) async {
      final exporter = await pumpTile(tester, appointment: appointment());

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      expect(exporter.events, hasLength(1));
      final event = exporter.events.single;
      expect(event.title, 'Vet appointment: Praxis Müller');
      expect(event.start, startsAt.toLocal());
      expect(
        event.end,
        startsAt.toLocal().add(kVetAppointmentCalendarDuration),
      );
      // The bird the appointment is for, then why — read off the case bundle.
      expect(event.description, '2026-001 · Bella\n\nWing check');
      // No stored lead and no mute: the device default (one day) applies.
      expect(event.reminder, const Duration(days: 1));
      expect(find.text('Nothing was added to the calendar.'), findsNothing);
    });

    testWidgets('reports when nothing was added', (tester) async {
      await pumpTile(tester, appointment: appointment(), result: false);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      // Android's insert intent resolving to nothing is otherwise completely
      // silent, which would read as success.
      expect(find.text('Nothing was added to the calendar.'), findsOneWidget);
    });

    testWidgets('offers nothing on a platform without a calendar', (
      tester,
    ) async {
      await pumpTile(
        tester,
        appointment: appointment(),
        isSupported: false,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Add to calendar'), findsNothing);
    });

    testWidgets('hides the action once the visit is settled or past', (
      tester,
    ) async {
      Future<void> expectHidden(VetAppointment a) async {
        await pumpTile(tester, appointment: a);
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        expect(find.text('Add to calendar'), findsNothing);
        // Close the menu before the next pump replaces the tree under it.
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }

      await expectHidden(appointment(attendedAt: DateTime.now().toUtc()));
      await expectHidden(appointment(cancelledAt: DateTime.now().toUtc()));
      await expectHidden(
        appointment(
          at: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        ),
      );
    });
  });
}

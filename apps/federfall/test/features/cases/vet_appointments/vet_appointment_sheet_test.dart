import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/vet_appointments/vet_appointment_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockVetAppointmentsRepo extends Mock
    implements PbVetAppointmentsRepository {}

VetAppointment _appointment({
  DateTime? startsAt,
  DateTime? attendedAt,
  int? leadMinutes,
  bool muted = false,
  String? outcome,
}) => VetAppointment(
  id: 'v1',
  caseId: 'c1',
  startsAt: startsAt ?? DateTime.now().toUtc().add(const Duration(days: 3)),
  vet: 'Praxis Dr. Vogel',
  reason: 'Röntgen der Schwinge',
  outcome: outcome,
  attendedAt: attendedAt,
  reminderLeadMinutes: leadMinutes,
  reminderMuted: muted,
);

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockVetAppointmentsRepo appointments;

  setUp(() {
    appointments = MockVetAppointmentsRepo();
    when(() => appointments.create(any())).thenAnswer(
      (_) async => const VetAppointment(id: 'v9', caseId: 'c1'),
    );
    when(() => appointments.update(any(), any())).thenAnswer(
      (_) async => const VetAppointment(id: 'v1', caseId: 'c1'),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    VetAppointment? appointment,
    bool focusOutcome = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async => const AppUser(
            id: 'u1',
            email: 'me@x.org',
            org: 'org1',
            role: UserRole.carer,
          ),
        ),
        vetAppointmentsRepositoryProvider.overrideWith(
          (ref) async => appointments,
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
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showVetAppointmentSheet(
                  context,
                  caseId: 'c1',
                  appointment: appointment,
                  focusOutcome: focusOutcome,
                ),
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

  Future<void> save(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> captureCreate() =>
      verify(() => appointments.create(captureAny())).captured.single
          as Map<String, dynamic>;

  testWidgets('a new appointment defaults to 9:00 tomorrow', (tester) async {
    await pump(tester);

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final shown = tester
        .widget<DateField>(find.widgetWithText(DateField, 'Appointment'))
        .value!;
    // Nobody books a vet for "right now"; the default is one fewer tap than a
    // picker starting at the current minute.
    expect(shown.hour, 9);
    expect(shown.day, tomorrow.day);
    // A local wall-clock time, sent as UTC.
    expect(shown.isUtc, isFalse);

    await save(tester);
    final body = captureCreate();
    expect(DateTime.parse(body['starts_at'] as String).isUtc, isTrue);
    expect(body['case'], 'c1');
    expect(body['created_by'], 'u1');
    expect(body['org'], 'org1');
  });

  testWidgets('the practice and the reason reach the record', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Practice'),
      'Praxis Dr. Vogel',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Röntgen der Schwinge',
    );
    await save(tester);

    final body = captureCreate();
    expect(body['vet'], 'Praxis Dr. Vogel');
    expect(body['reason'], 'Röntgen der Schwinge');
  });

  // The outcome box is hidden until it can honestly be filled in: an empty
  // "Ergebnis" on a future appointment invites writing down a result nobody
  // has yet.
  testWidgets('a future appointment offers no outcome field', (tester) async {
    await pump(tester, appointment: _appointment());
    expect(find.widgetWithText(TextField, 'Outcome'), findsNothing);

    await save(tester);
    final captured =
        verify(() => appointments.update('v1', captureAny())).captured.single
            as Map<String, dynamic>;
    // Not merely empty — absent, so a stored outcome could never be wiped by
    // saving an edit made before the visit.
    expect(captured.containsKey('outcome'), isFalse);
  });

  testWidgets('a visit already behind us can record its outcome', (
    tester,
  ) async {
    await pump(
      tester,
      appointment: _appointment(
        startsAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ),
    );

    expect(find.text('Edit vet appointment'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Outcome'),
      'Fracture healed',
    );
    await save(tester);

    final captured =
        verify(() => appointments.update('v1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(captured['outcome'], 'Fracture healed');
  });

  testWidgets('an attended appointment offers the outcome even when it is '
      'still in the future', (tester) async {
    await pump(
      tester,
      appointment: _appointment(attendedAt: DateTime.now().toUtc()),
      focusOutcome: true,
    );

    expect(find.widgetWithText(TextField, 'Outcome'), findsOneWidget);
  });

  testWidgets('the reminder follows the device default until one is picked', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Default'), findsOneWidget);

    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 h before').last);
    await tester.pumpAndSettle();

    expect(find.text('3 h before'), findsOneWidget);
    await save(tester);
    expect(captureCreate()['reminder_lead_minutes'], 180);
  });

  testWidgets('muting keeps the chosen lead, so un-muting restores it', (
    tester,
  ) async {
    await pump(tester, appointment: _appointment(leadMinutes: 180));
    expect(find.text('3 h before'), findsOneWidget);

    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    expect(find.text('None'), findsOneWidget);

    await save(tester);
    final captured =
        verify(() => appointments.update('v1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(captured['reminder_muted'], isTrue);
    // The lead survives the mute — that is what makes un-muting restore it
    // instead of silently reverting to the device default.
    expect(captured['reminder_lead_minutes'], 180);
  });

  testWidgets('"follow the device default" is written as the empty value', (
    tester,
  ) async {
    await pump(tester);
    await save(tester);

    // PocketBase has no null for a number field; '' reads back as 0 and the
    // mapper turns it into null again.
    final body = captureCreate();
    expect(body['reminder_lead_minutes'], '');
    expect(body['reminder_muted'], isFalse);
  });

  testWidgets('a failed save is reported and the sheet stays open', (
    tester,
  ) async {
    when(() => appointments.create(any())).thenThrow(
      const RepositoryException('nope'),
    );

    await pump(tester);
    await save(tester);

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Vet appointment'), findsOneWidget);
  });
}

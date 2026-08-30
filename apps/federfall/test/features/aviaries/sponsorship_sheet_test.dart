import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/sponsorship_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSponsorshipsRepo extends Mock implements PbSponsorshipsRepository {}

/// A patronage as the server hands it back: cents, not euros, and UTC dates.
final _existing = Sponsorship(
  id: 's1',
  animal: 'a1',
  sponsorName: 'Marlene Wolf',
  sponsorPronouns: 'she/her',
  address: 'Lindenweg 4',
  postalCode: '24103',
  city: 'Kiel',
  mobile: '+49 170 1234567',
  amountCents: 1250,
  interval: SponsorshipInterval.monthly,
  startedAt: DateTime.utc(2026, 3),
  notes: 'Pays by standing order',
);

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockSponsorshipsRepo sponsorships;

  setUp(() {
    sponsorships = MockSponsorshipsRepo();
    when(() => sponsorships.create(any())).thenAnswer(
      (_) async => const Sponsorship(id: 's9', animal: 'a1', sponsorName: 'x'),
    );
    when(() => sponsorships.update(any(), any())).thenAnswer(
      (_) async => const Sponsorship(id: 's1', animal: 'a1', sponsorName: 'x'),
    );
  });

  Future<void> pump(WidgetTester tester, {Sponsorship? sponsorship}) async {
    // Taller than the 600px default: the sheet is a scroll view on a device,
    // but a test lays it out at the view size, and the nine fields would put
    // Save out of hit-test range.
    tester.view.physicalSize = const Size(800, 2400);
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
        sponsorshipsRepositoryProvider.overrideWith(
          (ref) async => sponsorships,
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
                onPressed: () => showSponsorshipSheet(
                  context,
                  animalId: 'a1',
                  sponsorship: sponsorship,
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
      verify(() => sponsorships.create(captureAny())).captured.single
          as Map<String, dynamic>;

  testWidgets('a patronage needs a sponsor, and nothing else', (tester) async {
    await pump(tester);
    await save(tester);

    // The name is the only required field: an arrangement whose amount is not
    // settled yet is still worth recording.
    expect(find.text('This field is required'), findsOneWidget);
    verifyNever(() => sponsorships.create(any()));

    await tester.enterText(
      find.widgetWithText(TextField, 'Sponsor'),
      'Marlene Wolf',
    );
    await save(tester);

    final body = captureCreate();
    expect(body['sponsor_name'], 'Marlene Wolf');
    expect(body['amount_cents'], isNull);
  });

  testWidgets('an amount that is not a number is refused', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Sponsor'), 'W');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1.2.3');
    await save(tester);

    expect(find.text('Enter an amount such as 12.50'), findsOneWidget);
    verifyNever(() => sponsorships.create(any()));
  });

  testWidgets('a decimal comma reaches the record as cents', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Sponsor'), 'W');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '12,50');
    await save(tester);

    // Money is integer cents on the wire, parsed at this one edge.
    expect(captureCreate()['amount_cents'], 1250);
  });

  testWidgets('a create carries the bird and the org, and starts today', (
    tester,
  ) async {
    await pump(tester);
    for (final (label, value) in const [
      ('Sponsor', 'Marlene Wolf'),
      ('Pronouns', 'she/her'),
      ('Mobile', '+49 170 1234567'),
      ('Street and number', 'Lindenweg 4'),
      ('Postcode', '24103'),
      ('Town', 'Kiel'),
      ('Region', 'Schleswig-Holstein'),
      ('Notes', 'Pays by standing order'),
    ]) {
      await tester.enterText(find.widgetWithText(TextField, label), value);
    }
    await save(tester);

    final body = captureCreate();
    expect(body['sponsor_name'], 'Marlene Wolf');
    expect(body['sponsor_pronouns'], 'she/her');
    expect(body['mobile'], '+49 170 1234567');
    expect(body['address'], 'Lindenweg 4');
    expect(body['postal_code'], '24103');
    expect(body['city'], 'Kiel');
    expect(body['region'], 'Schleswig-Holstein');
    expect(body['notes'], 'Pays by standing order');
    // Both are frozen on update (1700000085), so they are sent exactly once.
    expect(body['animal'], 'a1');
    expect(body['org'], 'org1');
    // Monthly is the default, and a new arrangement starts today.
    expect(body['interval'], 'monthly');
    expect(
      DateTime.parse(body['started_at'] as String).toLocal().day,
      DateTime.now().day,
    );
  });

  testWidgets('picking one-off sends that interval', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Sponsor'), 'W');
    await tester.tap(find.byType(DropdownButtonFormField<SponsorshipInterval>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('one-off').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(captureCreate()['interval'], 'one_time');
  });

  testWidgets('clearing the start date sends an empty string, not a null', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Sponsor'), 'W');
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(DateField, 'Start'),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No date'), findsOneWidget);
    await save(tester);

    // A cleared field has to be cleared server-side; an omitted key would
    // leave the old value standing.
    expect(captureCreate()['started_at'], '');
  });

  testWidgets('editing seeds every field and updates instead of creating', (
    tester,
  ) async {
    await pump(tester, sponsorship: _existing);

    expect(find.text('Edit sponsorship'), findsOneWidget);
    String textOf(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(textOf('Sponsor'), 'Marlene Wolf');
    expect(textOf('Town'), 'Kiel');
    // Cents come back as a plain locale-formatted number — no currency symbol
    // inside a value somebody is about to edit.
    expect(textOf('Amount'), '12.5');
    // Still running, so the end date says so rather than „no date".
    expect(find.text('Still running'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Town'), 'Flensburg');
    await save(tester);

    final captured =
        verify(
              () => sponsorships.update('s1', captureAny()),
            ).captured.single
            as Map<String, dynamic>;
    expect(captured['city'], 'Flensburg');
    // Frozen server-side, so the form must not resend them.
    expect(captured.containsKey('animal'), isFalse);
    expect(captured.containsKey('org'), isFalse);
    verifyNever(() => sponsorships.create(any()));
  });

  testWidgets('a failed save is reported and the sheet stays open', (
    tester,
  ) async {
    when(() => sponsorships.create(any())).thenThrow(
      const RepositoryException('refused'),
    );

    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Sponsor'), 'W');
    await save(tester);

    // The raw exception text never reaches the reader: errorMessage() maps
    // the kind to localized copy, and a bare one is generic.
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Add sponsorship'), findsOneWidget);
  });
}

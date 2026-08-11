import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_detail_screen.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/sponsorship_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_sheet.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSponsorshipsRepo extends Mock implements PbSponsorshipsRepository {}

const _animal = Animal(
  id: 'a1',
  species: 'Columba livia',
  name: 'Pip',
  currentAviary: 'av1',
);

const _sponsorship = Sponsorship(
  id: 's1',
  animal: 'a1',
  sponsorName: 'Marlene Wolf',
  amountCents: 1250,
  interval: SponsorshipInterval.monthly,
);

/// `av1` is kept by `me`, `av2` by somebody else — the whole point of every
/// assertion below is which of the two the bird lives in.
const _mine = Aviary(id: 'av1', name: 'Freiflug', keeper: 'me');
const _theirs = Aviary(id: 'av2', name: 'Quarantäne 1', keeper: 'other');

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockSponsorshipsRepo sponsorships;

  setUp(() {
    sponsorships = MockSponsorshipsRepo();
    when(() => sponsorships.forAnimal(any())).thenAnswer(
      (_) async => const [_sponsorship],
    );
    when(() => sponsorships.countForAnimal(any())).thenAnswer((_) async => 1);
  });

  /// The animal detail screen, with the sponsorship ACCESS predicate left real:
  /// the point of these tests is that it resolves off the bird's current
  /// enclosure and the viewer's role, so overriding it would test nothing.
  Future<void> pumpDetail(
    WidgetTester tester, {
    required UserRole role,
    Animal animal = _animal,
    List<Aviary> aviaries = const [_mine, _theirs],
  }) async {
    // The detail is a lazy ListView of cards; the default viewport stops
    // building before the sponsorship card would mount.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animalLifetimeProvider('a1').overrideWith(
            (ref) async => AnimalLifetime(
              animal: animal,
              markings: const [],
              cases: const [],
              accessibleCaseIds: const {},
            ),
          ),
          animalByIdProvider('a1').overrideWith((ref) async => animal),
          for (final a in aviaries)
            aviaryByIdProvider(a.id).overrideWith((ref) async => a),
          weightsForAnimalProvider('a1').overrideWith((ref) async => const []),
          eggsForAnimalProvider('a1').overrideWith((ref) async => const []),
          examsForAnimalProvider('a1').overrideWith((ref) async => const []),
          vaccinationsForAnimalProvider(
            'a1',
          ).overrideWith((ref) async => const []),
          markingTypesProvider.overrideWith((ref) async => const []),
          canWriteAnimalProvider('a1').overrideWith((ref) async => true),
          canOpenCaseOnAnimalProvider('a1').overrideWith((ref) async => true),
          currentUserProvider.overrideWith(
            (ref) async =>
                AppUser(id: 'me', email: 'me@x.org', org: 'org1', role: role),
          ),
          sponsorshipsRepositoryProvider.overrideWith(
            (ref) async => sponsorships,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AnimalDetailScreen(animalId: 'a1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the sponsorship section', () {
    testWidgets('shows the patronage to the keeper of the bird’s aviary', (
      tester,
    ) async {
      await pumpDetail(tester, role: UserRole.carer);

      expect(find.text('Sponsorships'), findsOneWidget);
      expect(find.text('Marlene Wolf'), findsOneWidget);
      // €12.50 monthly — stored in cents, rendered at the edge.
      expect(find.textContaining('12.50'), findsOneWidget);
      expect(find.byTooltip('Add sponsorship'), findsOneWidget);
    });

    testWidgets('is absent — not empty — for a carer who keeps no aviary', (
      tester,
    ) async {
      // Same bird, same everything, except it lives in somebody else's
      // enclosure. An empty „Sponsorships" card would itself disclose that this
      // bird has a sponsor, so the section must not render at all.
      await pumpDetail(
        tester,
        role: UserRole.carer,
        animal: _animal.copyWith(currentAviary: 'av2'),
      );

      expect(find.text('Sponsorships'), findsNothing);
      expect(find.text('Marlene Wolf'), findsNothing);
      expect(find.text('No sponsorship recorded'), findsNothing);
    });

    testWidgets('a coordinator reads it even once the bird has left care', (
      tester,
    ) async {
      // No enclosure: no keeper can reach the row, which is exactly when
      // winding a patronage down becomes a coordinator's job. Read yes, write
      // no — there is no enclosure to record a new one on.
      await pumpDetail(
        tester,
        role: UserRole.coordinator,
        animal: _animal.copyWith(currentAviary: null),
      );

      expect(find.text('Marlene Wolf'), findsOneWidget);
      expect(find.byTooltip('Add sponsorship'), findsNothing);
    });
  });

  group('ending a patronage', () {
    testWidgets('one tap writes today as the end date, after confirming', (
      tester,
    ) async {
      when(() => sponsorships.update(any(), any())).thenAnswer(
        (_) async => _sponsorship.copyWith(endedAt: DateTime.now().toUtc()),
      );
      await pumpDetail(tester, role: UserRole.carer);
      await tester.tap(find.text('Marlene Wolf'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('End patronage'));
      await tester.pumpAndSettle();
      // The confirmation names the date it is about to write, and says the
      // record is kept — an ended patronage is never scrubbed
      // (federfall-5s5j.4), so this is a date and not a deletion.
      expect(find.text('End this patronage?'), findsOneWidget);
      expect(find.textContaining('kept in full'), findsOneWidget);

      await tester.tap(find.text('End it'));
      await tester.pumpAndSettle();

      final values =
          verify(
                () => sponsorships.update('s1', captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(values.keys, ['ended_at']);
      final written = DateTime.parse(values['ended_at'] as String);
      expect(
        written.difference(DateTime.now().toUtc()).inMinutes.abs(),
        lessThan(2),
      );
    });

    testWidgets('backing out of the confirmation writes nothing', (
      tester,
    ) async {
      await pumpDetail(tester, role: UserRole.carer);
      await tester.tap(find.text('Marlene Wolf'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('End patronage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => sponsorships.update(any(), any()));
    });

    testWidgets('an already-ended patronage is not offered it again', (
      tester,
    ) async {
      // The button would silently move an end date that is already set.
      when(() => sponsorships.forAnimal(any())).thenAnswer(
        (_) async => [
          _sponsorship.copyWith(
            endedAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          ),
        ],
      );
      await pumpDetail(tester, role: UserRole.carer);
      await tester.tap(find.text('Marlene Wolf'));
      await tester.pumpAndSettle();

      expect(find.text('End patronage'), findsNothing);
      expect(find.text('Edit sponsorship'), findsOneWidget);
    });

    testWidgets('a reader who may not write is not offered it', (tester) async {
      // A coordinator reading the patronages of a bird that has left aviary
      // care: they wind them down through a coordinator's own edit, and nobody
      // may write to a patronage whose bird lives nowhere.
      await pumpDetail(
        tester,
        role: UserRole.coordinator,
        animal: _animal.copyWith(currentAviary: null),
      );
      await tester.tap(find.text('Marlene Wolf'));
      await tester.pumpAndSettle();

      expect(find.text('End patronage'), findsNothing);
    });
  });

  group('the detail sheet', () {
    testWidgets('tapping a patronage opens its full record, read-only', (
      tester,
    ) async {
      when(() => sponsorships.forAnimal(any())).thenAnswer(
        (_) async => const [
          Sponsorship(
            id: 's1',
            animal: 'a1',
            sponsorName: 'Marlene Wolf',
            sponsorPronouns: 'sie/ihr',
            mobile: '0170 1234567',
            address: 'Bahnhofstr. 3',
            postalCode: '26121',
            city: 'Oldenburg',
            notes: 'Möchte jährlich ein Foto.',
            amountCents: 1250,
            interval: SponsorshipInterval.monthly,
          ),
        ],
      );
      await pumpDetail(tester, role: UserRole.carer);

      await tester.tap(find.text('Marlene Wolf'));
      await tester.pumpAndSettle();

      // Everything the card could not show, which is why this sheet exists.
      expect(find.text('sie/ihr'), findsOneWidget);
      expect(find.text('0170 1234567'), findsOneWidget);
      expect(find.textContaining('26121 Oldenburg'), findsOneWidget);
      expect(find.text('Möchte jährlich ein Foto.'), findsOneWidget);
      // An unset end date is a fact, not a blank.
      expect(find.text('Still running'), findsWidgets);
      // The keeper may write, so the sheet offers the way in.
      expect(
        find.widgetWithText(OutlinedButton, 'Edit sponsorship'),
        findsOneWidget,
      );
    });

    testWidgets('a reader who may not write gets the record without an edit '
        'control', (tester) async {
      // The gap this sheet closes: a coordinator looking at a bird that has
      // left aviary care may READ the patronage and may not edit it, so before
      // this sheet the address and the mobile were unreachable for them.
      await pumpDetail(
        tester,
        role: UserRole.coordinator,
        animal: _animal.copyWith(currentAviary: null),
      );

      await tester.tap(find.text('Marlene Wolf'));
      await tester.pumpAndSettle();

      expect(find.textContaining('12.50'), findsWidgets);
      expect(
        find.widgetWithText(OutlinedButton, 'Edit sponsorship'),
        findsNothing,
      );
    });
  });

  group('the aviary-transfer warning', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required int count,
      String? currentAviary = 'av1',
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            caseBundleProvider('c1').overrideWith(
              (ref) async => CaseBundle(
                medicalCase: const Case(id: 'c1', animal: 'a1'),
                animal: _animal.copyWith(currentAviary: currentAviary),
              ),
            ),
            animalByIdProvider('a1').overrideWith(
              (ref) async => _animal.copyWith(currentAviary: currentAviary),
            ),
            sponsorshipCountForAnimalProvider(
              'a1',
            ).overrideWith((ref) async => count),
            activeAviariesProvider.overrideWith(
              (ref) async => const [_mine, _theirs],
            ),
            orgMembersByIdProvider.overrideWith(
              (ref) async => const {
                'other': AppUser(
                  id: 'other',
                  email: 'ida@x.org',
                  org: 'org1',
                  name: 'Ida Berg',
                ),
              },
            ),
            currentUserProvider.overrideWith(
              (ref) async =>
                  const AppUser(id: 'me', email: 'me@x.org', org: 'org1'),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: DispositionSheet(caseId: 'c1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Switches the outcome dropdown to "Placed in aviary" and picks [aviary].
    Future<void> placeIn(WidgetTester tester, String aviary) async {
      await tester.tap(find.text('Released'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Placed in aviary').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aviary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(aviary).last);
      await tester.pumpAndSettle();
    }

    testWidgets('names the gaining keeper and counts the patronages', (
      tester,
    ) async {
      await pumpSheet(tester, count: 2);
      await placeIn(tester, 'Quarantäne 1');

      // The count and the keeper's name, and never a sponsor's name.
      expect(find.textContaining('2 sponsorships'), findsOneWidget);
      expect(find.textContaining('Ida Berg'), findsOneWidget);
      expect(find.textContaining('Marlene'), findsNothing);
    });

    testWidgets('stays absent when the bird is placed where it already is', (
      tester,
    ) async {
      await pumpSheet(tester, count: 2);
      await placeIn(tester, 'Freiflug');

      // A re-save of the same placement transfers nothing, so there is nothing
      // to warn about.
      expect(find.textContaining('sponsorships'), findsNothing);
    });

    testWidgets('stays absent for an unsponsored bird', (tester) async {
      await pumpSheet(tester, count: 0);
      await placeIn(tester, 'Quarantäne 1');

      expect(find.textContaining('sponsorship'), findsNothing);
    });

    testWidgets('warns that release leaves the patronage coordinator-only', (
      tester,
    ) async {
      // The default outcome is "Released", which clears `current_aviary` — so
      // the notice is already up without touching the form.
      await pumpSheet(tester, count: 1);

      expect(
        find.textContaining('no longer be visible to any keeper'),
        findsOneWidget,
      );
    });

    testWidgets('release warns nothing for a bird already out of an aviary', (
      tester,
    ) async {
      await pumpSheet(tester, count: 1, currentAviary: null);

      expect(find.textContaining('no longer be visible'), findsNothing);
    });
  });
}

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show pocketBaseProvider;

/// One row per provider in `repository_providers.dart`. The file is forty-odd
/// near-identical one-liners, which is exactly the shape a copy-paste binds to
/// the wrong repository class in — and nothing else would notice, because the
/// screen that reads it only ever sees the interface it expected.
typedef _Row = (
  String name,
  Future<Object> Function(ProviderContainer),
  Matcher,
);

void main() {
  final pb = PocketBase('https://pigeons.example');

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [pocketBaseProvider.overrideWith((ref) async => pb)],
    );
    addTearDown(c.dispose);
    return c;
  }

  final rows = <_Row>[
    (
      'authRepository',
      (c) => c.read(authRepositoryProvider.future),
      isA<AuthRepository>(),
    ),
    (
      'casesRepository',
      (c) => c.read(casesRepositoryProvider.future),
      isA<PbCasesRepository>(),
    ),
    (
      'auditEventsRepository',
      (c) => c.read(auditEventsRepositoryProvider.future),
      isA<PbAuditEventsRepository>(),
    ),
    (
      'animalsRepository',
      (c) => c.read(animalsRepositoryProvider.future),
      isA<PbAnimalsRepository>(),
    ),
    (
      'animalSpeciesRepository',
      (c) => c.read(animalSpeciesRepositoryProvider.future),
      isA<PbAnimalSpeciesRepository>(),
    ),
    (
      'conditionLabelsRepository',
      (c) => c.read(conditionLabelsRepositoryProvider.future),
      isA<PbConditionLabelsRepository>(),
    ),
    (
      'carerLoadRepository',
      (c) => c.read(carerLoadRepositoryProvider.future),
      isA<PbCarerLoadRepository>(),
    ),
    (
      'findersRepository',
      (c) => c.read(findersRepositoryProvider.future),
      isA<PbFindersRepository>(),
    ),
    (
      'aviariesRepository',
      (c) => c.read(aviariesRepositoryProvider.future),
      isA<PbAviariesRepository>(),
    ),
    (
      'aviaryStaysRepository',
      (c) => c.read(aviaryStaysRepositoryProvider.future),
      isA<PbAviaryStaysRepository>(),
    ),
    (
      'conditionsRepository',
      (c) => c.read(conditionsRepositoryProvider.future),
      isA<PbConditionsRepository>(),
    ),
    (
      'admissionReasonsRepository',
      (c) => c.read(admissionReasonsRepositoryProvider.future),
      isA<PbAdmissionReasonsRepository>(),
    ),
    (
      'caseConditionsRepository',
      (c) => c.read(caseConditionsRepositoryProvider.future),
      isA<PbCaseConditionsRepository>(),
    ),
    (
      'weightsRepository',
      (c) => c.read(weightsRepositoryProvider.future),
      isA<PbWeightsRepository>(),
    ),
    (
      'eggRecordsRepository',
      (c) => c.read(eggRecordsRepositoryProvider.future),
      isA<PbEggRecordsRepository>(),
    ),
    (
      'vaccinationsRepository',
      (c) => c.read(vaccinationsRepositoryProvider.future),
      isA<PbVaccinationsRepository>(),
    ),
    (
      'vaccineLabelsRepository',
      (c) => c.read(vaccineLabelsRepositoryProvider.future),
      isA<PbVaccineLabelsRepository>(),
    ),
    (
      'medicationsRepository',
      (c) => c.read(medicationsRepositoryProvider.future),
      isA<PbMedicationsRepository>(),
    ),
    (
      'medicationAdministrationsRepository',
      (c) => c.read(medicationAdministrationsRepositoryProvider.future),
      isA<PbMedicationAdministrationsRepository>(),
    ),
    (
      'journalRepository',
      (c) => c.read(journalRepositoryProvider.future),
      isA<PbJournalRepository>(),
    ),
    (
      'followUpsRepository',
      (c) => c.read(followUpsRepositoryProvider.future),
      isA<PbFollowUpsRepository>(),
    ),
    (
      'vetAppointmentsRepository',
      (c) => c.read(vetAppointmentsRepositoryProvider.future),
      isA<PbVetAppointmentsRepository>(),
    ),
    (
      'medicationDueRepository',
      (c) => c.read(medicationDueRepositoryProvider.future),
      isA<PbMedicationDueRepository>(),
    ),
    (
      'placementsRepository',
      (c) => c.read(placementsRepositoryProvider.future),
      isA<PbPlacementsRepository>(),
    ),
    (
      'examsRepository',
      (c) => c.read(examsRepositoryProvider.future),
      isA<PbExamsRepository>(),
    ),
    (
      'examFindingsRepository',
      (c) => c.read(examFindingsRepositoryProvider.future),
      isA<PbExamFindingsRepository>(),
    ),
    (
      'microscopySamplesRepository',
      (c) => c.read(microscopySamplesRepositoryProvider.future),
      isA<PbMicroscopySamplesRepository>(),
    ),
    (
      'microscopyFindingsRepository',
      (c) => c.read(microscopyFindingsRepositoryProvider.future),
      isA<PbMicroscopyFindingsRepository>(),
    ),
    (
      'microscopyFindingTypesRepository',
      (c) => c.read(microscopyFindingTypesRepositoryProvider.future),
      isA<PbMicroscopyFindingTypesRepository>(),
    ),
    (
      'markingsRepository',
      (c) => c.read(markingsRepositoryProvider.future),
      isA<PbMarkingsRepository>(),
    ),
    (
      'markingTypesRepository',
      (c) => c.read(markingTypesRepositoryProvider.future),
      isA<PbMarkingTypesRepository>(),
    ),
    (
      'medicationRoutesRepository',
      (c) => c.read(medicationRoutesRepositoryProvider.future),
      isA<PbMedicationRoutesRepository>(),
    ),
    (
      'medicationProductsRepository',
      (c) => c.read(medicationProductsRepositoryProvider.future),
      isA<PbMedicationProductsRepository>(),
    ),
    (
      'dispositionsRepository',
      (c) => c.read(dispositionsRepositoryProvider.future),
      isA<PbDispositionsRepository>(),
    ),
    (
      'caseSharesRepository',
      (c) => c.read(caseSharesRepositoryProvider.future),
      isA<PbCaseSharesRepository>(),
    ),
    (
      'caseSummariesRepository',
      (c) => c.read(caseSummariesRepositoryProvider.future),
      isA<PbCaseSummariesRepository>(),
    ),
    (
      'caseActivityRepository',
      (c) => c.read(caseActivityRepositoryProvider.future),
      isA<PbCaseLastActivityRepository>(),
    ),
    (
      'quarantineRepository',
      (c) => c.read(quarantineRepositoryProvider.future),
      isA<PbQuarantineRepository>(),
    ),
    (
      'caseQuarantineRepository',
      (c) => c.read(caseQuarantineRepositoryProvider.future),
      isA<PbCaseQuarantineRepository>(),
    ),
    (
      'sponsorshipsRepository',
      (c) => c.read(sponsorshipsRepositoryProvider.future),
      isA<PbSponsorshipsRepository>(),
    ),
    (
      'usersRepository',
      (c) => c.read(usersRepositoryProvider.future),
      isA<PbUsersRepository>(),
    ),
    (
      'organisationsRepository',
      (c) => c.read(organisationsRepositoryProvider.future),
      isA<PbOrganisationsRepository>(),
    ),
    (
      'geocodingRepository',
      (c) => c.read(geocodingRepositoryProvider.future),
      isA<GeocodingRepository>(),
    ),
    (
      'caseReportRepository',
      (c) => c.read(caseReportRepositoryProvider.future),
      isA<PbCaseReportRepository>(),
    ),
    (
      'statsRepository',
      (c) => c.read(statsRepositoryProvider.future),
      isA<PbStatsRepository>(),
    ),
  ];

  test('every repository provider builds the repository it names', () async {
    final c = container();
    for (final (name, read, matcher) in rows) {
      expect(await read(c), matcher, reason: name);
    }
  });

  test('all of them share the one resolved client', () async {
    final c = container();
    for (final (name, read, _) in rows) {
      final repo = await read(c);
      // Auth and geocoding are interfaces without the base class, so they are
      // covered by the type check above and skipped here.
      if (repo is PbReadOnlyRepository) {
        expect(repo.pb, same(pb), reason: name);
      }
    }
  });

  // keepAlive: true on every one of them. A second read that rebuilt would
  // hand a screen a different repository — harmless in itself, but it would
  // also mean a fresh client resolution on every watch.
  test('a repository is built once and cached', () async {
    final c = container();
    for (final (name, read, _) in rows) {
      expect(await read(c), same(await read(c)), reason: name);
    }
  });
}

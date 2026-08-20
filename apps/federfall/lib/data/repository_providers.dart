import 'dart:async';

import 'package:federfall/core/pocketbase/pocketbase_provider.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

// The protected-file cache manager and the short-lived file token now come
// from zugvogel_pb_client (eiermann-d2a.4), which builds the cache key from the
// configured service — it was the literal 'federfallProtectedFiles', and two
// Zugvogel apps on one device must not share a store holding different users'
// files.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show fileTokenProvider, protectedFileCacheManagerProvider;

part 'repository_providers.g.dart';

/// Repository providers bind each `federfall_data` repository to the resolved
/// [PocketBase] client. This app is online-only: every read and write goes
/// straight to the server, there is no local cache.
///
/// They are async because the client is (it restores the session and depends on
/// the resolved server URL). Data providers and screens compose them via
/// `ref.watch(<repo>Provider.future)`.

Future<PocketBase> _client(Ref ref) => ref.watch(pocketBaseProvider.future);

@Riverpod(keepAlive: true)
Future<AuthRepository> authRepository(Ref ref) async =>
    PbAuthRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCasesRepository> casesRepository(Ref ref) async =>
    PbCasesRepository(await _client(ref));

/// Supervisor-only audit log. Read-only by type: the collection has no write
/// rules at all, so appending to it from the app is a compile error.
@Riverpod(keepAlive: true)
Future<PbAuditEventsRepository> auditEventsRepository(Ref ref) async =>
    PbAuditEventsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbAnimalsRepository> animalsRepository(Ref ref) async =>
    PbAnimalsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbAnimalSpeciesRepository> animalSpeciesRepository(Ref ref) async =>
    PbAnimalSpeciesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbConditionLabelsRepository> conditionLabelsRepository(Ref ref) async =>
    PbConditionLabelsRepository(await _client(ref));

/// Open caseload per team member, org-wide. Read-only by type (a view), and
/// coordinator/supervisor-scoped by its list rule — a carer reads no rows.
@Riverpod(keepAlive: true)
Future<PbCarerLoadRepository> carerLoadRepository(Ref ref) async =>
    PbCarerLoadRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbFindersRepository> findersRepository(Ref ref) async =>
    PbFindersRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbAviariesRepository> aviariesRepository(Ref ref) async =>
    PbAviariesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbAviaryStaysRepository> aviaryStaysRepository(Ref ref) async =>
    PbAviaryStaysRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbConditionsRepository> conditionsRepository(Ref ref) async =>
    PbConditionsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbAdmissionReasonsRepository> admissionReasonsRepository(
  Ref ref,
) async => PbAdmissionReasonsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCaseConditionsRepository> caseConditionsRepository(Ref ref) async =>
    PbCaseConditionsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbWeightsRepository> weightsRepository(Ref ref) async =>
    PbWeightsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbEggRecordsRepository> eggRecordsRepository(Ref ref) async =>
    PbEggRecordsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbVaccinationsRepository> vaccinationsRepository(Ref ref) async =>
    PbVaccinationsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbVaccineLabelsRepository> vaccineLabelsRepository(Ref ref) async =>
    PbVaccineLabelsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMedicationsRepository> medicationsRepository(Ref ref) async =>
    PbMedicationsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMedicationAdministrationsRepository>
medicationAdministrationsRepository(Ref ref) async =>
    PbMedicationAdministrationsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbJournalRepository> journalRepository(Ref ref) async =>
    PbJournalRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbFollowUpsRepository> followUpsRepository(Ref ref) async =>
    PbFollowUpsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbVetAppointmentsRepository> vetAppointmentsRepository(Ref ref) async =>
    PbVetAppointmentsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMedicationDueRepository> medicationDueRepository(Ref ref) async =>
    PbMedicationDueRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbPlacementsRepository> placementsRepository(Ref ref) async =>
    PbPlacementsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbExamsRepository> examsRepository(Ref ref) async =>
    PbExamsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbExamFindingsRepository> examFindingsRepository(Ref ref) async =>
    PbExamFindingsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMicroscopySamplesRepository> microscopySamplesRepository(
  Ref ref,
) async => PbMicroscopySamplesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMicroscopyFindingsRepository> microscopyFindingsRepository(
  Ref ref,
) async => PbMicroscopyFindingsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMicroscopyFindingTypesRepository> microscopyFindingTypesRepository(
  Ref ref,
) async => PbMicroscopyFindingTypesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMarkingsRepository> markingsRepository(Ref ref) async =>
    PbMarkingsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMarkingTypesRepository> markingTypesRepository(Ref ref) async =>
    PbMarkingTypesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMedicationRoutesRepository> medicationRoutesRepository(
  Ref ref,
) async => PbMedicationRoutesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbMedicationProductsRepository> medicationProductsRepository(
  Ref ref,
) async => PbMedicationProductsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbDispositionsRepository> dispositionsRepository(Ref ref) async =>
    PbDispositionsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCaseSharesRepository> caseSharesRepository(Ref ref) async =>
    PbCaseSharesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCaseSummariesRepository> caseSummariesRepository(Ref ref) async =>
    PbCaseSummariesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCaseLastActivityRepository> caseActivityRepository(Ref ref) async =>
    PbCaseLastActivityRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbQuarantineRepository> quarantineRepository(Ref ref) async =>
    PbQuarantineRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCaseQuarantineRepository> caseQuarantineRepository(Ref ref) async =>
    PbCaseQuarantineRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbSponsorshipsRepository> sponsorshipsRepository(Ref ref) async =>
    PbSponsorshipsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbUsersRepository> usersRepository(Ref ref) async =>
    PbUsersRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbOrganisationsRepository> organisationsRepository(Ref ref) async =>
    PbOrganisationsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<GeocodingRepository> geocodingRepository(Ref ref) async =>
    PbGeocodingRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCaseReportRepository> caseReportRepository(Ref ref) async =>
    PbCaseReportRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbStatsRepository> statsRepository(Ref ref) async =>
    PbStatsRepository(await _client(ref));

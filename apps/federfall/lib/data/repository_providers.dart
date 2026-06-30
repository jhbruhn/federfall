import 'dart:async';

import 'package:federfall/core/pocketbase/pocketbase_provider.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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

@Riverpod(keepAlive: true)
Future<PbAnimalsRepository> animalsRepository(Ref ref) async =>
    PbAnimalsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbFindersRepository> findersRepository(Ref ref) async =>
    PbFindersRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbAviariesRepository> aviariesRepository(Ref ref) async =>
    PbAviariesRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbConditionsRepository> conditionsRepository(Ref ref) async =>
    PbConditionsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCaseConditionsRepository> caseConditionsRepository(Ref ref) async =>
    PbCaseConditionsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbWeightsRepository> weightsRepository(Ref ref) async =>
    PbWeightsRepository(await _client(ref));

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
Future<PbMarkingsRepository> markingsRepository(Ref ref) async =>
    PbMarkingsRepository(await _client(ref));

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
Future<PbUsersRepository> usersRepository(Ref ref) async =>
    PbUsersRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbOrganisationsRepository> organisationsRepository(Ref ref) async =>
    PbOrganisationsRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<GeocodingRepository> geocodingRepository(Ref ref) async =>
    PbGeocodingRepository(await _client(ref));

/// A short-lived PocketBase file access token (FED-8.1) for fetching the
/// Protected image fields (case intake photos, journal attachments, animal
/// photo). One token is valid for any protected file the current user may read
/// (~2min server TTL), so it is minted once and reused across a screen's
/// images. The result is cached briefly and then self-invalidated so the next
/// read re-mints well before the server-side token expires; appended to file
/// URLs via `repo.fileUrl(..., token:)`.
@riverpod
Future<String> fileToken(Ref ref) async {
  final pb = await _client(ref);
  final token = await pb.files.getToken();
  // The provider may have been disposed during the awaits above; touching the
  // ref (keepAlive/onDispose) then throws, so bail with the token as-is.
  if (!ref.mounted) return token;
  // Cache under the ~2min TTL, then drop so the next read mints a fresh one.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 90), link.close);
  ref.onDispose(timer.cancel);
  return token;
}

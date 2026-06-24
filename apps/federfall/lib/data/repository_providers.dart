import 'package:federfall/core/pocketbase/pocketbase_provider.dart';
import 'package:federfall/data/cache/prefs_record_cache.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'repository_providers.g.dart';

/// Repository providers bind each `federfall_data` repository to the resolved
/// [PocketBase] client and the shared offline [RecordCache] (FED-2.6), so every
/// collection's reads are cached and stay readable without a connection.
///
/// They are async because the client is (it restores the session and depends on
/// the resolved server URL). Data providers and screens compose them via
/// `ref.watch(<repo>Provider.future)`.

/// App-wide persistent read cache shared by all repositories.
@Riverpod(keepAlive: true)
RecordCache recordCache(Ref ref) => PrefsRecordCache();

Future<PocketBase> _client(Ref ref) => ref.watch(pocketBaseProvider.future);

RecordCache _cache(Ref ref) => ref.watch(recordCacheProvider);

@Riverpod(keepAlive: true)
Future<AuthRepository> authRepository(Ref ref) async =>
    PbAuthRepository(await _client(ref));

@Riverpod(keepAlive: true)
Future<PbCasesRepository> casesRepository(Ref ref) async =>
    PbCasesRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbAnimalsRepository> animalsRepository(Ref ref) async =>
    PbAnimalsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbFindersRepository> findersRepository(Ref ref) async =>
    PbFindersRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbAviariesRepository> aviariesRepository(Ref ref) async =>
    PbAviariesRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbConditionsRepository> conditionsRepository(Ref ref) async =>
    PbConditionsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbCaseConditionsRepository> caseConditionsRepository(Ref ref) async =>
    PbCaseConditionsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbWeightsRepository> weightsRepository(Ref ref) async =>
    PbWeightsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbMedicationsRepository> medicationsRepository(Ref ref) async =>
    PbMedicationsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbMedicationAdministrationsRepository>
    medicationAdministrationsRepository(Ref ref) async =>
        PbMedicationAdministrationsRepository(
          await _client(ref),
          cache: _cache(ref),
        );

@Riverpod(keepAlive: true)
Future<PbJournalRepository> journalRepository(Ref ref) async =>
    PbJournalRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbFollowUpsRepository> followUpsRepository(Ref ref) async =>
    PbFollowUpsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbPlacementsRepository> placementsRepository(Ref ref) async =>
    PbPlacementsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbMarkingsRepository> markingsRepository(Ref ref) async =>
    PbMarkingsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbDispositionsRepository> dispositionsRepository(Ref ref) async =>
    PbDispositionsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbCaseSharesRepository> caseSharesRepository(Ref ref) async =>
    PbCaseSharesRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbCaseSummariesRepository> caseSummariesRepository(Ref ref) async =>
    PbCaseSummariesRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbCaseLastActivityRepository> caseActivityRepository(Ref ref) async =>
    PbCaseLastActivityRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbUsersRepository> usersRepository(Ref ref) async =>
    PbUsersRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<PbOrganisationsRepository> organisationsRepository(Ref ref) async =>
    PbOrganisationsRepository(await _client(ref), cache: _cache(ref));

@Riverpod(keepAlive: true)
Future<GeocodingRepository> geocodingRepository(Ref ref) async =>
    PbGeocodingRepository(await _client(ref));

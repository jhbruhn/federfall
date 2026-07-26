import 'package:federfall/features/cases/case_intake_draft.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'case_intake_draft_store.g.dart';

/// Persistence for the one in-progress [CaseIntakeDraft] (federfall-t2is).
///
/// A single slot, not a list: nobody admits two birds at once, and a queue of
/// half-finished intakes would be a worse problem than the one this solves.
abstract interface class CaseIntakeDraftStore {
  /// The stored draft, or `null` when there is none (or it is unreadable).
  Future<CaseIntakeDraft?> read();

  /// Replaces the stored draft.
  Future<void> write(CaseIntakeDraft draft);

  /// Drops the stored draft — on a finished intake or an explicit discard.
  Future<void> clear();
}

/// Native implementation backed by the platform keychain / keystore.
///
/// A draft holds the finder's contact details, so it gets the same treatment
/// as the auth token rather than plain preferences.
class SecureCaseIntakeDraftStore implements CaseIntakeDraftStore {
  SecureCaseIntakeDraftStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'federfall.case_intake_draft';

  final FlutterSecureStorage _storage;

  @override
  Future<CaseIntakeDraft?> read() async =>
      CaseIntakeDraft.decode(await _storage.read(key: _key));

  @override
  Future<void> write(CaseIntakeDraft draft) =>
      _storage.write(key: _key, value: draft.encode());

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Web fallback backed by `shared_preferences` (localStorage).
///
/// Browsers give a Flutter web app no real secure storage, so anything written
/// here is readable by any script in this origin — the same accepted tradeoff
/// the auth token already makes (`auth_token_storage.dart` documents the CSP
/// hardening it rests on). The draft's values, finder contact included, are
/// stored as they are.
///
/// Only the staged photo paths are dropped, via
/// [CaseIntakeDraft.withoutPhotoPaths] — on web they are `blob:` URLs that die
/// with the document. That reduction flags the draft `partial` so the restore
/// prompt can say the photos will not come back.
class PrefsCaseIntakeDraftStore implements CaseIntakeDraftStore {
  static const _key = 'federfall.case_intake_draft';

  @override
  Future<CaseIntakeDraft?> read() async => CaseIntakeDraft.decode(
    (await SharedPreferences.getInstance()).getString(_key),
  );

  @override
  Future<void> write(CaseIntakeDraft draft) async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        draft.withoutPhotoPaths().encode(),
      );

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

/// Selects the right [CaseIntakeDraftStore] for the current platform, exactly
/// as `authTokenStorageProvider` does.
@Riverpod(keepAlive: true)
CaseIntakeDraftStore caseIntakeDraftStore(Ref ref) =>
    kIsWeb ? PrefsCaseIntakeDraftStore() : SecureCaseIntakeDraftStore();

/// Reopens a staged photo a draft only remembers by path.
///
/// `image_picker` returns files in a cache directory the OS may clear at any
/// time, so a stored path can outlive its bytes — a restore that trusted the
/// list would hand submit a file that no longer exists. [load] answers `null`
/// for those.
///
/// A class behind a provider rather than a bare function because it touches the
/// filesystem: widget tests substitute it (like `imagePickerProvider`) since
/// real file I/O never progresses inside the test's async zone.
class StagedPhotoLoader {
  const StagedPhotoLoader();

  /// The file at [path], or `null` when it can no longer be read.
  Future<XFile?> load(String path) async {
    final file = XFile(path);
    try {
      await file.length();
      return file;
    } on Object {
      return null;
    }
  }
}

@Riverpod(keepAlive: true)
StagedPhotoLoader stagedPhotoLoader(Ref ref) => const StagedPhotoLoader();

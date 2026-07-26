import 'package:federfall/features/cases/case_intake_draft.dart';
import 'package:federfall/features/cases/case_intake_draft_store.dart';

/// In-memory [CaseIntakeDraftStore] so tests don't touch the platform
/// keystore — the real one never completes its read under `flutter test`,
/// which hangs any widget test that pumps the intake wizard.
class FakeCaseIntakeDraftStore implements CaseIntakeDraftStore {
  FakeCaseIntakeDraftStore([this.draft]);

  /// The currently stored draft, readable by tests to assert what was written.
  CaseIntakeDraft? draft;

  /// How many times [write] was called — lets a test assert that editing
  /// persists (and that an untouched wizard persists nothing).
  int writes = 0;

  /// How many times [clear] was called.
  int clears = 0;

  /// When set, [read] fails with it — for the "unreadable store" path.
  Exception? readError;

  @override
  Future<CaseIntakeDraft?> read() async {
    if (readError case final error?) throw error;
    return draft;
  }

  @override
  Future<void> write(CaseIntakeDraft draft) async {
    writes++;
    this.draft = draft;
  }

  @override
  Future<void> clear() async {
    clears++;
    draft = null;
  }
}

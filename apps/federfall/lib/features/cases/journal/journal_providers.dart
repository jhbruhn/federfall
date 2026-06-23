import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'journal_providers.g.dart';

/// Journal entries for a case, newest first (FED-4.7).
@riverpod
Future<List<JournalEntry>> journalForCase(Ref ref, String caseId) async {
  final repo = await ref.watch(journalRepositoryProvider.future);
  return repo.forCase(caseId);
}

/// Injectable image source, so tests can supply a fake picker.
@riverpod
ImagePicker imagePicker(Ref ref) => ImagePicker();

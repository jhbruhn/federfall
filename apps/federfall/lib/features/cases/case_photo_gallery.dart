import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'case_photo_gallery.g.dart';

/// One photo in the case-level gallery (federfall-6rdd): a thumbnail and
/// full-resolution URL, plus the date used to place it in the gallery.
class CasePhoto {
  const CasePhoto({required this.thumb, required this.full, this.sortAt});

  final Uri thumb;
  final Uri full;
  final DateTime? sortAt;
}

/// Every photo attached to a case — intake photos and journal attachments —
/// as one chronological gallery (oldest first), consolidating the sources
/// that used to render as separate inline strips
/// (federfall-ui-prefers-unified-consistent-views).
///
/// Both source fields are Protected (FED-8.1), but the access token is
/// appended at download time (ProtectedFileCacheManager), so the URLs built
/// here stay token-free.
@riverpod
Future<List<CasePhoto>> caseGallery(Ref ref, String caseId) async {
  final medicalCase = await ref.watch(caseByIdProvider(caseId).future);
  final journal = await ref.watch(journalForCaseProvider(caseId).future);
  final casesRepo = await ref.watch(casesRepositoryProvider.future);
  final journalRepo = await ref.watch(journalRepositoryProvider.future);

  final intakeAt =
      medicalCase.admittedAt ?? medicalCase.foundAt ?? medicalCase.created;
  final photos = <CasePhoto>[
    for (final filename in medicalCase.intakePhotos)
      CasePhoto(
        thumb: casesRepo.fileUrl(caseId, filename, thumb: '200x200'),
        full: casesRepo.fileUrl(caseId, filename),
        sortAt: intakeAt,
      ),
    for (final entry in journal)
      for (final filename in entry.attachments)
        CasePhoto(
          thumb: journalRepo.fileUrl(entry.id, filename, thumb: '200x200'),
          full: journalRepo.fileUrl(entry.id, filename),
          sortAt: entry.entryAt ?? entry.created,
        ),
  ];

  return photos..sort((a, b) {
    final at = a.sortAt;
    final bt = b.sortAt;
    if (at == null && bt == null) return 0;
    if (at == null) return -1;
    if (bt == null) return 1;
    return at.compareTo(bt);
  });
}

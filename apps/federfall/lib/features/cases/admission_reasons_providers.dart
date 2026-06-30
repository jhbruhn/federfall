import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'admission_reasons_providers.g.dart';

/// The full admission-reason code list, label-sorted. Used to populate the
/// intake picker (active entries only) and to resolve a stored reason id → its
/// label on the case detail / report (so a now-inactive entry still resolves).
@riverpod
Future<List<AdmissionReason>> admissionReasons(Ref ref) async {
  final repo = await ref.watch(admissionReasonsRepositoryProvider.future);
  return repo.list(sort: 'label');
}

/// Admission-reason code-list entries keyed by id, for label lookup.
@riverpod
Future<Map<String, AdmissionReason>> admissionReasonsById(Ref ref) async {
  final all = await ref.watch(admissionReasonsProvider.future);
  return {for (final r in all) r.id: r};
}

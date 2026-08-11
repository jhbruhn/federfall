import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'medication_products_providers.g.dart';

/// The org's whole drug catalogue, label-sorted (federfall-6d3a.3) — including
/// deactivated entries, so the admin screen can show them and an existing
/// prescription still resolves the product it was written from.
///
/// Kept alive like the route list: a small vocabulary, read whenever a
/// prescription form opens.
@Riverpod(keepAlive: true)
Future<List<MedicationProduct>> medicationProducts(Ref ref) async {
  final repo = await ref.watch(medicationProductsRepositoryProvider.future);
  return repo.codelist();
}

/// Just the entries a supervisor has left active — what the picker in the
/// prescription form offers.
@Riverpod(keepAlive: true)
Future<List<MedicationProduct>> activeMedicationProducts(Ref ref) async {
  final all = await ref.watch(medicationProductsProvider.future);
  return all.where((p) => p.active).toList(growable: false);
}

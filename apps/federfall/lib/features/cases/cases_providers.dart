import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cases_providers.g.dart';

/// The signed-in carer's own cases, newest first ("my cases", FED-3.4).
/// Empty while signed out. The access rules already scope what a carer can
/// read; this narrows further to the cases they actively carry.
@riverpod
Future<List<Case>> myCases(Ref ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const <Case>[];
  final repo = await ref.watch(casesRepositoryProvider.future);
  return repo.forCarer(user.id);
}

/// A single case by id (case detail).
@riverpod
Future<Case> caseById(Ref ref, String id) async {
  final repo = await ref.watch(casesRepositoryProvider.future);
  return repo.getOne(id);
}

/// The animal (name + species) behind a case.
@riverpod
Future<Animal> animalById(Ref ref, String id) async {
  final repo = await ref.watch(animalsRepositoryProvider.future);
  return repo.getOne(id);
}

/// The external finder linked to a case, by id (case detail).
@riverpod
Future<Finder> finderById(Ref ref, String id) async {
  final repo = await ref.watch(findersRepositoryProvider.future);
  return repo.getOne(id);
}

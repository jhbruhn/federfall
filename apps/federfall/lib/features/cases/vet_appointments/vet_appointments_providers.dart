import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vet_appointments_providers.g.dart';

/// Vet appointments for a case, soonest first (federfall-fnpo).
@riverpod
Future<List<VetAppointment>> vetAppointmentsForCase(Ref ref, String caseId) =>
    caseBundleList(ref, caseId, (b) => b.vetAppointments, () async {
      final repo = await ref.watch(vetAppointmentsRepositoryProvider.future);
      return repo.forCase(caseId);
    });

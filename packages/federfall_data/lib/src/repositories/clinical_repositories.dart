import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `weights` collection (drives the trend chart).
class PbWeightsRepository extends PbRepository<Weight> {
  PbWeightsRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'weights',
        fromRecord: Weight.fromRecord,
      );

  /// Weights for a case in chronological order (for plotting).
  Future<List<Weight>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: 'measured_at',
  );

  /// Every weight recorded for an animal across its life (FED-5yg), oldest
  /// first — the longitudinal trend independent of any single case.
  Future<List<Weight>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: 'measured_at',
  );
}

/// Repository over the `medications` collection (prescriptions).
class PbMedicationsRepository extends PbRepository<Medication> {
  PbMedicationsRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'medications',
        fromRecord: Medication.fromRecord,
      );

  /// Medications for a case, most recently started first.
  Future<List<Medication>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-started_at',
  );
}

/// Repository over the `medication_administrations` collection (doses given).
class PbMedicationAdministrationsRepository
    extends PbRepository<MedicationAdministration> {
  PbMedicationAdministrationsRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'medication_administrations',
        fromRecord: MedicationAdministration.fromRecord,
      );

  /// Administrations for a case, most recent first.
  Future<List<MedicationAdministration>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-administered_at',
  );
}

/// Repository over the `journal_entries` collection (dated log + photos).
class PbJournalRepository extends PbRepository<JournalEntry> {
  PbJournalRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'journal_entries',
        fromRecord: JournalEntry.fromRecord,
      );

  /// Journal entries for a case, newest first.
  Future<List<JournalEntry>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-entry_at',
  );
}

/// Repository over the `placements` collection (enclosure & handoff history).
class PbPlacementsRepository extends PbRepository<Placement> {
  PbPlacementsRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'placements',
        fromRecord: Placement.fromRecord,
      );

  /// Placement/handoff history for a case, newest move first.
  Future<List<Placement>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-moved_in_at',
  );
}

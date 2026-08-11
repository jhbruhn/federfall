import 'dart:async';

import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_data/src/repository_exception.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `weights` collection (drives the trend chart).
class PbWeightsRepository extends PbRepository<Weight> {
  PbWeightsRepository(PocketBase pb)
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

/// Repository over the `egg_records` collection (federfall-4agw) — egg-laying
/// as a longitudinal property of the animal.
///
/// There is no `forCase`: egg records carry no case relation at all, so a case
/// timeline derives its own membership from the animal (see [EggRecord]).
class PbEggRecordsRepository extends PbRepository<EggRecord> {
  PbEggRecordsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'egg_records',
        fromRecord: EggRecord.fromRecord,
      );

  /// Every laying event recorded for an animal, oldest first (like
  /// [PbWeightsRepository.forAnimal]) — the order both the per-month chart and
  /// clutch grouping need.
  Future<List<EggRecord>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: 'laid_at',
  );
}

/// Repository over the `vaccinations` collection (1700000087) — shots as a
/// longitudinal property of the animal.
///
/// Like [PbEggRecordsRepository] there is no `forCase`: a vaccination carries
/// no case relation, so a case timeline derives its own membership from the
/// animal (see [Vaccination]).
class PbVaccinationsRepository extends PbRepository<Vaccination> {
  PbVaccinationsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'vaccinations',
        fromRecord: Vaccination.fromRecord,
      );

  /// Every shot recorded for an animal, oldest first — the order the lifetime
  /// ledger and the per-target roll-up both read in.
  Future<List<Vaccination>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: 'administered_at',
  );

  /// Vaccinates [animalIds] with one shared record, atomically, via
  /// `POST /api/federfall/vaccinate-batch` (federfall-s63u). Returns how many
  /// rows were written.
  ///
  /// Not a client-side loop, and that is the entire point: vaccinating a flock
  /// is one act, and a connection lost halfway through N saves leaves a
  /// half-recorded enclosure in which the missing rows are indistinguishable
  /// from the birds somebody meant to skip.
  ///
  /// [payload] carries the shared fields (`vaccine` required); `animal`,
  /// `author` and `org` are the server's to set. The route refuses the WHOLE
  /// batch if any bird is in someone else's care, so callers filter by custody
  /// before offering the action — the server check is the backstop for a
  /// handover that happens mid-sheet.
  Future<int> vaccinateBatch(
    List<String> animalIds,
    Map<String, dynamic> payload, {
    String? idempotencyKey,
  }) async {
    try {
      final res = await pb
          .send<Map<String, dynamic>>(
            '/api/federfall/vaccinate-batch',
            method: 'POST',
            body: {
              'animals': animalIds,
              'vaccination': payload,
              'idempotency_key': ?idempotencyKey,
            },
          )
          .timeout(networkTimeout);
      final created = res['created'];
      return created is int ? created : animalIds.length;
    } on TimeoutException {
      // The request left the device; a slow server may still commit the batch.
      // With an idempotency key a resubmission converges on the committed
      // result, so it is an ordinary network error; without one, retrying would
      // vaccinate the flock twice.
      if (idempotencyKey != null) {
        throw const RepositoryException(
          'The server did not respond in time',
          kind: RepositoryErrorKind.network,
        );
      }
      throw const RepositoryException(
        'The server did not respond in time — the vaccinations may or may '
        'not have been saved',
        kind: RepositoryErrorKind.unknownOutcome,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }
}

/// Read-only repository over the `vaccine_labels` view (1700000088) — the
/// (vaccine, target) pairs this org has recorded, for the entry sheet's
/// suggestions.
///
/// Sorted by recency, not alphabetically: what the org vaccinated with last is
/// the likely next answer. The view is org-scoped by its own rule, so no filter
/// is needed here.
class PbVaccineLabelsRepository extends PbReadOnlyRepository<VaccineLabel> {
  PbVaccineLabelsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'vaccine_labels',
        fromRecord: VaccineLabel.fromRecord,
      );

  Future<List<VaccineLabel>> all() => list(sort: '-last_used_at');
}

/// Repository over the `medications` collection (prescriptions).
class PbMedicationsRepository extends PbRepository<Medication> {
  PbMedicationsRepository(PocketBase pb)
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

  /// How many prescriptions still name the [routeId] code-list entry — one of
  /// the three collections a `medication_routes` delete would blank, since
  /// `route` is an optional relation with `cascadeDelete: false` (same
  /// mechanism as `PbCaseConditionsRepository.countForCondition`).
  Future<int> countForRoute(String routeId) =>
      count(filter: filterExpr('route = {:r}', {'r': routeId}));
}

/// Repository over the `medication_administrations` collection (doses given).
class PbMedicationAdministrationsRepository
    extends PbRepository<MedicationAdministration> {
  PbMedicationAdministrationsRepository(PocketBase pb)
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

  /// How many logged doses still name the [routeId] code-list entry — the
  /// second of the three `medication_routes` referrers.
  Future<int> countForRoute(String routeId) =>
      count(filter: filterExpr('route = {:r}', {'r': routeId}));
}

/// Repository over the `journal_entries` collection (dated log + photos).
class PbJournalRepository extends PbRepository<JournalEntry> {
  PbJournalRepository(PocketBase pb)
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

  /// Aviary-scoped journal entries (flock-level free-text log), newest first.
  Future<List<JournalEntry>> forAviary(String aviaryId) => list(
    filter: filterExpr('aviary = {:a}', {'a': aviaryId}),
    sort: '-entry_at',
  );
}

/// Repository over the `follow_ups` collection (one-off rechecks on a case).
class PbFollowUpsRepository extends PbRepository<FollowUp> {
  PbFollowUpsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'follow_ups',
        fromRecord: FollowUp.fromRecord,
      );

  /// Follow-ups for a case, soonest due first.
  Future<List<FollowUp>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: 'due_at',
  );

  /// Open (not-yet-done) rechecks across the cases a carer is responsible for —
  /// one query for the worklist instead of one per case.
  Future<List<FollowUp>> openForCarer(String userId) => list(
    filter: filterExpr(
      'case.active_carer = {:u} && done_at = ""',
      {'u': userId},
    ),
    sort: 'due_at',
  );
}

/// Repository over the `vet_appointments` collection (booked vet visits on a
/// case).
class PbVetAppointmentsRepository extends PbRepository<VetAppointment> {
  PbVetAppointmentsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'vet_appointments',
        fromRecord: VetAppointment.fromRecord,
      );

  /// Appointments for a case, soonest first.
  Future<List<VetAppointment>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: 'starts_at',
  );

  /// Unresolved appointments across the cases a carer is responsible for — one
  /// query for the worklist instead of one per case.
  ///
  /// Bounded below by [since] so an appointment nobody ever marked attended or
  /// cancelled stops being fetched eventually. There is deliberately no upper
  /// bound: the worklist's own window decides how far ahead to *show*, and the
  /// reminder planner needs the ones beyond it.
  Future<List<VetAppointment>> openForCarer(
    String userId, {
    required DateTime since,
  }) => list(
    filter: filterExpr(
      'case.active_carer = {:u} && attended_at = "" && cancelled_at = ""'
      ' && starts_at >= {:since}',
      {'u': userId, 'since': since},
    ),
    sort: 'starts_at',
  );
}

/// Repository over the org-wide `medication_due` view (cr3.6): each active
/// prescription with its server-computed next-due time, the worklist's
/// medications-due source.
class PbMedicationDueRepository extends PbReadOnlyRepository<MedicationDue> {
  PbMedicationDueRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'medication_due',
        fromRecord: MedicationDue.fromRecord,
      );

  /// Pending doses for the signed-in carer's cases (rows with a next-due time).
  Future<List<MedicationDue>> mine(String userId) => list(
    filter: filterExpr(
      'active_carer = {:u} && next_due != ""',
      {'u': userId},
    ),
    sort: 'next_due',
  );
}

/// Repository over the `exams` collection (structured physical exams, FED-4.8).
class PbExamsRepository extends PbRepository<Exam> {
  PbExamsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'exams',
        fromRecord: Exam.fromRecord,
      );

  /// Exams for a case, most recent first (a timeline source).
  Future<List<Exam>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-examined_at',
  );

  /// Every exam recorded for an animal across its life, newest first — the
  /// lifetime view aggregating exams across cases.
  Future<List<Exam>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: '-examined_at',
  );

  /// Atomic exam save via `POST /api/federfall/exam`: persists the exam, its
  /// full findings set (replaced server-side) and an optional exam weight in
  /// one transaction, so a mid-save failure can never lose the previous
  /// findings or duplicate the exam on retry (federfall-lov0). Returns the
  /// exam id. Pass `payload['id']` to update an existing exam.
  Future<String> saveWithFindings(Map<String, dynamic> payload) async {
    try {
      final res = await pb
          .send<Map<String, dynamic>>(
            '/api/federfall/exam',
            method: 'POST',
            body: payload,
          )
          .timeout(networkTimeout);
      final id = res['id'] as String?;
      if (id == null || id.isEmpty) {
        throw const RepositoryException('malformed exam save response');
      }
      return id;
    } on TimeoutException {
      // The request left the device; a slow server may still commit the
      // exam, so a blind retry of a create can duplicate it.
      throw const RepositoryException(
        'The server did not respond in time — the exam may or may not '
        'have been saved',
        kind: RepositoryErrorKind.unknownOutcome,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }
}

/// Repository over the `exam_findings` collection (one sparse row per assessed
/// body system on an [Exam], FED-4.8).
class PbExamFindingsRepository extends PbRepository<ExamFinding> {
  PbExamFindingsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'exam_findings',
        fromRecord: ExamFinding.fromRecord,
      );

  /// Findings for a single exam (for the edit sheet), in insertion order.
  Future<List<ExamFinding>> forExam(String examId) => list(
    filter: filterExpr('exam = {:e}', {'e': examId}),
    sort: 'created',
  );

  /// Every finding across all the case's exams in ONE query (traversing the
  /// grandparent `exam.case`), for the caller to group client-side under each
  /// exam — avoids a per-exam round trip on the timeline.
  Future<List<ExamFinding>> forCase(String caseId) => list(
    filter: filterExpr('exam.case = {:c}', {'c': caseId}),
    sort: 'created',
  );
}

/// Repository over the `placements` collection (enclosure & handoff history).
class PbPlacementsRepository extends PbRepository<Placement> {
  PbPlacementsRepository(PocketBase pb)
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

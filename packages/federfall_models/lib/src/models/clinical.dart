import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'clinical.freezed.dart';

/// A single weight measurement on a case (drives the trend chart).
@freezed
abstract class Weight with _$Weight {
  const factory Weight({
    required String id,
    required String animal,
    required double weightG,
    String? caseId,
    DateTime? measuredAt,
    String? notes,
    String? author,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Weight;

  factory Weight.fromRecord(RecordModel r) {
    final d = r.data;
    return Weight(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      caseId: pbString(d['case']),
      weightG: pbDouble(d['weight_g']) ?? 0,
      measuredAt: pbDate(d['measured_at']),
      notes: pbString(d['notes']),
      author: pbString(d['author']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// A medication / prescription recorded on a case.
@freezed
abstract class Medication with _$Medication {
  const factory Medication({
    required String id,
    required String caseId,
    required String drug,
    String? concentration,
    double? dose,
    String? doseUnit,
    String? frequency,
    MedicationFrequencyKind? frequencyKind,
    int? intervalHours,
    String? route,
    DateTime? startedAt,
    DateTime? endedAt,
    @Default(false) bool isControlled,
    String? instructions,
    String? prescribedBy,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Medication;

  factory Medication.fromRecord(RecordModel r) {
    final d = r.data;
    return Medication(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      drug: pbString(d['drug']) ?? '',
      concentration: pbString(d['concentration']),
      dose: pbDouble(d['dose']),
      doseUnit: pbString(d['dose_unit']),
      frequency: pbString(d['frequency']),
      frequencyKind: MedicationFrequencyKind.fromWire(d['frequency_kind']),
      intervalHours: pbInt(d['interval_hours']),
      route: pbString(d['route']),
      startedAt: pbDate(d['started_at']),
      endedAt: pbDate(d['ended_at']),
      isControlled: pbBool(d['is_controlled']),
      instructions: pbString(d['instructions']),
      prescribedBy: pbString(d['prescribed_by']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// A prescription's next-due projection, read from the org-wide
/// `medication_due` view (cr3.6): the worklist's medications-due source in one
/// query. [nextDue] is computed server-side (last dose + interval, or start if
/// never given); null when the prescription has nothing pending.
@freezed
abstract class MedicationDue with _$MedicationDue {
  const factory MedicationDue({
    required String id,
    required String caseId,
    required String drug,
    double? dose,
    String? doseUnit,
    String? route,
    MedicationFrequencyKind? frequencyKind,
    int? intervalHours,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? nextDue,
    String? activeCarer,
    String? org,
  }) = _MedicationDue;

  factory MedicationDue.fromRecord(RecordModel r) {
    final d = r.data;
    return MedicationDue(
      id: r.id,
      caseId: pbString(d['case_id']) ?? '',
      drug: pbString(d['drug']) ?? '',
      dose: pbDouble(d['dose']),
      doseUnit: pbString(d['dose_unit']),
      route: pbString(d['route']),
      frequencyKind: MedicationFrequencyKind.fromWire(d['frequency_kind']),
      intervalHours: pbInt(d['interval_hours']),
      startedAt: pbDate(d['started_at']),
      endedAt: pbDate(d['ended_at']),
      nextDue: pbDate(d['next_due']),
      activeCarer: pbString(d['active_carer']),
      org: pbString(d['org']),
    );
  }
}

/// A dated free-text journal entry with optional photo/file attachments.
@freezed
abstract class JournalEntry with _$JournalEntry {
  const factory JournalEntry({
    required String id,
    required String caseId,
    required String text,
    DateTime? entryAt,
    @Default(<String>[]) List<String> attachments,
    String? author,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _JournalEntry;

  factory JournalEntry.fromRecord(RecordModel r) {
    final d = r.data;
    return JournalEntry(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      text: pbString(d['text']) ?? '',
      entryAt: pbDate(d['entry_at']),
      attachments: pbStringList(d['attachments']),
      author: pbString(d['author']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// A one-off, future-dated recheck on a case (cr3.4): "recheck the wound
/// Thursday". [doneAt] is set when it has been carried out; until then it is an
/// open follow-up the worklist surfaces when due.
@freezed
abstract class FollowUp with _$FollowUp {
  const factory FollowUp({
    required String id,
    required String caseId,
    DateTime? dueAt,
    String? note,
    DateTime? doneAt,
    String? createdBy,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _FollowUp;

  factory FollowUp.fromRecord(RecordModel r) {
    final d = r.data;
    return FollowUp(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      dueAt: pbDate(d['due_at']),
      note: pbString(d['note']),
      doneAt: pbDate(d['done_at']),
      createdBy: pbString(d['created_by']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// An enclosure move / handoff (chain-of-custody) record on a case.
@freezed
abstract class Placement with _$Placement {
  const factory Placement({
    required String id,
    required String caseId,
    DateTime? movedInAt,
    String? carer,
    String? whereHolding,
    String? area,
    String? enclosure,
    String? fromUser,
    String? toUser,
    String? conditionAtHandoff,
    String? comments,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Placement;

  factory Placement.fromRecord(RecordModel r) {
    final d = r.data;
    return Placement(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      movedInAt: pbDate(d['moved_in_at']),
      carer: pbString(d['carer']),
      whereHolding: pbString(d['where_holding']),
      area: pbString(d['area']),
      enclosure: pbString(d['enclosure']),
      fromUser: pbString(d['from_user']),
      toUser: pbString(d['to_user']),
      conditionAtHandoff: pbString(d['condition_at_handoff']),
      comments: pbString(d['comments']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// A single dose actually given (FED-4.6). May reference the [Medication]
/// prescription it follows, or stand alone for an ad-hoc dose; drug/dose/route
/// are denormalized so the record is meaningful without a plan.
@freezed
abstract class MedicationAdministration with _$MedicationAdministration {
  const factory MedicationAdministration({
    required String id,
    required String caseId,
    required String drug,
    String? medication,
    double? dose,
    String? doseUnit,
    String? route,
    DateTime? administeredAt,
    String? administeredBy,
    String? notes,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _MedicationAdministration;

  factory MedicationAdministration.fromRecord(RecordModel r) {
    final d = r.data;
    return MedicationAdministration(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      drug: pbString(d['drug']) ?? '',
      medication: pbString(d['medication']),
      dose: pbDouble(d['dose']),
      doseUnit: pbString(d['dose_unit']),
      route: pbString(d['route']),
      administeredAt: pbDate(d['administered_at']),
      administeredBy: pbString(d['administered_by']),
      notes: pbString(d['notes']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

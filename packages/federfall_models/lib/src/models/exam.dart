import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'exam.freezed.dart';

/// A structured physical exam recorded on a case (FED-4.8) — repeatable, so the
/// intake exam and any later re-exams are the same kind on the case timeline.
///
/// Top-line vitals are typed columns here; the open-ended by-system part lives
/// in [ExamFinding] child rows (one per system actually assessed). [animal] is
/// denormalized from the case so the animal lifetime view can aggregate exams
/// across cases.
@freezed
abstract class Exam with _$Exam {
  const factory Exam({
    required String id,
    required String caseId,
    required String animal,
    DateTime? examinedAt,
    String? examiner,
    int? bodyCondition,
    Hydration? hydration,
    Mentation? mentation,
    String? notes,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Exam;

  factory Exam.fromRecord(RecordModel r) {
    final d = r.data;
    return Exam(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      animal: pbString(d['animal']) ?? '',
      examinedAt: pbDate(d['examined_at']),
      examiner: pbString(d['examiner']),
      bodyCondition: pbInt(d['body_condition']),
      hydration: Hydration.fromWire(d['hydration']),
      mentation: Mentation.fromWire(d['mentation']),
      notes: pbString(d['notes']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// A single by-system finding on an [Exam] — one sparse row per body region the
/// examiner actually assessed (a region never looked at has no row at all).
@freezed
abstract class ExamFinding with _$ExamFinding {
  const factory ExamFinding({
    required String id,
    required String exam,
    BodySystem? system,
    FindingStatus? status,
    String? note,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _ExamFinding;

  factory ExamFinding.fromRecord(RecordModel r) {
    final d = r.data;
    return ExamFinding(
      id: r.id,
      exam: pbString(d['exam']) ?? '',
      system: BodySystem.fromWire(d['system']),
      status: FindingStatus.fromWire(d['status']),
      note: pbString(d['note']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

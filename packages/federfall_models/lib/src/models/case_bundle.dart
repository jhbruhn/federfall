import 'package:federfall_models/src/models/animal.dart';
import 'package:federfall_models/src/models/clinical.dart';
import 'package:federfall_models/src/models/condition.dart';
import 'package:federfall_models/src/models/disposition.dart';
import 'package:federfall_models/src/models/exam.dart';
import 'package:federfall_models/src/models/finder.dart';
import 'package:federfall_models/src/models/marking.dart';
import 'package:federfall_models/src/models/medical_case.dart';
import 'package:federfall_models/src/models/quarantine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'case_bundle.freezed.dart';

/// The relation-expand string that loads a whole [CaseBundle] in ONE
/// `getOne(case)` request (federfall-kh0u): the animal (with its markings),
/// the finder, and every timeline collection as a PocketBase back-relation
/// (`<collection>_via_<field>`). Expanded rows honor each collection's view
/// rule, so the org/share security boundary is unchanged.
const String caseBundleExpand =
    'animal,animal.markings_via_animal,finder,'
    'journal_entries_via_case,weights_via_case,case_conditions_via_case,'
    'medications_via_case,medication_administrations_via_case,'
    'placements_via_case,dispositions_via_case,follow_ups_via_case,'
    'exams_via_case,exams_via_case.exam_findings_via_exam,'
    'quarantine_records_via_case';

/// PocketBase truncates each expanded back-relation at 1000 records. A list
/// of exactly this length may be incomplete — consumers fall back to the
/// paged per-collection query then.
const int pbExpandListCap = 1000;

/// Everything the case detail shows, mapped from one expanded case record:
/// the case itself, its animal and finder, and all twelve timeline sources.
/// Replaces one request per collection with a single round trip, and gives
/// realtime refreshes a single provider to invalidate.
///
/// Lists come pre-sorted in the same order the per-collection repository
/// queries used (the server cannot sort expanded relations).
@freezed
abstract class CaseBundle with _$CaseBundle {
  const factory CaseBundle({
    required Case medicalCase,
    Animal? animal,
    Finder? finder,
    @Default(<JournalEntry>[]) List<JournalEntry> journal,
    @Default(<Weight>[]) List<Weight> weights,
    @Default(<CaseCondition>[]) List<CaseCondition> caseConditions,
    @Default(<Medication>[]) List<Medication> medications,
    @Default(<MedicationAdministration>[])
    List<MedicationAdministration> administrations,
    @Default(<Marking>[]) List<Marking> markings,
    @Default(<Placement>[]) List<Placement> placements,
    @Default(<Disposition>[]) List<Disposition> dispositions,
    @Default(<FollowUp>[]) List<FollowUp> followUps,
    @Default(<Exam>[]) List<Exam> exams,
    @Default(<ExamFinding>[]) List<ExamFinding> examFindings,
    @Default(<Quarantine>[]) List<Quarantine> quarantines,
  }) = _CaseBundle;

  factory CaseBundle.fromRecord(RecordModel r) {
    List<T> rel<T>(
      RecordModel of,
      String key,
      T Function(RecordModel) map, {
      DateTime? Function(T)? by,
      bool descending = false,
    }) {
      final items = of
          .get<List<RecordModel>>('expand.$key', const [])
          .map(map)
          .toList();
      if (by != null) {
        items.sort((a, b) {
          final cmp = (by(a) ?? _epoch).compareTo(by(b) ?? _epoch);
          return descending ? -cmp : cmp;
        });
      }
      return items;
    }

    // Single relations arrive as one object; an absent expand yields the
    // empty fallback record (id ''), mapped to null below.
    RecordModel? single(String key) {
      final rec = r.get<RecordModel>('expand.$key', RecordModel());
      return rec.id.isEmpty ? null : rec;
    }

    final animalRec = single('animal');
    final finderRec = single('finder');
    final exams = rel(
      r,
      'exams_via_case',
      Exam.fromRecord,
      by: (e) => e.examinedAt ?? e.created,
      descending: true,
    );
    return CaseBundle(
      medicalCase: Case.fromRecord(r),
      animal: animalRec == null ? null : Animal.fromRecord(animalRec),
      finder: finderRec == null ? null : Finder.fromRecord(finderRec),
      journal: rel(
        r,
        'journal_entries_via_case',
        JournalEntry.fromRecord,
        by: (e) => e.entryAt ?? e.created,
        descending: true,
      ),
      weights: rel(
        r,
        'weights_via_case',
        Weight.fromRecord,
        by: (w) => w.measuredAt ?? w.created,
      ),
      caseConditions: rel(
        r,
        'case_conditions_via_case',
        CaseCondition.fromRecord,
        by: (c) => c.created,
        descending: true,
      ),
      medications: rel(
        r,
        'medications_via_case',
        Medication.fromRecord,
        by: (m) => m.startedAt ?? m.created,
        descending: true,
      ),
      administrations: rel(
        r,
        'medication_administrations_via_case',
        MedicationAdministration.fromRecord,
        by: (a) => a.administeredAt ?? a.created,
        descending: true,
      ),
      markings: animalRec == null
          ? const []
          : rel(
              animalRec,
              'markings_via_animal',
              Marking.fromRecord,
              by: (m) => m.appliedAt ?? m.created,
              descending: true,
            ),
      placements: rel(
        r,
        'placements_via_case',
        Placement.fromRecord,
        by: (p) => p.movedInAt ?? p.created,
        descending: true,
      ),
      dispositions: rel(
        r,
        'dispositions_via_case',
        Disposition.fromRecord,
        by: (d) => d.disposedAt ?? d.created,
        descending: true,
      ),
      followUps: rel(
        r,
        'follow_ups_via_case',
        FollowUp.fromRecord,
        by: (f) => f.dueAt ?? f.created,
      ),
      exams: exams,
      // Findings arrive nested under their exam; flatten across the (already
      // sorted) exams, insertion order within each exam.
      examFindings: [
        for (final exam in r.get<List<RecordModel>>(
          'expand.exams_via_case',
          const [],
        ))
          ...rel(
            exam,
            'exam_findings_via_exam',
            ExamFinding.fromRecord,
            by: (f) => f.created,
          ),
      ],
      quarantines: rel(
        r,
        'quarantine_records_via_case',
        Quarantine.fromRecord,
        by: (q) => q.created,
        descending: true,
      ),
    );
  }
}

final DateTime _epoch = DateTime.utc(1970);

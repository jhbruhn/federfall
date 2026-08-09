import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'microscopy.freezed.dart';

/// A supervisor-managed vocabulary entry for a microscopic finding
/// (`microscopy_finding_types`) — Trichomonaden, Hefen, Spulwurmeier…
///
/// [sampleTypes] is the one field this code list has beyond the shared
/// `{label, active}` shape, and it is why there is ONE list rather than two:
/// *Hefen* occurs in both a crop swab and a faecal sample, and two lists would
/// have to be kept in step by hand.
///
/// "Sonstiges" is deliberately not an entry — it is the free-text path on a
/// [MicroscopyFinding], so a supervisor cannot rename or delete the escape
/// hatch itself.
@freezed
abstract class MicroscopyFindingType with _$MicroscopyFindingType {
  const factory MicroscopyFindingType({
    required String id,
    required String label,
    @Default(<MicroscopySampleType>[]) List<MicroscopySampleType> sampleTypes,
    String? description,
    @Default(true) bool active,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _MicroscopyFindingType;

  factory MicroscopyFindingType.fromRecord(RecordModel r) {
    final d = r.data;
    return MicroscopyFindingType(
      id: r.id,
      label: pbString(d['label']) ?? '',
      sampleTypes: pbEnumList(
        MicroscopySampleType.values,
        (e) => e.wire,
        d['sample_types'],
      ),
      description: pbString(d['description']),
      active: pbBool(d['active']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// One microscopic examination of one sample taken from a case
/// (`microscopy_samples`) — the parent of a set of graded [MicroscopyFinding]s
/// that is replaced wholesale on every save.
///
/// There is deliberately no `animal` field: the animal lifetime roll-up is
/// deferred (federfall-h27q), and without the relation `merge_animals.pb.js`
/// cannot silently destroy a sample it forgot to re-point (federfall-0ua6).
/// A sample follows its case, and the merge already re-points cases.
///
/// [noFindings] is a positive assertion about the whole sample, which is what
/// separates the three states this workflow has:
///
/// | `noFindings` | findings | meaning |
/// |---|---|---|
/// | false | none | result pending — taken, sent to the lab, not read yet |
/// | true | none | *ohne Befund* — looked, found nothing |
/// | false | N | N graded findings |
@freezed
abstract class MicroscopySample with _$MicroscopySample {
  const factory MicroscopySample({
    required String id,
    required String caseId,
    MicroscopySampleType? sampleType,

    /// Faecal only; the server clears it for a crop swab.
    MicroscopyMethod? method,
    DateTime? examinedAt,
    MicroscopyExaminedBy? examinedBy,

    /// The in-house user who looked down the microscope.
    String? examiner,

    /// The practice or laboratory, when it was not done in-house.
    String? externalLab,
    @Default(false) bool noFindings,

    /// Stored filenames on the `attachments` file field — photos **and**
    /// video. PocketBase generates thumbs for images only, so a consumer must
    /// branch on the extension rather than request one for every entry.
    @Default(<String>[]) List<String> attachments,
    String? notes,
    String? author,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _MicroscopySample;

  factory MicroscopySample.fromRecord(RecordModel r) {
    final d = r.data;
    return MicroscopySample(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      sampleType: MicroscopySampleType.fromWire(d['sample_type']),
      method: MicroscopyMethod.fromWire(d['method']),
      examinedAt: pbDate(d['examined_at']),
      examinedBy: MicroscopyExaminedBy.fromWire(d['examined_by']),
      examiner: pbString(d['examiner']),
      externalLab: pbString(d['external_lab']),
      noFindings: pbBool(d['no_findings']),
      attachments: pbStringList(d['attachments']),
      notes: pbString(d['notes']),
      author: pbString(d['author']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// One graded finding on a [MicroscopySample] (`microscopy_findings`) — either
/// a [MicroscopyFindingType] reference or [freeText], never both.
///
/// [severity] is required, because "ohne Befund" lives on the sample: a finding
/// that exists at all was found at some strength.
@freezed
abstract class MicroscopyFinding with _$MicroscopyFinding {
  const factory MicroscopyFinding({
    required String id,
    required String sample,
    String? findingType,
    String? freeText,
    MicroscopySeverity? severity,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _MicroscopyFinding;

  factory MicroscopyFinding.fromRecord(RecordModel r) {
    final d = r.data;
    return MicroscopyFinding(
      id: r.id,
      sample: pbString(d['sample']) ?? '',
      findingType: pbString(d['finding_type']),
      freeText: pbString(d['free_text']),
      severity: MicroscopySeverity.fromWire(d['severity']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

import 'dart:async';

import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_data/src/repositories/codelist_repository.dart';
import 'package:federfall_data/src/repository_exception.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `microscopy_samples` collection (one microscopic
/// examination of a crop swab or faecal sample).
///
/// There is no `forAnimal`: samples carry no animal relation at all — the
/// lifetime roll-up is deferred and the relation is what would let a merge
/// destroy them (see [MicroscopySample]).
class PbMicroscopySamplesRepository extends PbRepository<MicroscopySample> {
  PbMicroscopySamplesRepository(PocketBase pb, {super.networkTimeout})
    : super(
        pb: pb,
        collection: 'microscopy_samples',
        fromRecord: MicroscopySample.fromRecord,
      );

  /// Samples for a case, most recent first (a timeline source).
  Future<List<MicroscopySample>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-examined_at',
  );

  /// Atomic microscopy save via `POST /api/federfall/microscopy`: persists the
  /// sample, its full findings set (replaced server-side) and the attachments
  /// in ONE transaction, so a mid-save failure can never lose the previous
  /// findings or duplicate the sample on retry (federfall-lov0, found on the
  /// exam sheet). Returns the sample id.
  ///
  /// [payload] is sent as the multipart `@jsonPayload` part when [attachments]
  /// is non-empty, and as a plain JSON body otherwise — `pb.send` picks the
  /// encoding. Pass `payload['id']` to update an existing sample; on an update
  /// `payload['keep_attachments']` names the stored files that survive, and
  /// anything omitted is dropped.
  Future<String> saveWithFindings(
    Map<String, dynamic> payload, {
    List<http.MultipartFile> attachments = const [],
  }) async {
    try {
      final res = await pb
          .send<Map<String, dynamic>>(
            '/api/federfall/microscopy',
            method: 'POST',
            body: payload,
            files: attachments,
          )
          .timeout(networkTimeout);
      final id = res['id'] as String?;
      if (id == null || id.isEmpty) {
        throw const RepositoryException('malformed microscopy save response');
      }
      return id;
    } on TimeoutException {
      // The request left the device; a slow server may still commit the
      // sample, so a blind retry of a create can duplicate it.
      throw const RepositoryException(
        'The server did not respond in time — the microscopy record may or '
        'may not have been saved',
        kind: RepositoryErrorKind.unknownOutcome,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }
}

/// Repository over the `microscopy_findings` collection (one graded finding on
/// a [MicroscopySample]).
///
/// Findings are written as a set through
/// [PbMicroscopySamplesRepository.saveWithFindings]; this repository reads
/// them and counts vocabulary references.
class PbMicroscopyFindingsRepository extends PbRepository<MicroscopyFinding> {
  PbMicroscopyFindingsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'microscopy_findings',
        fromRecord: MicroscopyFinding.fromRecord,
      );

  /// Findings for a single sample (for the edit sheet), in insertion order.
  Future<List<MicroscopyFinding>> forSample(String sampleId) => list(
    filter: filterExpr('sample = {:s}', {'s': sampleId}),
    sort: 'created',
  );

  /// Every finding across all the case's samples in ONE query (traversing the
  /// grandparent `sample.case`), for the caller to group client-side under each
  /// sample — avoids a per-sample round trip on the timeline.
  Future<List<MicroscopyFinding>> forCase(String caseId) => list(
    filter: filterExpr('sample.case = {:c}', {'c': caseId}),
    sort: 'created',
  );

  /// How many findings reference the vocabulary entry [typeId] — the number the
  /// code-list delete confirmation states.
  ///
  /// `finding_type` is an optional relation with `cascadeDelete: false`, so
  /// deleting the entry does not delete these rows: PocketBase blanks the field
  /// and each finding keeps its severity. So this informs rather than blocks
  /// (the `conditions` behaviour, not `marking_types`').
  Future<int> countForType(String typeId) =>
      count(filter: filterExpr('finding_type = {:t}', {'t': typeId}));
}

/// Repository over the `microscopy_finding_types` code list (the
/// supervisor-managed vocabulary of microscopic findings).
///
/// Applicability to the chosen sample type is filtered on the device rather
/// than in the query: the list is a handful of rows the sheet already holds,
/// and `sample_types` is a multi-select whose `?=` filter would have to be
/// rebuilt every time the probe segment changes.
class PbMicroscopyFindingTypesRepository
    extends PbRepository<MicroscopyFindingType>
    with CodelistRepository<MicroscopyFindingType> {
  PbMicroscopyFindingTypesRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'microscopy_finding_types',
        fromRecord: MicroscopyFindingType.fromRecord,
      );

  @override
  String labelOf(MicroscopyFindingType entry) => entry.label;
}

import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'carer_case_load.freezed.dart';

/// One member's open caseload, read from the `case_carer_load` view
/// (federfall-s0wk): how many non-disposed cases they are the active carer of.
///
/// The view is org-wide by construction and its list rule admits only
/// coordinators and supervisors, so a carer simply receives no rows — an empty
/// result here is the access rules answering, not a failed read.
///
/// [id] is the view's composite `org:carer` key, not a record id: a member who
/// carries cases in two orgs has one row per org, and a view's id must be
/// unique across the whole result. Join on [carer].
@freezed
abstract class CarerCaseLoad with _$CarerCaseLoad {
  const factory CarerCaseLoad({
    required String id,
    required String carer,
    @Default(0) int openCases,
    String? org,
  }) = _CarerCaseLoad;

  factory CarerCaseLoad.fromRecord(RecordModel r) {
    final d = r.data;
    return CarerCaseLoad(
      id: r.id,
      carer: pbString(d['carer']) ?? '',
      openCases: pbInt(d['open_cases']) ?? 0,
      org: pbString(d['org']),
    );
  }
}
